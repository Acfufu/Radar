import Foundation
import SwiftData
import Testing
@testable import ClaudeRadar

@Suite("CodexRenderedSyncCoreTests", .serialized)
struct CodexRenderedSyncCoreTests {
    @MainActor
    @Test("success and duplicate insert share one persisted history row")
    func successAndDuplicateInsert() async throws {
        let fixture = try coreFixture(now: Date(timeIntervalSince1970: 100))
        defer { fixture.cleanup() }
        let first = try coreSnapshot(capturedAt: Date(timeIntervalSince1970: 10))
        let duplicate = try coreSnapshot(capturedAt: fixture.clock.now())
        let counters = CoreCounters()
        let reader = CoreReader(results: [.success(first), .success(duplicate)], counters: counters)
        let publications = CorePublicationRecorder()
        let core = makeCore(
            fixture: fixture,
            reader: reader,
            counters: counters,
            projectionDidChange: { state, history in
                await publications.append(state: state, history: history)
            }
        )

        await core.refresh(trigger: .startup)
        await core.refresh(trigger: .manual)

        #expect(counters.snapshot().read == 2)
        #expect(counters.snapshot().insert == 2)
        #expect(try await fixture.repository.snapshotCount(
            datasetType: .renderedWarnings,
            sourceID: .codexRadar
        ) == 1)
        #expect(try await fixture.repository.renderedWarningHistory(sourceID: .codexRadar) == [first])
        #expect(try await fixture.repository.metadata(
            sourceID: .codexRadar,
            datasetType: .renderedWarnings
        ).lastAttemptedAt == duplicate.capturedAt)
        #expect(await publications.count == 2)
    }

    @MainActor
    @Test("persisted projection loads without reading and publishes")
    func persistedLoad() async throws {
        let fixture = try coreFixture()
        defer { fixture.cleanup() }
        let snapshot = try coreSnapshot(capturedAt: fixture.clock.now())
        _ = try await fixture.repository.insertRenderedWarning(snapshot)
        let counters = CoreCounters()
        let reader = CoreReader(results: [], counters: counters)
        let publications = CorePublicationRecorder()
        let core = makeCore(
            fixture: fixture,
            reader: reader,
            counters: counters,
            projectionDidChange: { state, history in
                await publications.append(state: state, history: history)
            }
        )

        let projection = try await core.loadPersistedProjection()

        #expect(counters.snapshot().read == 0)
        #expect(projection.0.value == snapshot)
        #expect(projection.1 == [snapshot])
        #expect(await publications.lastState?.value == snapshot)
    }

    @MainActor
    @Test("stale LKG and no-LKG failures preserve typed projection semantics")
    func failureProjectionMatrix() async throws {
        for hasLKG in [false, true] {
            let fixture = try coreFixture(now: Date(timeIntervalSince1970: 10_000))
            defer { fixture.cleanup() }
            let prior = try coreSnapshot(capturedAt: Date(timeIntervalSince1970: 6_399))
            if hasLKG { _ = try await fixture.repository.insertRenderedWarning(prior) }
            let counters = CoreCounters()
            let reader = CoreReader(results: [.failure(CoreTestError.network)], counters: counters)
            let publications = CorePublicationRecorder()
            let core = makeCore(
                fixture: fixture,
                reader: reader,
                counters: counters,
                policy: SyncPolicy(refreshInterval: 30 * 60),
                projectionDidChange: { state, history in
                    await publications.append(state: state, history: history)
                }
            )

            await core.refresh(trigger: .manual)

            #expect(await publications.lastState?.value == (hasLKG ? prior : nil))
            #expect(await publications.lastState?.error?.kind == .network)
            #expect(await publications.lastState?.isStale == true)
            #expect(await publications.lastHistory == (hasLKG ? [prior] : []))
        }
    }

    @MainActor
    @Test("adapter cancellation suppression and error classification are dataset-specific")
    func cancellationAndErrorClassification() async throws {
        let fixture = try coreFixture()
        defer { fixture.cleanup() }
        let counters = CoreCounters()
        let reader = CoreReader(
            results: [.failure(CoreTestError.cancelled), .failure(CoreTestError.network)],
            counters: counters
        )
        let core = makeCore(fixture: fixture, reader: reader, counters: counters)

        await core.refresh(trigger: .manual)
        let afterCancellation = try await fixture.repository.metadata(
            sourceID: .codexRadar,
            datasetType: .renderedWarnings
        )
        #expect(afterCancellation.lastError == nil)

        await core.refresh(trigger: .manual)
        let afterNetworkError = try await fixture.repository.metadata(
            sourceID: .codexRadar,
            datasetType: .renderedWarnings
        )
        #expect(afterNetworkError.lastError?.kind == .network)
        #expect(afterNetworkError.lastError?.message == "core warning failure")
        #expect(counters.snapshot().error == 1)
    }

    @MainActor
    @Test("periodic backoff is enforced while manual refresh bypasses it")
    func backoffAndManualBypass() async throws {
        let fixture = try coreFixture()
        defer { fixture.cleanup() }
        let snapshot = try coreSnapshot(capturedAt: fixture.clock.now())
        let counters = CoreCounters()
        let reader = CoreReader(
            results: [.failure(CoreTestError.network), .success(snapshot)],
            counters: counters
        )
        let core = makeCore(fixture: fixture, reader: reader, counters: counters)

        await core.refresh(trigger: .periodic)
        await core.refresh(trigger: .periodic)
        #expect(counters.snapshot().read == 1)
        await core.refresh(trigger: .manual)

        #expect(counters.snapshot().read == 2)
        #expect(try await fixture.repository.snapshotCount(
            datasetType: .renderedWarnings,
            sourceID: .codexRadar
        ) == 1)
    }

    @MainActor
    @Test("active task is installed before acquisition begins")
    func activeTaskInstalledBeforeAcquisition() async throws {
        let fixture = try coreFixture()
        defer { fixture.cleanup() }
        let counters = CoreCounters()
        let reader = CoreReader(results: [], counters: counters)
        let eligibilityGate = CoreAsyncGate()
        let core = makeCore(
            fixture: fixture,
            reader: reader,
            counters: counters,
            eligibilityCheckpoint: { _, _ in await eligibilityGate.pause() }
        )

        let refresh = Task { await core.refresh(trigger: .periodic) }
        await eligibilityGate.waitUntilPaused()

        #expect((await core.lifecycleState()).hasActiveTask)
        #expect(counters.snapshot().read == 0)
        let stopping = Task { await core.stop() }
        await eligibilityGate.release()
        await stopping.value
        await refresh.value
    }

    @MainActor
    @Test("stop fences a suspended read")
    func stopDuringRead() async throws {
        let fixture = try coreFixture()
        defer { fixture.cleanup() }
        let snapshot = try coreSnapshot(capturedAt: fixture.clock.now())
        let counters = CoreCounters()
        let gate = CoreReadGate(counters: counters)
        let reader = GatedCoreReader(gate: gate)
        let publications = CorePublicationRecorder()
        let core = makeCore(
            fixture: fixture,
            reader: reader,
            counters: counters,
            projectionDidChange: { state, history in
                await publications.append(state: state, history: history)
            }
        )
        let refresh = Task { await core.refresh(trigger: .manual) }
        await gate.waitUntilStarted()

        let stopping = Task { await core.stop() }
        while !(await core.lifecycleState()).isStopped { await Task.yield() }
        await gate.succeed(snapshot)
        await stopping.value
        await refresh.value

        #expect(counters.snapshot().insert == 0)
        #expect(await publications.count == 0)
        #expect(reader.cancelCount == 1)
    }

    @MainActor
    @Test("stop fences the persistence boundary")
    func stopDuringPersistence() async throws {
        let fixture = try coreFixture()
        defer { fixture.cleanup() }
        let snapshot = try coreSnapshot(capturedAt: fixture.clock.now())
        let counters = CoreCounters()
        let reader = CoreReader(results: [.success(snapshot)], counters: counters)
        let persistenceGate = CoreAsyncGate()
        let core = makeCore(
            fixture: fixture,
            reader: reader,
            counters: counters,
            persistenceCheckpoint: { await persistenceGate.pause() }
        )
        let refresh = Task { await core.refresh(trigger: .manual) }
        await persistenceGate.waitUntilPaused()

        let stopping = Task { await core.stop() }
        while !(await core.lifecycleState()).isStopped { await Task.yield() }
        await persistenceGate.release()
        await stopping.value
        await refresh.value

        #expect(counters.snapshot().insert == 0)
    }

    @MainActor
    @Test("pause drains work, rejects triggers, and resume accepts a later refresh")
    func pauseDrainResume() async throws {
        let fixture = try coreFixture()
        defer { fixture.cleanup() }
        let snapshot = try coreSnapshot(capturedAt: fixture.clock.now())
        let counters = CoreCounters()
        let reader = CoreReader(results: [.success(snapshot), .success(snapshot)], counters: counters)
        let persistenceGate = CoreAsyncGate()
        let core = makeCore(
            fixture: fixture,
            reader: reader,
            counters: counters,
            persistenceCheckpoint: { await persistenceGate.pause() }
        )
        let refresh = Task { await core.refresh(trigger: .manual) }
        await persistenceGate.waitUntilPaused()

        let pausing = Task { await core.pauseAndDrain() }
        while !(await core.lifecycleState()).isPaused { await Task.yield() }
        await persistenceGate.release()
        await pausing.value
        await refresh.value
        await core.refresh(trigger: .manual)
        #expect(counters.snapshot().read == 1)
        #expect(counters.snapshot().insert == 0)

        await core.resume()
        await core.refresh(trigger: .manual)
        #expect(counters.snapshot().read == 2)
        #expect(counters.snapshot().insert == 1)
    }

    @MainActor
    @Test("concurrent pause callers join one drain")
    func concurrentPauseJoins() async throws {
        let fixture = try coreFixture()
        defer { fixture.cleanup() }
        let snapshot = try coreSnapshot(capturedAt: fixture.clock.now())
        let counters = CoreCounters()
        let gate = CoreReadGate(counters: counters)
        let reader = GatedCoreReader(gate: gate)
        let core = makeCore(fixture: fixture, reader: reader, counters: counters)
        let refresh = Task { await core.refresh(trigger: .manual) }
        await gate.waitUntilStarted()

        let firstPause = Task { await core.pauseAndDrain() }
        while !(await core.lifecycleState()).isPaused { await Task.yield() }
        let secondPause = Task { await core.pauseAndDrain() }
        await Task.yield()
        #expect(reader.cancelCount == 1)
        await gate.succeed(snapshot)
        await firstPause.value
        await secondPause.value
        await refresh.value

        #expect(reader.cancelCount == 1)
        #expect(counters.snapshot().insert == 0)
    }

    @MainActor
    @Test("M6 delayed manual after ineligible periodic performs exactly one residual read")
    func delayedManualAfterIneligiblePeriodic() async throws {
        let fixture = try coreFixture()
        defer { fixture.cleanup() }
        let snapshot = try coreSnapshot(capturedAt: fixture.clock.now())
        try await fixture.repository.recordBackoff(
            sourceID: .codexRadar,
            datasetType: .renderedWarnings,
            until: fixture.clock.now().addingTimeInterval(3_600),
            failureCount: 1
        )
        let counters = CoreCounters()
        let reader = CoreReader(results: [.success(snapshot)], counters: counters)
        let eligibilityGate = CoreAsyncGate()
        let core = makeCore(
            fixture: fixture,
            reader: reader,
            counters: counters,
            eligibilityCheckpoint: { trigger, eligible in
                if trigger == .periodic, !eligible { await eligibilityGate.pause() }
            }
        )

        let periodic = Task { await core.refresh(trigger: .periodic) }
        await eligibilityGate.waitUntilPaused()
        #expect(counters.snapshot().read == 0)
        let manual = Task { await core.refresh(trigger: .manual) }
        await Task.yield()
        await eligibilityGate.release()
        await periodic.value
        await manual.value

        let metadata = try await fixture.repository.metadata(
            sourceID: .codexRadar,
            datasetType: .renderedWarnings
        )
        let counts = counters.snapshot()
        #expect(counts.read == 1)
        #expect(counts.insert == 1)
        #expect(metadata.lastAttemptedAt == snapshot.capturedAt)
        #expect(metadata.lastSuccessfulAt == snapshot.capturedAt)
        #expect(metadata.lastError == nil)
        print("M6_COUNTERS read=\(counts.read) insert=\(counts.insert) state=\(counts.state) history=\(counts.history) error=\(counts.error) metadataAttemptedAt=\(metadata.lastAttemptedAt?.timeIntervalSince1970 ?? -1)")
    }
}

