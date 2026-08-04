import Foundation
import Testing
@testable import ClaudeRadar

@Suite("RadarAppRuntimeTests", .serialized)
struct RadarAppRuntimeTests {
    @MainActor
    @Test("debug sequence runs through the production coordinator and publishes segmented LKG")
    func sequenceRuntime() async throws {
        // Given
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .sequence, onlineSourceEnabled: true)
        let runtime = RadarAppRuntime(environment: environment)

        // When
        await runtime.start()
        await runtime.start()
        let projection = try #require(runtime.projection)
        await runtime.stop()

        // Then
        #expect(projection.supportLevel == .authorized)
        #expect(projection.benchmark.value != nil)
        #expect(projection.community.value != nil)
        #expect(projection.sourceStatus.value != nil)
        #expect(projection.benchmark.error != nil)
        #expect(projection.community.error != nil)
        #expect(projection.sourceStatus.error != nil)
        #expect(runtime.lifecycleState == .stopped)
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "sync-segments.json").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "request-counts.json").path))
        let segmentsData = try Data(contentsOf: root.appending(path: "sync-segments.json"))
        let segments = try #require(JSONSerialization.jsonObject(with: segmentsData) as? [String: Any])
        let stages = try #require(segments["stages"] as? [[String: Any]])
        #expect(stages.map { $0["stage"] as? String } == ["valid", "invalid-benchmark", "offline"])
        #expect(stages[0]["benchmarkError"] is NSNull)
        #expect(stages[1]["benchmarkError"] as? String == SegmentError.Kind.validation.rawValue)
        #expect(stages[1]["communityError"] is NSNull)
        #expect(stages[2]["benchmarkError"] as? String == SegmentError.Kind.network.rawValue)
        #expect(stages.allSatisfy { $0["benchmarkLKG"] as? Bool == true })
        let countsData = try Data(contentsOf: root.appending(path: "request-counts.json"))
        let counts = try #require(JSONSerialization.jsonObject(with: countsData) as? [String: Int])
        #expect(counts == ["benchmark": 3, "community": 3])
    }

    @MainActor
    @Test("manual refresh cannot acquire or persist when online support is disabled")
    func disabledManualRefresh() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ClaudeRadar-DisabledRefresh-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .sequence, onlineSourceEnabled: false)
        let runtime = RadarAppRuntime(environment: environment)

        await runtime.start()
        await runtime.refresh()
        await runtime.stop()

        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "request-counts.json").path))
        let repository = RadarRepository(container: try environment.makeModelContainer(), metadataStore: SyncMetadataStore(root: root))
        #expect(try await repository.snapshotCount(datasetType: .benchmark, sourceID: .claudeCodeRadar) == 0)
        #expect(try await repository.snapshotCount(datasetType: .community, sourceID: .claudeCodeRadar) == 0)
        #expect(try await repository.snapshotCount(datasetType: .sourceStatus, sourceID: .claudeCodeRadar) == 0)
    }

    @MainActor
    @Test("warning reader is Codex-only and disabled Codex loads persisted LKG without reading")
    func codexOnlyReaderAndOfflineLKG() async throws {
        let codexRoot = FileManager.default.temporaryDirectory
            .appending(path: "RadarAppRuntimeTests-CodexLKG-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: codexRoot) }
        let codexEnvironment = AppEnvironment(
            dataRoot: codexRoot,
            fixtureMode: .disabled,
            onlineSourceEnabled: false
        )
        let repository = RadarRepository(
            container: try codexEnvironment.makeModelContainer(),
            metadataStore: SyncMetadataStore(root: codexRoot)
        )
        let cached = try runtimeWarning(capturedAt: Date(timeIntervalSince1970: 100))
        _ = try await repository.insertRenderedWarning(cached)
        let codexReader = RuntimeWarningReader(result: .failure(RuntimeWarningError.unavailable))
        let codexFactory = RuntimeWarningFactoryProbe(reader: codexReader)
        let codexRuntime = RadarAppRuntime(
            environment: codexEnvironment,
            sourceID: .codexRadar,
            renderedWarningReaderFactory: { codexFactory.makeReader() }
        )

        await codexRuntime.start()

        #expect(codexFactory.creationCount == 1)
        #expect(codexReader.readCount == 0)
        #expect(codexRuntime.renderedWarningProjection?.value == cached)
        #expect(codexRuntime.renderedWarningHistory == [cached])
        await codexRuntime.stop()

        for sourceID in [RadarSourceID.claudeCodeRadar, .sweBenchVerified] {
            let root = FileManager.default.temporaryDirectory
                .appending(path: "RadarAppRuntimeTests-\(sourceID.rawValue)-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: root) }
            let reader = RuntimeWarningReader(result: .failure(RuntimeWarningError.unavailable))
            let factory = RuntimeWarningFactoryProbe(reader: reader)
            let runtime = RadarAppRuntime(
                environment: AppEnvironment(
                    dataRoot: root,
                    fixtureMode: .disabled,
                    onlineSourceEnabled: false
                ),
                sourceID: sourceID,
                renderedWarningReaderFactory: { factory.makeReader() }
            )

            await runtime.start()

            #expect(factory.creationCount == 0)
            #expect(reader.readCount == 0)
            #expect(runtime.renderedWarningProjection == nil)
            #expect(runtime.renderedWarningHistory.isEmpty)
            await runtime.stop()
        }
    }

    @MainActor
    @Test("Codex startup reads warnings while warning failure leaves primary sync green")
    func codexWarningFailureDoesNotCorruptPrimaryProjection() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "RadarAppRuntimeTests-CodexFailure-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = RuntimeWarningReader(result: .failure(
            CodexRenderedWarningPageReaderError.validation(.revisionMismatch)
        ))
        let runtime = RadarAppRuntime(
            environment: AppEnvironment(dataRoot: root, fixtureMode: .codex, onlineSourceEnabled: true),
            sourceID: .codexRadar,
            renderedWarningReaderFactory: { reader }
        )

        await runtime.start()
        for _ in 0..<200 where runtime.renderedWarningProjection?.error == nil {
            await Task.yield()
        }

        #expect(reader.readCount == 1)
        #expect(runtime.projection?.benchmark.value != nil)
        #expect(runtime.projection?.community.value != nil)
        #expect(runtime.renderedWarningProjection?.value == nil)
        #expect(runtime.renderedWarningProjection?.error?.kind == .validation)
        #expect(runtime.lifecycleState == .running)
        await runtime.stop()
    }

    @MainActor
    @Test("clear history clears the in-memory warning projection")
    func clearHistoryClearsWarningProjection() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "RadarAppRuntimeTests-ClearWarning-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .disabled, onlineSourceEnabled: false)
        let repository = RadarRepository(
            container: try environment.makeModelContainer(),
            metadataStore: SyncMetadataStore(root: root)
        )
        _ = try await repository.insertRenderedWarning(
            try runtimeWarning(capturedAt: Date(timeIntervalSince1970: 100))
        )
        let reader = RuntimeWarningReader(result: .failure(RuntimeWarningError.unavailable))
        let runtime = RadarAppRuntime(
            environment: environment,
            sourceID: .codexRadar,
            renderedWarningReaderFactory: { reader }
        )
        await runtime.start()
        #expect(runtime.renderedWarningProjection?.value != nil)

        #expect(await runtime.clearHistory())

        #expect(runtime.renderedWarningProjection == nil)
        #expect(runtime.renderedWarningHistory.isEmpty)
        await runtime.stop()
    }

    @MainActor
    @Test("Codex IQ failure leaves primary sync and warning publication green")
    func codexIQFailureIsIndependent() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "RadarAppRuntimeTests-CodexIQFailure-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let warning = try runtimeWarning(capturedAt: Date(timeIntervalSince1970: 100))
        let warningReader = RuntimeWarningReader(result: .success(warning))
        let iqReader = RuntimeIQReader(results: [
            .failure(CodexRenderedIQHistoryPageReaderError.validation(.revisionMismatch)),
        ])
        let runtime = RadarAppRuntime(
            environment: AppEnvironment(dataRoot: root, fixtureMode: .codex, onlineSourceEnabled: true),
            sourceID: .codexRadar,
            renderedWarningReaderFactory: { warningReader },
            renderedIQHistoryReaderFactory: { iqReader }
        )

        await runtime.start()
        for _ in 0..<200 where runtime.renderedIQHistoryProjection?.error == nil {
            await Task.yield()
        }

        #expect(runtime.lifecycleState == .running)
        #expect(runtime.projection?.benchmark.value != nil)
        #expect(runtime.projection?.community.value != nil)
        #expect(runtime.renderedWarningProjection?.value == warning)
        #expect(runtime.renderedIQHistoryProjection?.value == nil)
        #expect(runtime.renderedIQHistoryProjection?.error?.kind == .validation)
        await runtime.stop()
    }

    @MainActor
    @Test("disabled Codex loads persisted IQ history without reading")
    func persistedIQHistoryLoadsIndependently() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "RadarAppRuntimeTests-CodexIQLKG-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .disabled, onlineSourceEnabled: false)
        let repository = RadarRepository(
            container: try environment.makeModelContainer(),
            metadataStore: SyncMetadataStore(root: root)
        )
        let cached = try runtimeIQHistory(capturedAt: Date(timeIntervalSince1970: 100))
        _ = try await repository.insertRenderedIQHistory(cached)
        let reader = RuntimeIQReader(results: [.failure(RuntimeWarningError.unavailable)])
        let runtime = RadarAppRuntime(
            environment: environment,
            sourceID: .codexRadar,
            renderedIQHistoryReaderFactory: { reader }
        )

        await runtime.start()

        #expect(reader.readCount == 0)
        #expect(runtime.renderedIQHistoryProjection?.value == cached)
        #expect(runtime.renderedIQHistoryHistory == [cached])
        await runtime.stop()
    }

    @MainActor
    @Test("manual refresh publishes IQ history and clear removes it")
    func manualRefreshAndClearIQHistory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "RadarAppRuntimeTests-CodexIQManual-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let initial = try runtimeIQHistory(capturedAt: Date(timeIntervalSince1970: 100), iq: 80)
        let snapshot = try runtimeIQHistory(capturedAt: Date(timeIntervalSince1970: 200), iq: 81)
        let reader = RuntimeIQReader(results: [.success(initial), .success(snapshot)])
        let runtime = RadarAppRuntime(
            environment: AppEnvironment(dataRoot: root, fixtureMode: .codex, onlineSourceEnabled: true),
            sourceID: .codexRadar,
            renderedIQHistoryReaderFactory: { reader }
        )

        await runtime.start()
        for _ in 0..<200 where runtime.renderedIQHistoryProjection?.value == nil {
            await Task.yield()
        }
        await runtime.refresh()
        for _ in 0..<200 where reader.readCount < 2 {
            await Task.yield()
        }
        await runtime.updateRefreshInterval(minutes: 60)

        #expect(reader.readCount == 2)
        #expect(runtime.refreshIntervalMinutes == 60)
        #expect(runtime.renderedIQHistoryProjection?.value == snapshot)
        #expect(await runtime.clearHistory())
        #expect(runtime.renderedIQHistoryProjection == nil)
        #expect(runtime.renderedIQHistoryHistory.isEmpty)
        await runtime.stop()
    }

    @MainActor
    @Test("concurrent history clears coalesce into one source deletion")
    func concurrentHistoryClearsCoalesce() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "RadarAppRuntimeTests-CoalescedClear-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .disabled, onlineSourceEnabled: false)
        let repository = RadarRepository(container: try environment.makeModelContainer(), metadataStore: SyncMetadataStore(root: root))
        _ = try await repository.insertRenderedWarning(try runtimeWarning(capturedAt: Date(timeIntervalSince1970: 100)))
        _ = try await repository.insertRenderedIQHistory(try runtimeIQHistory(capturedAt: Date(timeIntervalSince1970: 100)))
        let deletion = RuntimeDeletionProbe()
        let runtime = RadarAppRuntime(
            environment: environment,
            sourceID: .codexRadar,
            renderedWarningReaderFactory: { RuntimeWarningReader(result: .failure(RuntimeWarningError.unavailable)) },
            renderedIQHistoryReaderFactory: { RuntimeIQReader(results: [.failure(RuntimeWarningError.unavailable)]) },
            deleteNormalizedHistory: { repository, sourceID in
                try await deletion.delete(repository: repository, sourceID: sourceID)
            }
        )
        await runtime.start()

        let first = Task { await runtime.clearHistory() }
        await deletion.waitUntilStarted()
        let second = Task { await runtime.clearHistory() }
        await Task.yield()
        #expect(await deletion.callCount == 1)
        await deletion.release()

        #expect(await first.value)
        #expect(await second.value)
        #expect(await deletion.callCount == 1)
        #expect(runtime.lifecycleState == .running)
        let states = await runtime.synchronizationLifecycleStates()
        #expect(states.primary?.isPaused == false)
        #expect(states.renderedWarning?.isPaused == false)
        #expect(states.renderedIQHistory?.isPaused == false)
        await runtime.stop()
        #expect(!(await runtime.clearHistory()))
    }

    @MainActor
    @Test("failed history deletion resumes every coordinator and preserves truthful memory")
    func failedHistoryDeletionResumesSynchronization() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "RadarAppRuntimeTests-FailedClear-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let warning = try runtimeWarning(capturedAt: Date(timeIntervalSince1970: 100))
        let iq = try runtimeIQHistory(capturedAt: Date(timeIntervalSince1970: 100))
        let warningReader = RuntimeWarningReader(result: .success(warning))
        let iqReader = RuntimeIQReader(results: [.success(iq), .success(iq)])
        let runtime = RadarAppRuntime(
            environment: AppEnvironment(dataRoot: root, fixtureMode: .codex, onlineSourceEnabled: true),
            sourceID: .codexRadar,
            renderedWarningReaderFactory: { warningReader },
            renderedIQHistoryReaderFactory: { iqReader },
            deleteNormalizedHistory: { _, _ in throw RuntimeDeletionError.injected }
        )
        await runtime.start()
        for _ in 0..<200 where warningReader.readCount < 1 || iqReader.readCount < 1 { await Task.yield() }
        let projectionBefore = try #require(runtime.projection)
        let benchmarkCountBefore = runtime.benchmarkHistory.count

        #expect(!(await runtime.clearHistory()))

        #expect(runtime.projection?.benchmark.value == projectionBefore.benchmark.value)
        #expect(runtime.benchmarkHistory.count == benchmarkCountBefore)
        #expect(runtime.renderedWarningProjection?.value == warning)
        #expect(runtime.renderedIQHistoryProjection?.value == iq)
        #expect(runtime.lifecycleState == .running)
        let states = await runtime.synchronizationLifecycleStates()
        #expect(states.primary?.isPaused == false)
        #expect(states.renderedWarning?.isPaused == false)
        #expect(states.renderedIQHistory?.isPaused == false)

        await runtime.refresh()
        for _ in 0..<200 where warningReader.readCount < 2 || iqReader.readCount < 2 { await Task.yield() }
        #expect(warningReader.readCount == 2)
        #expect(iqReader.readCount == 2)
        await runtime.stop()
    }
}

