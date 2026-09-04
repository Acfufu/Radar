import Foundation
import Testing
@testable import AIRadar

@Suite("WorkspaceSupportSurfaceTests", .serialized)
struct WorkspaceSupportSurfaceTests {
    @MainActor
    @Test("workspace refresh interval broadcasts to every source runtime")
    func refreshIntervalBroadcast() async {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .disabled, onlineSourceEnabled: false)
        let runtimes = Dictionary(uniqueKeysWithValues: [
            RadarSourceID.claudeCodeRadar,
            .codexRadar,
            .sweBenchVerified,
        ].map { ($0, RadarAppRuntime(environment: environment, sourceID: $0)) })
        let model = RadarWorkspaceModel(runtimes: runtimes, selectedSourceID: .codexRadar)

        await model.updateRefreshInterval(minutes: 60)

        #expect(runtimes.values.allSatisfy { $0.refreshIntervalMinutes == 60 })
        #expect(model.refreshIntervalMinutes == 60)
    }

    @MainActor
    @Test("export dataset choices remain source-local")
    func sourceLocalExportDatasets() {
        #expect(ExportView.availableDatasets(for: .claudeCodeRadar) == [.models, .benchmarkRuns, .communityRatings, .sourceStatus])
        #expect(ExportView.availableDatasets(for: .codexRadar) == ExportDataset.normalized)
        #expect(ExportView.availableDatasets(for: .sweBenchVerified) == [.models, .benchmarkRuns])
    }
}
