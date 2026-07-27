import Foundation
import Observation

enum RadarAppLifecycleState: Sendable, Equatable {
    case idle
    case starting
    case running
    case stopping
    case stopped
    case failed
}

@MainActor
@Observable
final class RadarAppRuntime {
    let environment: AppEnvironment
    let sourceID: RadarSourceID
    private(set) var projection: RadarSyncProjection?
    private(set) var lifecycleState: RadarAppLifecycleState = .idle
    private(set) var failureMessage: String?
    private(set) var benchmarkHistory: [BenchmarkDataset] = []
    private(set) var renderedWarningProjection: SegmentState<CodexRenderedWarningSnapshot>?
    private(set) var renderedWarningHistory: [CodexRenderedWarningSnapshot] = []
    private(set) var renderedIQHistoryProjection: SegmentState<CodexRenderedIQHistorySnapshot>?
    private(set) var renderedIQHistoryHistory: [CodexRenderedIQHistorySnapshot] = []
    private(set) var refreshIntervalMinutes: Int

    private var coordinator: RadarSyncCoordinator?
    private var renderedWarningCoordinator: CodexRenderedWarningCoordinator?
    private var renderedIQHistoryCoordinator: CodexRenderedIQHistoryCoordinator?
    private var repository: RadarRepository?
    #if DEBUG
    private var evidenceStages: [[String: Any]] = []
    #endif
    private let startCheckpoint: (@Sendable () async -> Void)?
    private let startupLoadCheckpoint: (@Sendable (RadarSyncCoordinator) async throws -> Void)?
    private let exportArchiver: any RadarExportArchiver
    private let metadataStore: SyncMetadataStore
    private let renderedWarningReaderFactory: (@MainActor @Sendable () -> any CodexRenderedWarningReading)?
    private let renderedIQHistoryReaderFactory: (@MainActor @Sendable () -> any CodexRenderedIQHistoryReading)?
    private var lifecycleGeneration = 0
    private var startOperation: Task<Void, Never>?
    private var stopOperation: Task<Void, Never>?
    private var exportOperations: [UUID: Task<ExportResult, Error>] = [:]

    init(
        environment: AppEnvironment,
        sourceID: RadarSourceID = .claudeCodeRadar,
        metadataStore: SyncMetadataStore? = nil,
        startCheckpoint: (@Sendable () async -> Void)? = nil,
        startupLoadCheckpoint: (@Sendable (RadarSyncCoordinator) async throws -> Void)? = nil,
        exportArchiver: any RadarExportArchiver = SystemZipArchiver(),
        refreshIntervalMinutes: Int = 30,
        renderedWarningReaderFactory: (@MainActor @Sendable () -> any CodexRenderedWarningReading)? = nil,
        renderedIQHistoryReaderFactory: (@MainActor @Sendable () -> any CodexRenderedIQHistoryReading)? = nil
    ) {
        self.environment = environment
        self.sourceID = sourceID
        self.metadataStore = metadataStore ?? SyncMetadataStore(root: environment.dataRoot)
        self.startCheckpoint = startCheckpoint
        self.startupLoadCheckpoint = startupLoadCheckpoint
        self.exportArchiver = exportArchiver
        self.renderedWarningReaderFactory = renderedWarningReaderFactory
        self.renderedIQHistoryReaderFactory = renderedIQHistoryReaderFactory
        self.refreshIntervalMinutes = AppSettings.allowedIntervals.contains(refreshIntervalMinutes) ? refreshIntervalMinutes : 30
    }