private enum RuntimeWarningError: Error {
    case unavailable
}

private enum RuntimeDeletionError: Error { case injected }

private actor RuntimeDeletionProbe {
    private(set) var callCount = 0
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func delete(repository: RadarRepository, sourceID: RadarSourceID) async throws {
        callCount += 1
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        if !released { await withCheckedContinuation { releaseWaiters.append($0) } }
        try await repository.deleteNormalizedHistory(sourceID: sourceID)
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

@MainActor
private final class RuntimeWarningReader: CodexRenderedWarningReading {
    private let result: Result<CodexRenderedWarningSnapshot, Error>
    private(set) var readCount = 0
    private(set) var cancelCount = 0

    init(result: Result<CodexRenderedWarningSnapshot, Error>) {
        self.result = result
    }

    func read() async throws -> CodexRenderedWarningSnapshot {
        readCount += 1
        return try result.get()
    }

    func cancel() {
        cancelCount += 1
    }
}

@MainActor
private final class RuntimeWarningFactoryProbe {
    let reader: RuntimeWarningReader
    private(set) var creationCount = 0

    init(reader: RuntimeWarningReader) {
        self.reader = reader
    }

    func makeReader() -> any CodexRenderedWarningReading {
        creationCount += 1
        return reader
    }
}

@MainActor
private final class RuntimeIQReader: CodexRenderedIQHistoryReading {
    private var results: [Result<CodexRenderedIQHistorySnapshot, Error>]
    private(set) var readCount = 0
    private(set) var cancelCount = 0

    init(results: [Result<CodexRenderedIQHistorySnapshot, Error>]) {
        self.results = results
    }

    func read() async throws -> CodexRenderedIQHistorySnapshot {
        readCount += 1
        return try results.removeFirst().get()
    }

    func cancel() {
        cancelCount += 1
    }
}

private func runtimeWarning(capturedAt: Date) throws -> CodexRenderedWarningSnapshot {
    let cards = [
        CodexRenderedWarningCard(
            displayName: "GPT-5 High",
            family: "gpt-5",
            effort: "high",
            sourceOrder: 0,
            iq: 80,
            drop24h: 3,
            drop48h: nil
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

private func runtimeIQHistory(
    capturedAt: Date,
    iq: Double = 80
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
