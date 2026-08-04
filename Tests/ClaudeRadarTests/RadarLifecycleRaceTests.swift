import Foundation
import SwiftData
import Testing
@testable import ClaudeRadar

@Suite("RadarLifecycleRaceTests", .serialized)
struct RadarLifecycleRaceTests {
    @MainActor
    @Test("Codex runtime stop fences a warning read that completes late")
    func codexRuntimeStopFencesLateWarningRead() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "RadarLifecycleRaceTests-WarningRead-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = LifecycleWarningGate()
        let reader = LifecycleWarningReader(gate: gate)
        let runtime = RadarAppRuntime(
            environment: AppEnvironment(dataRoot: root, fixtureMode: .codex, onlineSourceEnabled: true),
            sourceID: .codexRadar,
            renderedWarningReaderFactory: { reader }
        )
        let starting = Task { await runtime.start() }
        await gate.waitUntilStarted()

        let stopping = Task { await runtime.stop() }
        while runtime.lifecycleState != .stopping { await Task.yield() }
        await gate.succeed(try lifecycleWarning(capturedAt: Date(timeIntervalSince1970: 100)))
        await stopping.value
        await starting.value

        let repository = RadarRepository(
            container: try AppEnvironment(
                dataRoot: root,
                fixtureMode: .disabled,
                onlineSourceEnabled: false
            ).makeModelContainer(),
            metadataStore: SyncMetadataStore(root: root)
        )
        #expect(runtime.lifecycleState == .stopped)
        #expect(runtime.renderedWarningProjection?.value == nil)
        #expect(runtime.renderedWarningProjection?.error == nil)
        #expect(runtime.renderedWarningHistory.isEmpty)
        #expect(try await repository.snapshotCount(
            datasetType: .renderedWarnings,
            sourceID: .codexRadar
        ) == 0)
        #expect(reader.cancelCount == 1)
    }

    @MainActor
    @Test("Codex runtime stop fences an IQ history read that completes late")
    func codexRuntimeStopFencesLateIQHistoryRead() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "RadarLifecycleRaceTests-IQHistoryRead-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = LifecycleIQHistoryGate()
        let reader = LifecycleIQHistoryReader(gate: gate)
        let runtime = RadarAppRuntime(
            environment: AppEnvironment(dataRoot: root, fixtureMode: .codex, onlineSourceEnabled: true),
            sourceID: .codexRadar,
            renderedIQHistoryReaderFactory: { reader }
        )
        let starting = Task { await runtime.start() }
        await gate.waitUntilStarted()

        let stopping = Task { await runtime.stop() }
        while runtime.lifecycleState != .stopping { await Task.yield() }
        await gate.succeed(try lifecycleIQHistory(capturedAt: Date(timeIntervalSince1970: 100)))
        await stopping.value
        await starting.value

        let repository = RadarRepository(
            container: try AppEnvironment(
                dataRoot: root,
                fixtureMode: .disabled,
                onlineSourceEnabled: false
            ).makeModelContainer(),
            metadataStore: SyncMetadataStore(root: root)
        )
        #expect(runtime.lifecycleState == .stopped)
        #expect(runtime.renderedIQHistoryProjection?.value == nil)
        #expect(runtime.renderedIQHistoryProjection?.error == nil)
        #expect(runtime.renderedIQHistoryHistory.isEmpty)
        #expect(try await repository.snapshotCount(
            datasetType: .renderedIQHistory,
            sourceID: .codexRadar
        ) == 0)
        #expect(reader.cancelCount == 1)
    }

    @MainActor
    @Test("startup failure stops and cancels the Codex warning coordinator")
    func codexStartupFailureCleansWarningCoordinator() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "RadarLifecycleRaceTests-WarningFailure-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = LifecycleImmediateWarningReader()
        let runtime = RadarAppRuntime(
            environment: AppEnvironment(dataRoot: root, fixtureMode: .codex, onlineSourceEnabled: true),
            sourceID: .codexRadar,
            startupLoadCheckpoint: { _ in throw StartupLoadFailure.injected },
            renderedWarningReaderFactory: { reader }
        )

        await runtime.start()

        #expect(runtime.lifecycleState == .failed)
        #expect(reader.readCount == 1)
        #expect(reader.cancelCount == 1)
        await runtime.stop()
        #expect(runtime.lifecycleState == .stopped)
    }

    @MainActor
    @Test("runtime stop is bounded while a cancelled start checkpoint ignores cancellation")
    func runtimeStopDoesNotAwaitStartCheckpoint() async throws {
        // Given
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let gate = LifecycleGate()
        let completion = LifecycleCompletion()
        let runtime = RadarAppRuntime(
            environment: AppEnvironment(dataRoot: root, fixtureMode: .sequence, onlineSourceEnabled: true),
            startCheckpoint: { await gate.pause() }
        )
        let starting = Task { await runtime.start() }
        await gate.waitUntilPaused()

        // When
        let stopping = Task {
            await runtime.stop()
            await completion.finish()
        }
        let stopCompleted = await completion.waitUntilFinished(for: .seconds(1))

        // Then
        #expect(stopCompleted)
        #expect(runtime.lifecycleState == .stopped)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "sync-segments.json").path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "request-counts.json").path))
        await gate.release()
        await starting.value
        await stopping.value
        await runtime.stop()
        #expect(runtime.lifecycleState == .stopped)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "sync-segments.json").path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "request-counts.json").path))
    }

    @MainActor
    @Test("startup load failure stops coordinator triggers and active work before reporting failure")
    func startupLoadFailureCleansCoordinator() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = CoordinatorProbe()
        let runtime = RadarAppRuntime(
            environment: AppEnvironment(dataRoot: root, fixtureMode: .sequence, onlineSourceEnabled: true),
            startupLoadCheckpoint: { coordinator in
                await probe.capture(coordinator)
                throw StartupLoadFailure.injected
            }
        )

        await runtime.start()

        let coordinator = try #require(await probe.coordinator)
        let state = await coordinator.lifecycleState()
        #expect(runtime.lifecycleState == .failed)
        #expect(state.isStopped)
        #expect(!state.hasActiveTask)
        await runtime.stop()
        #expect(runtime.lifecycleState == .stopped)
    }

    @MainActor
    @Test("runtime stop cancels and drains active export staging before shutdown completes")
    func runtimeStopDrainsExport() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let archiver = LifecycleExportArchiver()
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .disabled, onlineSourceEnabled: false)
        let runtime = RadarAppRuntime(environment: environment, exportArchiver: archiver)
        await runtime.start()
        let destination = root.appending(path: "quit.zip")
        let exporting = Task {
            try await runtime.export(request: .init(destination: destination, datasets: [.models])) { _ in }
        }
        await archiver.waitUntilStarted()

        await runtime.stop()

        await #expect(throws: CancellationError.self) { try await exporting.value }
        #expect(!(await archiver.isActive))
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".ClaudeRadarExport-") })
        let repository = RadarRepository(container: try environment.makeModelContainer(), metadataStore: SyncMetadataStore(root: root))
        let subsequent = try await repository.beginExportSnapshot()
        await repository.endExportSnapshot(subsequent)
    }

    @MainActor
    @Test("stop dominates an in-flight runtime start in twenty exact interleavings")
    func runtimeStopDominatesStart() async throws {
        for _ in 0..<20 {
            // Given
            let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let gate = LifecycleGate()
            let runtime = RadarAppRuntime(
                environment: AppEnvironment(dataRoot: root, fixtureMode: .sequence, onlineSourceEnabled: true),
                startCheckpoint: { await gate.pause() }
            )

            // When
            let starting = Task { await runtime.start() }
            await gate.waitUntilPaused()
            let stopping = Task { await runtime.stop() }
            while runtime.lifecycleState == .starting { await Task.yield() }
            await gate.release()
            await stopping.value
            await starting.value
            await runtime.start()
            await runtime.stop()

            // Then
            #expect(runtime.lifecycleState == .stopped)
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: "sync-segments.json").path))
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: "request-counts.json").path))
        }
    }

    @Test("stop drains and fences registered persistence and freezes all observable counts")
    func coordinatorStopDrainsPersistence() async throws {
        // Given
        let fixture = try repositoryFixture()
        let gate = LifecycleGate()
        let completion = LifecycleCompletion()
        let projections = LifecycleProjectionRecorder()
        let network = LifecycleNetworkMonitor()
        let wake = LifecycleSleepNotifier()
        let transport = LifecycleTransport(routes: [
            benchmarkURL: .json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"), headers: ["ETag": "\"v1\""]),
            communityURL: .json(url: communityURL, body: try fixtureData("claude-radar-community-valid"), headers: ["ETag": "\"c1\""]),
        ])
        let source = ClaudeCodeRadarSource(configuration: configuration, transport: transport)
        let coordinator = RadarSyncCoordinator(
            source: source,
            repository: fixture.repository,
            networkMonitor: network,
            sleepNotifier: wake,
            projectionDidChange: { projection in await projections.append(projection) },
            persistenceCheckpoint: { await gate.pause() }
        )
        await coordinator.startLifecycleTriggers()
        let refresh = Task { await coordinator.refresh(trigger: .manual) }
        await gate.waitUntilPaused()

        // When
        let stopping = Task {
            await coordinator.stop()
            await completion.finish()
        }
        while !(await coordinator.lifecycleState()).isStopped { await Task.yield() }

        // Then
        #expect(!(await completion.isFinished))
        await gate.release()
        await stopping.value
        await refresh.value
        await coordinator.stop()
        let frozen = try await counts(fixture.repository, projections: projections)
        network.fire()
        wake.fire()
        await coordinator.refresh(trigger: .manual)
        let afterCallbacks = try await counts(fixture.repository, projections: projections)
        #expect(frozen == afterCallbacks)
        #expect(frozen == LifecycleCounts(benchmark: 0, community: 0, status: 0, projections: 0))
        #expect(network.startCount == 1)
        #expect(network.stopCount == 1)
        #expect(wake.startCount == 1)
        #expect(wake.stopCount == 1)
        #expect(await transport.cancelCount == 1)
    }

    @Test("concurrent pauses join acquisition and registered persistence without late mutation or publication")
    func concurrentPauseDrainsPersistence() async throws {
        // Given
        let fixture = try repositoryFixture()
        let gate = LifecycleGate()
        let firstCompletion = LifecycleCompletion()
        let secondCompletion = LifecycleCompletion()
        let projections = LifecycleProjectionRecorder()
        let transport = LifecycleTransport(routes: [
            benchmarkURL: .json(url: benchmarkURL, body: try fixtureData("claude-radar-valid")),
            communityURL: .json(url: communityURL, body: try fixtureData("claude-radar-community-valid")),
        ])
        let coordinator = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: transport),
            repository: fixture.repository,
            projectionDidChange: { projection in await projections.append(projection) },
            persistenceCheckpoint: { await gate.pause() }
        )
        let refresh = Task { await coordinator.refresh(trigger: .manual) }
        await gate.waitUntilPaused()

        // When
        let firstPause = Task {
            await coordinator.pauseAndDrain()
            await firstCompletion.finish()
        }
        while !(await coordinator.lifecycleState()).isPaused { await Task.yield() }
        let secondPause = Task {
            await coordinator.pauseAndDrain()
            await secondCompletion.finish()
        }
        await Task.yield()

        // Then
        #expect(!(await firstCompletion.isFinished))
        #expect(!(await secondCompletion.isFinished))
        await gate.release()
        await firstPause.value
        await secondPause.value
        await refresh.value
        #expect(try await counts(fixture.repository, projections: projections) == LifecycleCounts(
            benchmark: 0,
            community: 0,
            status: 0,
            projections: 0
        ))
        #expect(await transport.cancelCount == 1)
        let lifecycle = await coordinator.lifecycleState()
        #expect(lifecycle.isPaused)
        #expect(!lifecycle.hasActiveTask)
        print("G028_MANUAL_QA persistence_benchmark=0 persistence_community=0 persistence_status=0 publication=0 cancel=1 paused=\(lifecycle.isPaused) stopped=\(lifecycle.isStopped) active=\(lifecycle.hasActiveTask)")
    }

    private var benchmarkURL: URL { URL(string: "https://lifecycle.invalid/benchmark")! }
    private var communityURL: URL { URL(string: "https://lifecycle.invalid/community")! }
    private var configuration: ClaudeRadarConfiguration {
        ClaudeRadarConfiguration(benchmarkURL: benchmarkURL, communityURL: communityURL, sourceStatusURL: nil)
    }

    private func fixtureData(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appending(path: "Sources/ClaudeRadar/Resources/Fixtures/\(name).json"))
    }

    private func repositoryFixture() throws -> LifecycleRepositoryFixture {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let container = try RadarModelSchema.makeContainer(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return LifecycleRepositoryFixture(repository: RadarRepository(container: container, metadataStore: SyncMetadataStore(root: root)))
    }

    private func counts(
        _ repository: RadarRepository,
        projections: LifecycleProjectionRecorder
    ) async throws -> LifecycleCounts {
        LifecycleCounts(
            benchmark: try await repository.snapshotCount(datasetType: .benchmark, sourceID: .claudeCodeRadar),
            community: try await repository.snapshotCount(datasetType: .community, sourceID: .claudeCodeRadar),
            status: try await repository.snapshotCount(datasetType: .sourceStatus, sourceID: .claudeCodeRadar),
            projections: await projections.count
        )
    }
}