@MainActor
private protocol CoreReading: AnyObject {
    func read() async throws -> CodexRenderedWarningSnapshot
    func cancel()
}

@MainActor
private final class CoreReader: CoreReading {
    private var results: [Result<CodexRenderedWarningSnapshot, Error>]
    private let counters: CoreCounters
    private(set) var cancelCount = 0

    init(results: [Result<CodexRenderedWarningSnapshot, Error>], counters: CoreCounters) {
        self.results = results
        self.counters = counters
    }

    func read() async throws -> CodexRenderedWarningSnapshot {
        counters.incrementRead()
        return try results.removeFirst().get()
    }

    func cancel() { cancelCount += 1 }
}

@MainActor
private final class GatedCoreReader: CoreReading {
    private let gate: CoreReadGate
    private(set) var cancelCount = 0

    init(gate: CoreReadGate) { self.gate = gate }

    func read() async throws -> CodexRenderedWarningSnapshot { try await gate.read() }

    func cancel() { cancelCount += 1 }
}

private actor CoreReadGate {
    private let counters: CoreCounters
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<CodexRenderedWarningSnapshot, Error>?

    init(counters: CoreCounters) { self.counters = counters }

    func read() async throws -> CodexRenderedWarningSnapshot {
        counters.incrementRead()
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return try await withCheckedThrowingContinuation { resultContinuation = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func succeed(_ snapshot: CodexRenderedWarningSnapshot) {
        resultContinuation?.resume(returning: snapshot)
        resultContinuation = nil
    }
}

private actor CoreAsyncGate {
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

private actor CorePublicationRecorder {
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

private final class CoreCounters: @unchecked Sendable {
    struct Values {
        var read = 0
        var insert = 0
        var state = 0
        var history = 0
        var error = 0
    }

    private let lock = NSLock()
    private var values = Values()

    func incrementRead() { lock.withLock { values.read += 1 } }
    func incrementInsert() { lock.withLock { values.insert += 1 } }
    func incrementState() { lock.withLock { values.state += 1 } }
    func incrementHistory() { lock.withLock { values.history += 1 } }
    func incrementError() { lock.withLock { values.error += 1 } }
    func snapshot() -> Values { lock.withLock { values } }
}

private enum CoreTestError: Error {
    case cancelled
    case network
}

private struct CoreFixture {
    let root: URL
    let repository: RadarRepository
    let clock: CoreTestClock

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}

private func coreFixture(
    now: Date = Date(timeIntervalSince1970: 50_000)
) throws -> CoreFixture {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "CodexRenderedSyncCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let container = try RadarModelSchema.makeContainer(
        configuration: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return CoreFixture(
        root: root,
        repository: RadarRepository(container: container, metadataStore: SyncMetadataStore(root: root)),
        clock: CoreTestClock(now)
    )
}

private final class CoreTestClock: RadarClock, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) { self.date = date }

    func now() -> Date { lock.withLock { date } }
}

@MainActor
private func makeCore(
    fixture: CoreFixture,
    reader: any CoreReading,
    counters: CoreCounters,
    policy: SyncPolicy = SyncPolicy(),
    projectionDidChange: (@Sendable (
        SegmentState<CodexRenderedWarningSnapshot>,
        [CodexRenderedWarningSnapshot]
    ) async -> Void)? = nil,
    persistenceCheckpoint: (@Sendable () async -> Void)? = nil,
    eligibilityCheckpoint: (@Sendable (SyncTrigger, Bool) async -> Void)? = nil
) -> CodexRenderedSyncCore<CodexRenderedWarningSnapshot> {
    let repository = fixture.repository
    let adapter = CodexRenderedSyncAdapter<CodexRenderedWarningSnapshot>(
        sourceID: .codexRadar,
        datasetType: .renderedWarnings,
        read: { try await reader.read() },
        cancel: { reader.cancel() },
        insert: { snapshot in
            counters.incrementInsert()
            return try await repository.insertRenderedWarning(snapshot)
        },
        loadState: {
            counters.incrementState()
            return try await repository.renderedWarningState(sourceID: .codexRadar)
        },
        loadHistory: {
            counters.incrementHistory()
            return try await repository.renderedWarningHistory(sourceID: .codexRadar)
        },
        isCancellation: { error in
            error is CancellationError || (error as? CoreTestError) == .cancelled
        },
        segmentError: { _ in
            counters.incrementError()
            return SegmentError(kind: .network, message: "core warning failure")
        },
        projectionDidChange: projectionDidChange
    )
    return CodexRenderedSyncCore(
        adapter: adapter,
        repository: repository,
        policy: policy,
        clock: fixture.clock,
        persistenceCheckpoint: persistenceCheckpoint,
        eligibilityCheckpoint: eligibilityCheckpoint
    )
}

private func coreSnapshot(capturedAt: Date) throws -> CodexRenderedWarningSnapshot {
    let cards = [
        CodexRenderedWarningCard(
            displayName: "GPT-5 High",
            family: "gpt-5",
            effort: "high",
            sourceOrder: 0,
            iq: 82,
            drop24h: 3,
            drop48h: 5
        ),
    ]
    let origin = "https://codexradar.com"
    let revision = "codex-radar-rendered-dom-v1"
    let sourceTimeLabel = "刚刚"
    return CodexRenderedWarningSnapshot(
        sourceID: .codexRadar,
        parserRevision: revision,
        finalOrigin: origin,
        sourceTimeLabel: sourceTimeLabel,
        capturedAt: capturedAt,
        cards: cards,
        semanticFingerprint: try CodexRenderedWarningSemanticFingerprint.make(
            sourceTimeLabel: sourceTimeLabel,
            cards: cards,
            finalOrigin: origin,
            parserRevision: revision
        )
    )
}