    func start() async {
        if lifecycleState == .starting {
            await startOperation?.value
            return
        }
        guard lifecycleState == .idle else { return }
        lifecycleState = .starting
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performStart(generation: generation)
        }
        startOperation = task
        await task.value
    }

    func stop() async {
        if lifecycleState == .stopping {
            await stopOperation?.value
            return
        }
        guard lifecycleState != .stopped else { return }
        lifecycleState = .stopping
        lifecycleGeneration += 1
        let generation = lifecycleGeneration
        let starting = startOperation
        let activeCoordinator = coordinator
        let activeRenderedWarningCoordinator = renderedWarningCoordinator
        let activeRenderedIQHistoryCoordinator = renderedIQHistoryCoordinator
        let activeExports = Array(exportOperations.values)
        starting?.cancel()
        activeExports.forEach { $0.cancel() }
        startOperation = nil
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            for export in activeExports { _ = try? await export.value }
            if let activeRenderedIQHistoryCoordinator { await activeRenderedIQHistoryCoordinator.stop() }
            if let activeRenderedWarningCoordinator { await activeRenderedWarningCoordinator.stop() }
            if let activeCoordinator { await activeCoordinator.stop() }
            guard generation == self.lifecycleGeneration else { return }
            self.coordinator = nil
            self.renderedWarningCoordinator = nil
            self.renderedIQHistoryCoordinator = nil
            self.repository = nil
            self.lifecycleState = .stopped
        }
        stopOperation = task
        await task.value
    }

    private func performStart(generation: Int) async {
        do {
            let container = try environment.makeModelContainer()
            let repository = RadarRepository(
                container: container,
                metadataStore: metadataStore
            )
            self.repository = repository
            #if DEBUG
            if environment.fixtureMode == .ui {
                try await DebugUISeed.populate(repository: repository, sourceID: sourceID, state: ProcessInfo.processInfo.environment["RADAR_UI_STATE"] ?? "fresh")
            }
            #endif
            #if DEBUG
            let source: RadarHTTPSource
            if sourceID == .codexRadar, environment.fixtureMode == .codex {
                source = RadarHTTPSource(
                    configuration: CodexRadarConfiguration(
                        summaryURL: CodexFixtureTransport.summaryURL,
                        communityURL: CodexFixtureTransport.communityURL
                    ),
                    transport: try CodexFixtureTransport(),
                    rawSampleStore: RawSampleStore(dataRoot: environment.dataRoot)
                )
            } else if sourceID == .claudeCodeRadar, environment.fixtureMode == .sequence {
                let configuration = ClaudeRadarConfiguration(
                    benchmarkURL: FixtureSequenceTransport.benchmarkURL,
                    communityURL: FixtureSequenceTransport.communityURL,
                    sourceStatusURL: nil
                )
                source = RadarHTTPSource(
                    configuration: configuration,
                    transport: try FixtureSequenceTransport(dataRoot: environment.dataRoot),
                    rawSampleStore: RawSampleStore(dataRoot: environment.dataRoot)
                )
            } else {
                source = productionSource()
            }
            #else
            let source = productionSource()
            #endif
            let renderedWarningCoordinator: CodexRenderedWarningCoordinator?
            if sourceID == .codexRadar, let renderedWarningReaderFactory {
                let warningCoordinator = CodexRenderedWarningCoordinator(
                    reader: renderedWarningReaderFactory(),
                    repository: repository,
                    policy: SyncPolicy(refreshInterval: TimeInterval(refreshIntervalMinutes * 60)),
                    projectionDidChange: { [weak self] state, history in
                        await self?.acceptRenderedWarning(
                            state,
                            history: history,
                            generation: generation
                        )
                    }
                )
                renderedWarningCoordinator = warningCoordinator
                self.renderedWarningCoordinator = warningCoordinator
                _ = try await warningCoordinator.loadPersistedProjection()
                guard isStarting(generation) else {
                    await warningCoordinator.stop()
                    return
                }
            } else {
                renderedWarningCoordinator = nil
            }
            let renderedIQHistoryCoordinator: CodexRenderedIQHistoryCoordinator?
            if sourceID == .codexRadar, let renderedIQHistoryReaderFactory {
                let iqHistoryCoordinator = CodexRenderedIQHistoryCoordinator(
                    reader: renderedIQHistoryReaderFactory(),
                    repository: repository,
                    policy: SyncPolicy(refreshInterval: TimeInterval(refreshIntervalMinutes * 60)),
                    projectionDidChange: { [weak self] state, history in
                        await self?.acceptRenderedIQHistory(
                            state,
                            history: history,
                            generation: generation
                        )
                    }
                )
                renderedIQHistoryCoordinator = iqHistoryCoordinator
                self.renderedIQHistoryCoordinator = iqHistoryCoordinator
                _ = try? await iqHistoryCoordinator.loadPersistedProjection()
                guard isStarting(generation) else {
                    await iqHistoryCoordinator.stop()
                    return
                }
            } else {
                renderedIQHistoryCoordinator = nil
            }
            let renderedTriggerObserver: (@Sendable (SyncTrigger) -> Void)?
            if renderedWarningCoordinator != nil || renderedIQHistoryCoordinator != nil {
                renderedTriggerObserver = { trigger in
                    if let renderedWarningCoordinator {
                        Task { await renderedWarningCoordinator.refresh(trigger: trigger) }
                    }
                    if let renderedIQHistoryCoordinator {
                        Task { await renderedIQHistoryCoordinator.refresh(trigger: trigger) }
                    }
                }
            } else {
                renderedTriggerObserver = nil
            }
            let coordinator = RadarSyncCoordinator(
                source: source,
                repository: repository,
                policy: SyncPolicy(refreshInterval: TimeInterval(refreshIntervalMinutes * 60)),
                networkMonitor: NetworkMonitor(),
                sleepNotifier: SleepRecoveryNotifier(),
                projectionDidChange: { [weak self] projection in
                    await self?.accept(projection, repository: repository, generation: generation)
                },
                triggerObserver: renderedTriggerObserver
            )
            self.coordinator = coordinator
            await startCheckpoint?()
            guard isStarting(generation) else {
                await coordinator.stop()
                return
            }
            if environment.synchronizationEnabled(for: sourceID) {
                await coordinator.startLifecycleTriggers()
                guard isStarting(generation) else { await coordinator.stop(); return }
                await coordinator.startPeriodicRefresh()
                guard isStarting(generation) else { await coordinator.stop(); return }
                await coordinator.refresh(trigger: .startup)
                guard isStarting(generation) else { await coordinator.stop(); return }
                #if DEBUG
                try await recordEvidenceStage("valid", coordinator: coordinator)
                guard isStarting(generation) else { await coordinator.stop(); return }
                if environment.fixtureMode == .sequence {
                    await coordinator.refresh(trigger: .manual)
                    guard isStarting(generation) else { await coordinator.stop(); return }
                    try await recordEvidenceStage("invalid-benchmark", coordinator: coordinator)
                    guard isStarting(generation) else { await coordinator.stop(); return }
                    await coordinator.refresh(trigger: .manual)
                    guard isStarting(generation) else { await coordinator.stop(); return }
                    try await recordEvidenceStage("offline", coordinator: coordinator)
                    guard isStarting(generation) else { await coordinator.stop(); return }
                }
                #endif
            }
            try await startupLoadCheckpoint?(coordinator)
            let initialProjection = try await coordinator.projection()
            let initialHistory = try await repository.benchmarkHistory(sourceID: sourceID)
            projection = initialProjection
            benchmarkHistory = initialHistory
            guard isStarting(generation) else { await coordinator.stop(); return }
            #if DEBUG
            try writeProjectionEvidence()
            #endif
            guard isStarting(generation) else { await coordinator.stop(); return }
            lifecycleState = .running
            startOperation = nil
        } catch {
            if let coordinator { await coordinator.stop() }
            if let renderedIQHistoryCoordinator { await renderedIQHistoryCoordinator.stop() }
            if let renderedWarningCoordinator { await renderedWarningCoordinator.stop() }
            guard isStarting(generation) else { return }
            self.coordinator = nil
            self.renderedWarningCoordinator = nil
            self.renderedIQHistoryCoordinator = nil
            self.repository = nil
            lifecycleState = .failed
            failureMessage = "Synchronization runtime could not start"
            startOperation = nil
        }
    }

    func refresh() async {
        guard environment.synchronizationEnabled(for: sourceID),
              let coordinator,
              lifecycleState == .running else { return }
        await coordinator.refresh(trigger: .manual)
        let updatedProjection = try? await coordinator.projection()
        let updatedHistory = try? await coordinator.repository.benchmarkHistory(sourceID: sourceID)
        if let updatedProjection { projection = updatedProjection }
        if let updatedHistory { benchmarkHistory = updatedHistory }
    }

    func updateRefreshInterval(minutes: Int) async {
        let normalized = AppSettings.allowedIntervals.contains(minutes) ? minutes : 30
        refreshIntervalMinutes = normalized
        await coordinator?.updateRefreshInterval(TimeInterval(normalized * 60))
        await renderedWarningCoordinator?.updateRefreshInterval(TimeInterval(normalized * 60))
        await renderedIQHistoryCoordinator?.updateRefreshInterval(TimeInterval(normalized * 60))
        if let coordinator { projection = try? await coordinator.projection() }
    }

    @discardableResult
    func clearHistory() async -> Bool {
        guard let coordinator else { return false }
        do {
            try await coordinator.repository.deleteAll()
            projection = try await coordinator.projection()
            benchmarkHistory = []
            renderedWarningProjection = nil
            renderedWarningHistory = []
            renderedIQHistoryProjection = nil
            renderedIQHistoryHistory = []
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func clearRawSamples() async -> Bool {
        do {
            try await RawSampleStore(dataRoot: environment.dataRoot).deleteAll()
            return true
        } catch {
            return false
        }
    }

    func export(
        request: ExportRequest,
        progress: @escaping @Sendable (ExportProgress) async -> Void
    ) async throws -> ExportResult {
        guard lifecycleState == .running, let repository else { throw ExportError.repositoryUnavailable }
        let source = RadarExportSource(
            repository: repository,
            rawSampleStore: RawSampleStore(dataRoot: environment.dataRoot),
            sourceID: sourceID
        )
        let service = RadarExportService(source: source, archiver: exportArchiver)
        let id = UUID()
        let operation = Task { try await service.export(request: request, progress: progress) }
        exportOperations[id] = operation
        defer { exportOperations[id] = nil }
        return try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
    }

    private func isStarting(_ generation: Int) -> Bool {
        lifecycleState == .starting && lifecycleGeneration == generation && !Task.isCancelled
    }

    private func accept(_ projection: RadarSyncProjection, repository: RadarRepository, generation: Int) async {
        let history = (try? await repository.benchmarkHistory(sourceID: sourceID)) ?? benchmarkHistory
        guard lifecycleGeneration == generation,
              lifecycleState == .starting || lifecycleState == .running else { return }
        self.projection = projection
        benchmarkHistory = history
    }

    private func acceptRenderedWarning(
        _ state: SegmentState<CodexRenderedWarningSnapshot>,
        history: [CodexRenderedWarningSnapshot],
        generation: Int
    ) {
        guard lifecycleGeneration == generation,
              lifecycleState == .starting || lifecycleState == .running else { return }
        renderedWarningProjection = state
        renderedWarningHistory = history
    }

    private func acceptRenderedIQHistory(
        _ state: SegmentState<CodexRenderedIQHistorySnapshot>,
        history: [CodexRenderedIQHistorySnapshot],
        generation: Int
    ) {
        guard lifecycleGeneration == generation,
              lifecycleState == .starting || lifecycleState == .running else { return }
        renderedIQHistoryProjection = state
        renderedIQHistoryHistory = history
    }

    var statusTitle: String {
        if lifecycleState == .failed { return "Synchronization unavailable" }
        guard environment.synchronizationEnabled(for: sourceID) else { return "Online source disabled" }
        guard let projection else { return "Synchronizing \(descriptor.displayName)" }
        if projection.benchmark.error != nil
            || projection.community.error != nil
            || (sourceID != .sweBenchVerified && projection.sourceStatus.error != nil) {
            return "Last known good data retained"
        }
        return "\(descriptor.displayName) synchronized"
    }

    var supportLevel: SupportLevel { environment.supportLevel(for: sourceID) }

    var descriptor: RadarSourceDescriptor {
        let source = switch sourceID {
        case .codexRadar: CodexRadarConfiguration.descriptor
        case .sweBenchVerified: SWEBenchConfiguration.descriptor
        default: ClaudeRadarConfiguration.descriptor
        }
        return RadarSourceDescriptor(
            id: source.id,
            displayName: source.displayName,
            supportLevel: supportLevel,
            homepageURL: source.homepageURL,
            seriesRevision: source.seriesRevision
        )
    }

    var statusDetail: String {
        failureMessage ?? "Automatic synchronization keeps benchmark, community, and source-status state independent."
    }

    private func productionSource() -> RadarHTTPSource {
        let rawSamples = RawSampleStore(dataRoot: environment.dataRoot)
        return switch sourceID {
        case .codexRadar:
            RadarHTTPSource(
                configuration: CodexRadarConfiguration.production,
                transport: URLSessionHTTPTransport(),
                rawSampleStore: rawSamples
            )
        case .sweBenchVerified:
            RadarHTTPSource(
                configuration: SWEBenchConfiguration.production,
                transport: URLSessionHTTPTransport(maxBodyBytes: SWEBenchConfiguration.maximumResponseBytes),
                rawSampleStore: rawSamples
            )
        default:
            RadarHTTPSource(
                transport: URLSessionHTTPTransport(),
                rawSampleStore: rawSamples
            )
        }
    }

    #if DEBUG
    private func writeProjectionEvidence() throws {
        guard environment.fixtureMode == .sequence, let projection else { return }
        let document: [String: Any] = [
            "stages": evidenceStages,
            "final": evidenceState(projection),
        ]
        try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
            .write(to: environment.dataRoot.appending(path: "sync-segments.json"), options: .atomic)
    }

    private func recordEvidenceStage(_ name: String, coordinator: RadarSyncCoordinator) async throws {
        guard environment.fixtureMode == .sequence else { return }
        var state = evidenceState(try await coordinator.projection())
        state["stage"] = name
        evidenceStages.append(state)
    }

    private func evidenceState(_ projection: RadarSyncProjection) -> [String: Any] {
        [
            "benchmarkLKG": projection.benchmark.value != nil,
            "benchmarkError": projection.benchmark.error?.kind.rawValue ?? NSNull(),
            "communityLKG": projection.community.value != nil,
            "communityError": projection.community.error?.kind.rawValue ?? NSNull(),
            "sourceStatusLKG": projection.sourceStatus.value != nil,
            "sourceStatusError": projection.sourceStatus.error?.kind.rawValue ?? NSNull(),
        ]
    }
    #endif
}