private enum StartupLoadFailure: Error { case injected }

private actor LifecycleWarningGate {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<CodexRenderedWarningSnapshot, Error>?

    func read() async throws -> CodexRenderedWarningSnapshot {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func succeed(_ snapshot: CodexRenderedWarningSnapshot) {
        continuation?.resume(returning: snapshot)
        continuation = nil
    }
}

@MainActor
private final class LifecycleWarningReader: CodexRenderedWarningReading {
    private let gate: LifecycleWarningGate
    private(set) var cancelCount = 0

    init(gate: LifecycleWarningGate) {
        self.gate = gate
    }

    func read() async throws -> CodexRenderedWarningSnapshot {
        try await gate.read()
    }

    func cancel() {
        cancelCount += 1
    }
}

@MainActor
private final class LifecycleImmediateWarningReader: CodexRenderedWarningReading {
    private(set) var readCount = 0
    private(set) var cancelCount = 0

    func read() async throws -> CodexRenderedWarningSnapshot {
        readCount += 1
        throw CodexRenderedWarningPageReaderError.navigationFailed
    }

    func cancel() {
        cancelCount += 1
    }
}

private func lifecycleWarning(capturedAt: Date) throws -> CodexRenderedWarningSnapshot {
    let cards = [
        CodexRenderedWarningCard(
            displayName: "GPT-5 High",
            family: "gpt-5",
            effort: "high",
            sourceOrder: 0,
            iq: 80,
            drop24h: 3,
            drop48h: 5
        ),
    ]
    let fingerprint = try CodexRenderedWarningSemanticFingerprint.make(
        sourceTimeLabel: "刚刚",
        cards: cards,
        finalOrigin: "https://codexradar.com",
        parserRevision: CodexRenderedWarningDOMParser.parserRevision
    )
    return CodexRenderedWarningSnapshot(
        sourceID: .codexRadar,
        parserRevision: CodexRenderedWarningDOMParser.parserRevision,
        finalOrigin: "https://codexradar.com",
        sourceTimeLabel: "刚刚",
        capturedAt: capturedAt,
        cards: cards,
        semanticFingerprint: fingerprint
    )
}

private actor LifecycleIQHistoryGate {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<CodexRenderedIQHistorySnapshot, Error>?

    func read() async throws -> CodexRenderedIQHistorySnapshot {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func succeed(_ snapshot: CodexRenderedIQHistorySnapshot) {
        continuation?.resume(returning: snapshot)
        continuation = nil
    }
}

@MainActor
private final class LifecycleIQHistoryReader: CodexRenderedIQHistoryReading {
    private let gate: LifecycleIQHistoryGate
    private(set) var cancelCount = 0

    init(gate: LifecycleIQHistoryGate) {
        self.gate = gate
    }

    func read() async throws -> CodexRenderedIQHistorySnapshot {
        try await gate.read()
    }

    func cancel() {
        cancelCount += 1
    }
}

private func lifecycleIQHistory(capturedAt: Date) throws -> CodexRenderedIQHistorySnapshot {
    let series = [
        CodexRenderedIQHistorySeries(
            sourceOrder: 0,
            seriesKey: "aggregate",
            displayName: "官网综合",
            points: (0..<24).map {
                CodexRenderedIQHistoryPoint(
                    sourceOrder: $0,
                    sourceTimeLabel: "\($0)h",
                    iq: 80
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

private actor CoordinatorProbe {
    private(set) var coordinator: RadarSyncCoordinator?
    func capture(_ coordinator: RadarSyncCoordinator) { self.coordinator = coordinator }
}

private actor LifecycleExportArchiver: RadarExportArchiver {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var isActive = false

    func archive(contentsOf directory: URL, to destination: URL) async throws {
        try Data("partial".utf8).write(to: destination)
        isActive = true
        started = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        while !Task.isCancelled { await Task.yield() }
        isActive = false
        throw CancellationError()
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private struct LifecycleRepositoryFixture {
    let repository: RadarRepository
}

private struct LifecycleCounts: Equatable {
    let benchmark: Int
    let community: Int
    let status: Int
    let projections: Int
}

private actor LifecycleGate {
    private var paused = false
    private var released = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        paused = true
        for waiter in pauseWaiters { waiter.resume() }
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
        for waiter in releaseWaiters { waiter.resume() }
        releaseWaiters.removeAll()
    }
}

private actor LifecycleCompletion {
    private(set) var isFinished = false
    func finish() { isFinished = true }

    func waitUntilFinished(for timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !isFinished, clock.now < deadline {
            try? await clock.sleep(for: .milliseconds(2))
        }
        return isFinished
    }
}

private actor LifecycleProjectionRecorder {
    private var values: [RadarSyncProjection] = []
    var count: Int { values.count }
    func append(_ projection: RadarSyncProjection) { values.append(projection) }
}

private actor LifecycleTransport: HTTPTransport {
    private let routes: [URL: HTTPTransportResponse]
    private(set) var cancelCount = 0

    init(routes: [URL: HTTPTransportResponse]) { self.routes = routes }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        guard let url = request.url, let response = routes[url] else { throw URLError(.badURL) }
        return response
    }

    func cancelAll() async { cancelCount += 1 }
}

private final class LifecycleNetworkMonitor: NetworkMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0
    private var callback: (@Sendable () -> Void)?
    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
    func start(_ recovered: @escaping @Sendable () -> Void) { lock.withLock { starts += 1; callback = recovered } }
    func stop() { lock.withLock { stops += 1; callback = nil } }
    func fire() { lock.withLock { callback }?() }
}

private final class LifecycleSleepNotifier: SleepRecoveryNotifying, @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0
    private var callback: (@Sendable () -> Void)?
    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
    func start(_ recovered: @escaping @Sendable () -> Void) { lock.withLock { starts += 1; callback = recovered } }
    func stop() { lock.withLock { stops += 1; callback = nil } }
    func fire() { lock.withLock { callback }?() }
}
