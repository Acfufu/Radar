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
}
