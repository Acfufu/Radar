import Foundation
import SwiftData
import Testing
@testable import AIRadar

@Suite("CodexRenderedIQHistoryCoordinatorTests", .serialized)
struct CodexRenderedIQHistoryCoordinatorTests {
    @MainActor
    @Test("a successful render is persisted and published")
    func successfulRender() async throws {
        let fixture = try iqCoordinatorFixture()
        defer { fixture.cleanup() }
        let snapshot = try renderedIQHistory(capturedAt: fixture.clock.now())
        let reader = IQReaderProbe(results: [.success(snapshot)])
        let publications = IQPublicationRecorder()
        let coordinator = CodexRenderedIQHistoryCoordinator(
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
            datasetType: .renderedIQHistory,
            sourceID: .codexRadar
        ) == 1)
        #expect(await publications.lastState?.value == snapshot)
        #expect(await publications.lastHistory == [snapshot])
    }

    @MainActor
    @Test("duplicate success refreshes metadata without adding history")
    func duplicateSuccess() async throws {
        let fixture = try iqCoordinatorFixture(now: Date(timeIntervalSince1970: 100))
        defer { fixture.cleanup() }
        let original = try renderedIQHistory(capturedAt: Date(timeIntervalSince1970: 10))
        let duplicate = try renderedIQHistory(capturedAt: fixture.clock.now())
        _ = try await fixture.repository.insertRenderedIQHistory(original)
        let coordinator = CodexRenderedIQHistoryCoordinator(
            reader: IQReaderProbe(results: [.success(duplicate)]),
            repository: fixture.repository,
            clock: fixture.clock
        )

        await coordinator.refresh(trigger: .manual)

        let metadata = try await fixture.repository.metadata(
            sourceID: .codexRadar,
            datasetType: .renderedIQHistory
        )
        #expect(try await fixture.repository.renderedIQHistoryHistory(sourceID: .codexRadar) == [original])
        #expect(metadata.lastAttemptedAt == duplicate.capturedAt)
        #expect(metadata.lastSuccessfulAt == duplicate.capturedAt)
        #expect(metadata.lastError == nil)
    }

    @MainActor
    @Test("a trigger burst joins one in-flight render")
    func triggerBurstCoalesces() async throws {
        let fixture = try iqCoordinatorFixture()
        defer { fixture.cleanup() }
        let snapshot = try renderedIQHistory(capturedAt: fixture.clock.now())
        let gate = IQReadGate()
        let reader = GatedIQReader(gate: gate)
        let coordinator = CodexRenderedIQHistoryCoordinator(
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
    }

    @MainActor
    @Test("manual refresh overrides periodic backoff")
    func strongestTriggerWins() async throws {
        let fixture = try iqCoordinatorFixture()
        defer { fixture.cleanup() }
        let snapshot = try renderedIQHistory(capturedAt: fixture.clock.now())
        try await fixture.repository.recordBackoff(
            sourceID: .codexRadar,
            datasetType: .renderedIQHistory,
            until: fixture.clock.now().addingTimeInterval(3_600),
            failureCount: 1
        )
        let reader = IQReaderProbe(results: [.success(snapshot)])
        let coordinator = CodexRenderedIQHistoryCoordinator(
            reader: reader,
            repository: fixture.repository,
            clock: fixture.clock
        )

        await coordinator.refresh(trigger: .periodic)
        await coordinator.refresh(trigger: .manual)

        #expect(reader.readCount == 1)
    }

    @MainActor
    @Test("failure publishes typed error with LKG")
    func failurePublishesLKG() async throws {
        let fixture = try iqCoordinatorFixture()
        defer { fixture.cleanup() }
        let prior = try renderedIQHistory(capturedAt: fixture.clock.now().addingTimeInterval(-10))
        _ = try await fixture.repository.insertRenderedIQHistory(prior)
        let publications = IQPublicationRecorder()
        let coordinator = CodexRenderedIQHistoryCoordinator(
            reader: IQReaderProbe(results: [
                .failure(CodexRenderedIQHistoryPageReaderError.validation(.revisionMismatch)),
            ]),
            repository: fixture.repository,
            clock: fixture.clock,
            projectionDidChange: { state, history in
                await publications.append(state: state, history: history)
            }
        )

        await coordinator.refresh(trigger: .manual)

        #expect(await publications.lastState?.value == prior)
        #expect(await publications.lastState?.error?.kind == .validation)
        #expect(await publications.lastHistory == [prior])
    }

    @MainActor
    @Test("persisted projection loads without reading")
    func loadPersistedProjection() async throws {
        let fixture = try iqCoordinatorFixture()
        defer { fixture.cleanup() }
        let prior = try renderedIQHistory(capturedAt: fixture.clock.now().addingTimeInterval(-10))
        _ = try await fixture.repository.insertRenderedIQHistory(prior)
        let reader = IQReaderProbe(results: [])
        let publications = IQPublicationRecorder()
        let coordinator = CodexRenderedIQHistoryCoordinator(
            reader: reader,
            repository: fixture.repository,
            clock: fixture.clock,
            projectionDidChange: { state, history in
                await publications.append(state: state, history: history)
            }
        )

        let projection = try await coordinator.loadPersistedProjection()

        #expect(reader.readCount == 0)
        #expect(projection.state.value == prior)
        #expect(projection.history == [prior])
        #expect(await publications.lastState?.value == prior)
    }

    @MainActor
    @Test("periodic obeys backoff while manual bypasses it")
    func backoffAndManualPriority() async throws {
        let fixture = try iqCoordinatorFixture()
        defer { fixture.cleanup() }
        let snapshot = try renderedIQHistory(capturedAt: fixture.clock.now())
        let reader = IQReaderProbe(results: [
            .failure(IQTestError.offline),
            .success(snapshot),
        ])
        let coordinator = CodexRenderedIQHistoryCoordinator(
            reader: reader,
            repository: fixture.repository,
            clock: fixture.clock
        )

        await coordinator.refresh(trigger: .periodic)
        await coordinator.refresh(trigger: .periodic)
        #expect(reader.readCount == 1)
        await coordinator.refresh(trigger: .manual)

        #expect(reader.readCount == 2)
    }

    @MainActor
    @Test("stop during a suspended read fences late persistence and publication")
    func stopDuringRead() async throws {
        let fixture = try iqCoordinatorFixture()
        defer { fixture.cleanup() }
        let snapshot = try renderedIQHistory(capturedAt: fixture.clock.now())
        let gate = IQReadGate()
        let reader = GatedIQReader(gate: gate)
        let publications = IQPublicationRecorder()
        let coordinator = CodexRenderedIQHistoryCoordinator(
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
            datasetType: .renderedIQHistory,
            sourceID: .codexRadar
        ) == 0)
        #expect(await publications.count == 0)
        #expect(reader.cancelCount == 1)
    }

    @MainActor
    @Test("paused facade rejects triggers without reading")
    func pausedFacadeRejectsTriggers() async throws {
        let fixture = try iqCoordinatorFixture()
        defer { fixture.cleanup() }
        let snapshot = try renderedIQHistory(capturedAt: fixture.clock.now())
        let reader = IQReaderProbe(results: [.success(snapshot)])
        let coordinator = CodexRenderedIQHistoryCoordinator(
            reader: reader,
            repository: fixture.repository,
            clock: fixture.clock
        )

        await coordinator.pauseAndDrain()
        let paused = await coordinator.lifecycleState()
        await coordinator.refresh(trigger: .startup)
        await coordinator.refresh(trigger: .manual)

        #expect(paused.isPaused)
        #expect(!paused.isStopped)
        #expect(reader.readCount == 0)
        #expect(try await fixture.repository.snapshotCount(
            datasetType: .renderedIQHistory,
            sourceID: .codexRadar
        ) == 0)
    }

    @MainActor
    @Test("resume permits a later manual refresh through the IQ adapter")
    func resumePermitsManualRefresh() async throws {
        let fixture = try iqCoordinatorFixture()
        defer { fixture.cleanup() }
        let snapshot = try renderedIQHistory(capturedAt: fixture.clock.now())
        let reader = IQReaderProbe(results: [.success(snapshot)])
        let coordinator = CodexRenderedIQHistoryCoordinator(
            reader: reader,
            repository: fixture.repository,
            clock: fixture.clock
        )

        await coordinator.pauseAndDrain()
        await coordinator.refresh(trigger: .manual)
        await coordinator.resume()
        await coordinator.refresh(trigger: .manual)

        let lifecycle = await coordinator.lifecycleState()
        let metadata = try await fixture.repository.metadata(
            sourceID: .codexRadar,
            datasetType: .renderedIQHistory
        )
        #expect(!lifecycle.isPaused)
        #expect(reader.readCount == 1)
        #expect(try await fixture.repository.renderedIQHistoryHistory(sourceID: .codexRadar) == [snapshot])
        #expect(metadata.lastSuccessfulAt == snapshot.capturedAt)
        print("IQ_RESUME_COUNTERS read=\(reader.readCount) history=1 dataset=\(RadarDatasetType.renderedIQHistory.rawValue)")
    }

    @MainActor
    @Test("pause and drain fences a gated read and cancels the IQ reader")
    func pauseAndDrainDuringRead() async throws {
        let fixture = try iqCoordinatorFixture()
        defer { fixture.cleanup() }
        let snapshot = try renderedIQHistory(capturedAt: fixture.clock.now())
        let gate = IQReadGate()
        let reader = GatedIQReader(gate: gate)
        let publications = IQPublicationRecorder()
        let coordinator = CodexRenderedIQHistoryCoordinator(
            reader: reader,
            repository: fixture.repository,
            clock: fixture.clock,
            projectionDidChange: { state, history in
                await publications.append(state: state, history: history)
            }
        )
        let refresh = Task { await coordinator.refresh(trigger: .manual) }
        await gate.waitUntilStarted()

        let pausing = Task { await coordinator.pauseAndDrain() }
        while !(await coordinator.lifecycleState()).isPaused { await Task.yield() }
        await coordinator.refresh(trigger: .manual)
        await gate.succeed(snapshot)
        await pausing.value
        await refresh.value

        let lifecycle = await coordinator.lifecycleState()
        #expect(lifecycle.isPaused)
        #expect(!lifecycle.hasActiveTask)
        #expect(await gate.readCount == 1)
        #expect(reader.cancelCount == 1)
        #expect(try await fixture.repository.snapshotCount(
            datasetType: .renderedIQHistory,
            sourceID: .codexRadar
        ) == 0)
        #expect(await publications.count == 0)
        print("IQ_PAUSE_COUNTERS read=\(await gate.readCount) cancel=\(reader.cancelCount) insert=0 publication=\(await publications.count)")
    }

    @MainActor
    @Test("typed cancellation is suppressed and navigation timeout is network")
    func typedErrorMapping() async throws {
        let cancelledFixture = try iqCoordinatorFixture()
        defer { cancelledFixture.cleanup() }
        let cancelledCoordinator = CodexRenderedIQHistoryCoordinator(
            reader: IQReaderProbe(results: [
                .failure(CodexRenderedIQHistoryPageReaderError.cancelled),
            ]),
            repository: cancelledFixture.repository,
            clock: cancelledFixture.clock
        )

        await cancelledCoordinator.refresh(trigger: .manual)

        let cancelledMetadata = try await cancelledFixture.repository.metadata(
            sourceID: .codexRadar,
            datasetType: .renderedIQHistory
        )
        #expect(cancelledMetadata.lastError == nil)
        #expect(cancelledMetadata.consecutiveFailures == nil)
        #expect(cancelledMetadata.backoffUntil == nil)

        let timeoutFixture = try iqCoordinatorFixture()
        defer { timeoutFixture.cleanup() }
        let timeoutCoordinator = CodexRenderedIQHistoryCoordinator(
            reader: IQReaderProbe(results: [
                .failure(CodexRenderedIQHistoryPageReaderError.navigationTimeout),
            ]),
            repository: timeoutFixture.repository,
            clock: timeoutFixture.clock
        )

        await timeoutCoordinator.refresh(trigger: .manual)

        let timeoutMetadata = try await timeoutFixture.repository.metadata(
            sourceID: .codexRadar,
            datasetType: .renderedIQHistory
        )
        #expect(timeoutMetadata.lastError?.kind == .network)
        #expect(timeoutMetadata.lastError?.message == "The rendered Codex IQ history page could not be read")
        #expect(timeoutMetadata.consecutiveFailures == 1)
        #expect(timeoutMetadata.backoffUntil != nil)
        print("IQ_ERROR_COUNTERS cancelledFailures=\(cancelledMetadata.consecutiveFailures ?? -1) timeoutFailures=\(timeoutMetadata.consecutiveFailures ?? -1) timeoutKind=\(timeoutMetadata.lastError?.kind.rawValue ?? "nil")")
    }
}

