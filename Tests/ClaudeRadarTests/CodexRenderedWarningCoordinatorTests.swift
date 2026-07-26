import Foundation
import SwiftData
import Testing
@testable import ClaudeRadar

@Suite("CodexRenderedWarningCoordinatorTests", .serialized)
struct CodexRenderedWarningCoordinatorTests {
    @MainActor
    @Test("a successful render is persisted and published")
    func successfulRender() async throws {
        let fixture = try warningCoordinatorFixture()
        let snapshot = try renderedWarning(capturedAt: fixture.clock.now())
        let reader = WarningReaderProbe(results: [.success(snapshot)])
        let publications = WarningPublicationRecorder()
        let coordinator = CodexRenderedWarningCoordinator(
            reader: reader,
            repository: fixture.repository,
            clock: fixture.clock,
            projectionDidChange: { state, history in
                await publications.append(state: state, history: history)
            }
        )

        await coordinator.refresh(trigger: .startup)

        #expect(reader.readCount == 1)
        #expect(try await fixture.repository.snapshotCount(
            datasetType: .renderedWarnings,
            sourceID: .codexRadar
        ) == 1)
        #expect(await publications.lastState?.value == snapshot)
        #expect(await publications.lastHistory == [snapshot])
    }

    @MainActor
    @Test("a trigger burst joins one in-flight render")
    func triggerBurstCoalesces() async throws {
        let fixture = try warningCoordinatorFixture()
        let snapshot = try renderedWarning(capturedAt: fixture.clock.now())
        let gate = WarningReadGate()
        let reader = GatedWarningReader(gate: gate)
        let coordinator = CodexRenderedWarningCoordinator(
            reader: reader,
            repository: fixture.repository,
            clock: fixture.clock
        )

        let first = Task { await coordinator.refresh(trigger: .periodic) }
        await gate.waitUntilStarted()
        let joined = [
            SyncTrigger.startup, .manual, .periodic, .networkRecovery, .sleepRecovery,
        ].map { trigger in
            Task { await coordinator.refresh(trigger: trigger) }
        }
        await gate.succeed(snapshot)
        await first.value
        for task in joined { await task.value }

        #expect(await gate.readCount == 1)
        #expect(try await fixture.repository.snapshotCount(
            datasetType: .renderedWarnings,
            sourceID: .codexRadar
        ) == 1)
    }

    @MainActor
    @Test("duplicate success refreshes metadata without adding history")
    func duplicateSuccess() async throws {
        let fixture = try warningCoordinatorFixture(now: Date(timeIntervalSince1970: 100))
        let original = try renderedWarning(capturedAt: Date(timeIntervalSince1970: 10))
        let duplicate = try renderedWarning(capturedAt: fixture.clock.now())
        _ = try await fixture.repository.insertRenderedWarning(original)
        let reader = WarningReaderProbe(results: [.success(duplicate)])
        let coordinator = CodexRenderedWarningCoordinator(
            reader: reader,
            repository: fixture.repository,
            clock: fixture.clock
        )

        await coordinator.refresh(trigger: .manual)

        let metadata = try await fixture.repository.metadata(
            sourceID: .codexRadar,
            datasetType: .renderedWarnings
        )
        #expect(try await fixture.repository.renderedWarningHistory(sourceID: .codexRadar) == [original])
        #expect(metadata.lastAttemptedAt == duplicate.capturedAt)
        #expect(metadata.lastSuccessfulAt == duplicate.capturedAt)
        #expect(metadata.lastError == nil)
    }

    @MainActor
    @Test("failure publishes typed error with LKG and without LKG")
    func failureProjectionMatrix() async throws {
        for hasLKG in [false, true] {
            let fixture = try warningCoordinatorFixture()
            let prior = try renderedWarning(
                sourceTimeLabel: "cached",
                capturedAt: fixture.clock.now().addingTimeInterval(-10)
            )
            if hasLKG {
                _ = try await fixture.repository.insertRenderedWarning(prior)
            }
            let reader = WarningReaderProbe(results: [
                .failure(CodexRenderedWarningPageReaderError.validation(.revisionMismatch)),
            ])
            let publications = WarningPublicationRecorder()
            let coordinator = CodexRenderedWarningCoordinator(
                reader: reader,
                repository: fixture.repository,
                clock: fixture.clock,
                projectionDidChange: { state, history in
                    await publications.append(state: state, history: history)
                }
            )

            await coordinator.refresh(trigger: .manual)

            #expect(await publications.lastState?.value == (hasLKG ? prior : nil))
            #expect(await publications.lastState?.error?.kind == .validation)
            #expect(await publications.lastHistory == (hasLKG ? [prior] : []))
        }
    }

    @Test("projection uses the existing stale interval")
    func staleProjection() async throws {
        let fixture = try warningCoordinatorFixture(now: Date(timeIntervalSince1970: 10_000))
        let prior = try renderedWarning(capturedAt: Date(timeIntervalSince1970: 6_399))
        _ = try await fixture.repository.insertRenderedWarning(prior)
        let coordinator = await CodexRenderedWarningCoordinator(
            reader: WarningReaderProbe(results: []),
            repository: fixture.repository,
            policy: SyncPolicy(refreshInterval: 30 * 60),
            clock: fixture.clock
        )

        let projection = try await coordinator.projection()

        #expect(projection.state.value == prior)
        #expect(projection.state.isStale)
    }

    @MainActor
    @Test("periodic obeys backoff while manual bypasses it")
    func backoffAndManualPriority() async throws {
        let fixture = try warningCoordinatorFixture()
        let snapshot = try renderedWarning(capturedAt: fixture.clock.now())
        let reader = WarningReaderProbe(results: [
            .failure(WarningTestError.offline),
            .success(snapshot),
        ])
        let coordinator = CodexRenderedWarningCoordinator(
            reader: reader,
            repository: fixture.repository,
            clock: fixture.clock
        )

        await coordinator.refresh(trigger: .periodic)
        await coordinator.refresh(trigger: .periodic)
        #expect(reader.readCount == 1)
        await coordinator.refresh(trigger: .manual)

        #expect(reader.readCount == 2)
        #expect(try await fixture.repository.snapshotCount(
            datasetType: .renderedWarnings,
            sourceID: .codexRadar
        ) == 1)
    }

    @MainActor
    @Test("stop during a suspended read fences late persistence and publication")
    func stopDuringRead() async throws {
        let fixture = try warningCoordinatorFixture()
        let snapshot = try renderedWarning(capturedAt: fixture.clock.now())
        let gate = WarningReadGate()
        let reader = GatedWarningReader(gate: gate)
        let publications = WarningPublicationRecorder()
        let coordinator = CodexRenderedWarningCoordinator(
            reader: reader,
            repository: fixture.repository,
            clock: fixture.clock,
            projectionDidChange: { state, history in
                await publications.append(state: state, history: history)
            }
        )
        let refresh = Task { await coordinator.refresh(trigger: .manual) }
        await gate.waitUntilStarted()

        let stopping = Task { await coordinator.stop() }
        while !(await coordinator.lifecycleState()).isStopped { await Task.yield() }
        await gate.succeed(snapshot)
        await stopping.value
        await refresh.value

        #expect(try await fixture.repository.snapshotCount(
            datasetType: .renderedWarnings,
            sourceID: .codexRadar
        ) == 0)
        #expect(await publications.count == 0)
        #expect(reader.cancelCount == 1)
    }

    @MainActor
    @Test("stop during the persistence phase fences the write")
    func stopDuringPersistence() async throws {
        let fixture = try warningCoordinatorFixture()
        let snapshot = try renderedWarning(capturedAt: fixture.clock.now())
        let reader = WarningReaderProbe(results: [.success(snapshot)])
        let gate = WarningPersistenceGate()
        let publications = WarningPublicationRecorder()
        let coordinator = CodexRenderedWarningCoordinator(
            reader: reader,
            repository: fixture.repository,
            clock: fixture.clock,
            projectionDidChange: { state, history in
                await publications.append(state: state, history: history)
            },
            persistenceCheckpoint: { await gate.pause() }
        )
        let refresh = Task { await coordinator.refresh(trigger: .manual) }
        await gate.waitUntilPaused()

        let stopping = Task { await coordinator.stop() }
        while !(await coordinator.lifecycleState()).isStopped { await Task.yield() }
        await gate.release()
        await stopping.value
        await refresh.value

        #expect(try await fixture.repository.snapshotCount(
            datasetType: .renderedWarnings,
            sourceID: .codexRadar
        ) == 0)
        #expect(await publications.count == 0)
    }
}

