import Foundation
import SwiftData
import Testing
@testable import ClaudeRadar

@Suite("RadarLifecycleRaceTests", .serialized)
struct RadarLifecycleRaceTests {
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

    @Test("stop drains registered persistence and freezes all observable counts")
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
        #expect(frozen == LifecycleCounts(benchmark: 1, community: 1, status: 1, projections: 0))
        #expect(network.startCount == 1)
        #expect(network.stopCount == 1)
        #expect(wake.startCount == 1)
        #expect(wake.stopCount == 1)
        #expect(await transport.cancelCount == 1)
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
