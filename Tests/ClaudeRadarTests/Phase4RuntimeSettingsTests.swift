import Foundation
import Testing
@testable import ClaudeRadar

@Suite("Phase4RuntimeSettingsTests", .serialized)
struct Phase4RuntimeSettingsTests {
    @MainActor
    @Test("refresh interval is constrained and live runtime policy changes")
    func refreshIntervalWiring() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.refreshIntervalMinutes == 30)
        settings.refreshIntervalMinutes = 15
        #expect(settings.refreshIntervalMinutes == 15)
        settings.refreshIntervalMinutes = 17
        #expect(settings.refreshIntervalMinutes == 30)
        #expect(settings.launchAtLogin == false)

        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let runtime = RadarAppRuntime(environment: .init(dataRoot: root, fixtureMode: .disabled, onlineSourceEnabled: false), refreshIntervalMinutes: 30)
        #expect(runtime.refreshIntervalMinutes == 30)
        await runtime.updateRefreshInterval(minutes: 60)
        #expect(runtime.refreshIntervalMinutes == 60)
    }

    @MainActor
    @Test("automatic projection publication refreshes history atomically")
    func historyPublication() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let runtime = RadarAppRuntime(environment: .init(dataRoot: root, fixtureMode: .sequence, onlineSourceEnabled: true))
        await runtime.start()
        let latest = try #require(runtime.projection?.benchmark.value)
        #expect(runtime.benchmarkHistory.last?.seriesRevision == latest.seriesRevision)
        #expect(runtime.benchmarkHistory.last?.models == latest.models)
        await runtime.stop()
    }
}