@MainActor
private final class WarningReaderProbe: CodexRenderedWarningReading {
    private(set) var readCount = 0
    private var results: [Result<CodexRenderedWarningSnapshot, Error>]

    init(results: [Result<CodexRenderedWarningSnapshot, Error>]) {
        self.results = results
    }

    func read() async throws -> CodexRenderedWarningSnapshot {
        readCount += 1
        return try results.removeFirst().get()
    }

    func cancel() {}
}

private actor WarningPublicationRecorder {
    private(set) var lastState: SegmentState<CodexRenderedWarningSnapshot>?
    private(set) var lastHistory: [CodexRenderedWarningSnapshot] = []
    private(set) var count = 0

    func append(
        state: SegmentState<CodexRenderedWarningSnapshot>,
        history: [CodexRenderedWarningSnapshot]
    ) {
        count += 1
        lastState = state
        lastHistory = history
    }
}

private enum WarningTestError: Error {
    case offline
}

private actor WarningReadGate {
    private(set) var readCount = 0
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<CodexRenderedWarningSnapshot, Error>?
    private var pendingResult: Result<CodexRenderedWarningSnapshot, Error>?

    func read() async throws -> CodexRenderedWarningSnapshot {
        readCount += 1
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        if let pendingResult {
            self.pendingResult = nil
            return try pendingResult.get()
        }
        return try await withCheckedThrowingContinuation { resultContinuation = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func succeed(_ snapshot: CodexRenderedWarningSnapshot) {
        if let resultContinuation {
            self.resultContinuation = nil
            resultContinuation.resume(returning: snapshot)
        } else {
            pendingResult = .success(snapshot)
        }
    }
}

@MainActor
private final class GatedWarningReader: CodexRenderedWarningReading {
    private let gate: WarningReadGate
    private(set) var cancelCount = 0

    init(gate: WarningReadGate) {
        self.gate = gate
    }

    func read() async throws -> CodexRenderedWarningSnapshot {
        try await gate.read()
    }

    func cancel() {
        cancelCount += 1
    }
}

private actor WarningPersistenceGate {
    private var paused = false
    private var released = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        paused = true
        pauseWaiters.forEach { $0.resume() }
        pauseWaiters.removeAll()
        if released { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilPaused() async {
        if paused { return }
        await withCheckedContinuation { pauseWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private struct WarningCoordinatorFixture {
    let repository: RadarRepository
    let clock: WarningTestClock
}

private func warningCoordinatorFixture(
    now: Date = Date(timeIntervalSince1970: 50_000)
) throws -> WarningCoordinatorFixture {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "CodexRenderedWarningCoordinatorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let container = try RadarModelSchema.makeContainer(
        configuration: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return WarningCoordinatorFixture(
        repository: RadarRepository(container: container, metadataStore: SyncMetadataStore(root: root)),
        clock: WarningTestClock(now)
    )
}

private final class WarningTestClock: RadarClock, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    func now() -> Date {
        lock.withLock { date }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(interval) }
    }
}

private func renderedWarning(
    sourceTimeLabel: String = "刚刚",
    capturedAt: Date,
    iq: Double = 82
) throws -> CodexRenderedWarningSnapshot {
    let cards = [
        CodexRenderedWarningCard(
            displayName: "GPT-5 High",
            family: "gpt-5",
            effort: "high",
            sourceOrder: 0,
            iq: iq,
            drop24h: 3,
            drop48h: 5
        ),
    ]
    let fingerprint = try CodexRenderedWarningSemanticFingerprint.make(
        sourceTimeLabel: sourceTimeLabel,
        cards: cards,
        finalOrigin: "https://codexradar.com",
        parserRevision: "codex-radar-rendered-dom-v1"
    )
    return CodexRenderedWarningSnapshot(
        sourceID: .codexRadar,
        parserRevision: "codex-radar-rendered-dom-v1",
        finalOrigin: "https://codexradar.com",
        sourceTimeLabel: sourceTimeLabel,
        capturedAt: capturedAt,
        cards: cards,
        semanticFingerprint: fingerprint
    )
}