@MainActor
private final class IQReaderProbe: CodexRenderedIQHistoryReading {
    private(set) var readCount = 0
    private var results: [Result<CodexRenderedIQHistorySnapshot, Error>]

    init(results: [Result<CodexRenderedIQHistorySnapshot, Error>]) {
        self.results = results
    }

    func read() async throws -> CodexRenderedIQHistorySnapshot {
        readCount += 1
        return try results.removeFirst().get()
    }

    func cancel() {}
}

private actor IQPublicationRecorder {
    private(set) var lastState: SegmentState<CodexRenderedIQHistorySnapshot>?
    private(set) var lastHistory: [CodexRenderedIQHistorySnapshot] = []
    private(set) var count = 0

    func append(
        state: SegmentState<CodexRenderedIQHistorySnapshot>,
        history: [CodexRenderedIQHistorySnapshot]
    ) {
        count += 1
        lastState = state
        lastHistory = history
    }
}

private enum IQTestError: Error {
    case offline
}

private actor IQReadGate {
    private(set) var readCount = 0
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<CodexRenderedIQHistorySnapshot, Error>?
    private var pendingResult: Result<CodexRenderedIQHistorySnapshot, Error>?

    func read() async throws -> CodexRenderedIQHistorySnapshot {
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

    func succeed(_ snapshot: CodexRenderedIQHistorySnapshot) {
        if let resultContinuation {
            self.resultContinuation = nil
            resultContinuation.resume(returning: snapshot)
        } else {
            pendingResult = .success(snapshot)
        }
    }
}

@MainActor
private final class GatedIQReader: CodexRenderedIQHistoryReading {
    private let gate: IQReadGate
    private(set) var cancelCount = 0

    init(gate: IQReadGate) {
        self.gate = gate
    }

    func read() async throws -> CodexRenderedIQHistorySnapshot {
        try await gate.read()
    }

    func cancel() {
        cancelCount += 1
    }
}

private struct IQCoordinatorFixture {
    let root: URL
    let repository: RadarRepository
    let clock: IQTestClock

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private func iqCoordinatorFixture(
    now: Date = Date(timeIntervalSince1970: 50_000)
) throws -> IQCoordinatorFixture {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "CodexRenderedIQHistoryCoordinatorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let container = try RadarModelSchema.makeContainer(
        configuration: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return IQCoordinatorFixture(
        root: root,
        repository: RadarRepository(container: container, metadataStore: SyncMetadataStore(root: root)),
        clock: IQTestClock(now)
    )
}

private final class IQTestClock: RadarClock, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    func now() -> Date {
        lock.withLock { date }
    }
}

private func renderedIQHistory(
    capturedAt: Date,
    iq: Double = 82
) throws -> CodexRenderedIQHistorySnapshot {
    let series = [
        CodexRenderedIQHistorySeries(
            sourceOrder: 0,
            seriesKey: "aggregate",
            displayName: "官网综合",
            points: (0..<24).map {
                CodexRenderedIQHistoryPoint(
                    sourceOrder: $0,
                    sourceTimeLabel: "\($0)h",
                    iq: iq
                )
            }
        ),
    ]
    let origin = "https://deng.codexradar.com"
    let revision = CodexRenderedIQHistoryDOMParser.parserRevision
    return CodexRenderedIQHistorySnapshot(
        sourceID: .codexRadar,
        parserRevision: revision,
        finalOrigin: origin,
        capturedAt: capturedAt,
        series: series,
        semanticFingerprint: try CodexRenderedIQHistorySemanticFingerprint.make(
            sourceID: .codexRadar,
            series: series,
            finalOrigin: origin,
            parserRevision: revision
        )
    )
}
