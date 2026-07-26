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
}

private enum RuntimeWarningError: Error {
    case unavailable
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
