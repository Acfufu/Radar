import Foundation
import Testing
@testable import AIRadar

#if DEBUG
@Suite("CodexRenderedWarningDebugFixtureTests", .serialized)
struct CodexRenderedWarningDebugFixtureTests {
    private let states = [
        "warning-loading",
        "warning-fresh-cards",
        "warning-empty",
        "warning-stale",
        "warning-lkg-error",
        "warning-error",
        "warning-empty-benchmark",
        "warning-schema-drift",
        "warning-timeout",
    ]

    @Test("Debug launch selectors expose only supported warning states and source IDs")
    func launchSelectors() {
        #expect(DebugUISeed.renderedWarningStates == Set(states))
        #expect(AppEnvironment.debugInitialSourceID(
            fixtureMode: .ui,
            variables: ["RADAR_UI_SOURCE": "codexRadar"]
        ) == .codexRadar)
        #expect(AppEnvironment.debugInitialSourceID(
            fixtureMode: .ui,
            variables: ["RADAR_UI_SOURCE": "claudeCodeRadar"]
        ) == .claudeCodeRadar)
        #expect(AppEnvironment.debugInitialSourceID(
            fixtureMode: .ui,
            variables: ["RADAR_UI_SOURCE": "sweBenchVerified"]
        ) == .sweBenchVerified)
        #expect(AppEnvironment.debugInitialSourceID(
            fixtureMode: .ui,
            variables: ["RADAR_UI_SOURCE": "not-a-source"]
        ) == .claudeCodeRadar)
        #expect(AppEnvironment.debugInitialSourceID(
            fixtureMode: .disabled,
            variables: ["RADAR_UI_SOURCE": "codexRadar"]
        ) == .claudeCodeRadar)
    }

    @MainActor
    @Test("all warning fixture states load through production persistence without a reader request")
    func persistedStateMatrix() async throws {
        for state in states {
            let fixture = try await load(state: state)
            defer { try? FileManager.default.removeItem(at: fixture.root) }

            #expect(fixture.reader.readCount == 0, "Unexpected warning read for \(state)")
            #expect(fixture.runtime.lifecycleState == .running)
            #expect(!fixture.runtime.environment.synchronizationEnabled(for: .codexRadar))
            #expect((try await RawSampleStore(dataRoot: fixture.root).samples(
                sourceID: .codexRadar
            )).isEmpty)
            let projection = try #require(fixture.runtime.renderedWarningProjection)

            switch state {
            case "warning-loading":
                #expect(projection.value == nil)
                #expect(projection.error == nil)
                #expect(projection.lastSuccessfulAt == nil)
                #expect(projection.lastAttemptedAt == nil)
                #expect(projection.isStale)
            case "warning-fresh-cards", "warning-empty-benchmark":
                try assertFourCards(projection, capturedAt: fixture.now)
                #expect(!projection.isStale)
                #expect(projection.error == nil)
            case "warning-empty":
                let snapshot = try #require(projection.value)
                #expect(snapshot.cards.isEmpty)
                #expect(snapshot.capturedAt == fixture.now)
                #expect(projection.error == nil)
                #expect(!projection.isStale)
            case "warning-stale":
                let snapshot = try #require(projection.value)
                try assertFourCards(
                    projection,
                    capturedAt: fixture.now.addingTimeInterval(-8 * 60 * 60)
                )
                #expect(snapshot.capturedAt == fixture.now.addingTimeInterval(-8 * 60 * 60))
                #expect(projection.lastSuccessfulAt == snapshot.capturedAt)
                #expect(projection.lastAttemptedAt == snapshot.capturedAt)
                #expect(projection.error == nil)
                #expect(projection.isStale)
            case "warning-lkg-error":
                let snapshot = try #require(projection.value)
                try assertFourCards(
                    projection,
                    capturedAt: fixture.now.addingTimeInterval(-30 * 60)
                )
                #expect(snapshot.capturedAt == fixture.now.addingTimeInterval(-30 * 60))
                #expect(projection.lastSuccessfulAt == snapshot.capturedAt)
                #expect(projection.lastAttemptedAt == fixture.now)
                #expect(projection.error?.kind == .validation)
                #expect(!projection.isStale)
            case "warning-error":
                #expect(projection.value == nil)
                #expect(projection.lastSuccessfulAt == nil)
                #expect(projection.lastAttemptedAt == fixture.now)
                #expect(projection.error?.kind == .validation)
                #expect(projection.error?.message == "Rendered warning fixture failure")
            case "warning-schema-drift":
                #expect(projection.value == nil)
                #expect(projection.lastSuccessfulAt == nil)
                #expect(projection.lastAttemptedAt == fixture.now)
                #expect(projection.error?.kind == .validation)
                #expect(projection.error?.message == "Rendered warning schema drift")
            case "warning-timeout":
                #expect(projection.value == nil)
                #expect(projection.lastSuccessfulAt == nil)
                #expect(projection.lastAttemptedAt == fixture.now)
                #expect(projection.error?.kind == .network)
                #expect(projection.error?.message == "Rendered warning fixture timed out")
            default:
                Issue.record("Unhandled fixture state \(state)")
            }

            await fixture.runtime.stop()
        }
    }

    @MainActor
    @Test("official warnings remain populated when the Codex benchmark is explicitly empty")
    func emptyBenchmarkIndependence() async throws {
        let fixture = try await load(state: "warning-empty-benchmark")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        #expect(fixture.runtime.projection?.benchmark.value == nil)
        #expect(fixture.runtime.benchmarkHistory.isEmpty)
        #expect(fixture.runtime.renderedWarningProjection?.value?.cards.count == 4)
        #expect(try await fixture.repository.snapshotCount(
            datasetType: .benchmark,
            sourceID: .codexRadar
        ) == 0)

        await fixture.runtime.stop()
    }

    @Test("Claude and SWE fixture population never writes official warning rows")
    func warningSourceIsolation() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        for sourceID in [RadarSourceID.claudeCodeRadar, .sweBenchVerified] {
            let root = temporaryRoot("SourceIsolation-\(sourceID.rawValue)")
            defer { try? FileManager.default.removeItem(at: root) }
            let environment = AppEnvironment(
                dataRoot: root,
                fixtureMode: .ui,
                onlineSourceEnabled: false
            )
            let repository = RadarRepository(
                container: try environment.makeModelContainer(),
                metadataStore: SyncMetadataStore(root: root)
            )

            try await DebugUISeed.populate(
                repository: repository,
                sourceID: sourceID,
                state: "warning-fresh-cards",
                now: now
            )

            for warningSourceID in [
                RadarSourceID.claudeCodeRadar,
                .codexRadar,
                .sweBenchVerified,
            ] {
                #expect(try await repository.snapshotCount(
                    datasetType: .renderedWarnings,
                    sourceID: warningSourceID
                ) == 0)
            }
            let warningState = try await repository.renderedWarningState(sourceID: sourceID)
            #expect(warningState.value == nil)
            #expect(warningState.error == nil)
        }
    }

    @MainActor
    private func load(state: String) async throws -> LoadedFixture {
        let root = temporaryRoot(state)
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let seedEnvironment = AppEnvironment(
            dataRoot: root,
            fixtureMode: .ui,
            onlineSourceEnabled: false
        )
        let repository = RadarRepository(
            container: try seedEnvironment.makeModelContainer(),
            metadataStore: SyncMetadataStore(root: root)
        )
        try await DebugUISeed.populate(
            repository: repository,
            sourceID: .codexRadar,
            state: state,
            now: now
        )

        let persistedEnvironment = AppEnvironment(
            dataRoot: root,
            fixtureMode: .disabled,
            onlineSourceEnabled: false
        )
        let reader = DebugWarningReaderProbe()
        let runtime = RadarAppRuntime(
            environment: persistedEnvironment,
            sourceID: .codexRadar,
            renderedWarningReaderFactory: { reader }
        )
        await runtime.start()
        return LoadedFixture(
            root: root,
            now: now,
            repository: repository,
            reader: reader,
            runtime: runtime
        )
    }

    private func assertFourCards(
        _ projection: SegmentState<CodexRenderedWarningSnapshot>,
        capturedAt: Date
    ) throws {
        let snapshot = try #require(projection.value)
        #expect(snapshot.sourceID == .codexRadar)
        #expect(snapshot.parserRevision == CodexRenderedWarningDOMParser.parserRevision)
        #expect(snapshot.finalOrigin == "https://codexradar.com")
        #expect(snapshot.sourceTimeLabel == "数据更新于 2 分钟前")
        #expect(snapshot.capturedAt == capturedAt)
        #expect(snapshot.cards.map(\.displayName) == [
            "GPT-5.6 Sol · Max",
            "GPT-5.6 Sol · High",
            "GPT-5.5 Codex · Medium",
            "GPT-5.4 · Low",
        ])
        #expect(snapshot.cards.map(\.sourceOrder) == [0, 1, 2, 3])
        #expect(snapshot.cards.map(\.iq) == [128.5, 126, 119, 110])
        #expect(snapshot.cards.map(\.drop24h) == [2.25, 1, 0, 3])
        #expect(snapshot.cards.map(\.drop48h) == [4.5, 2, 0.5, nil])
    }

    private func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "CodexRenderedWarningDebugFixtureTests-\(name)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }
}

@MainActor
private final class DebugWarningReaderProbe: CodexRenderedWarningReading {
    private(set) var readCount = 0

    func read() async throws -> CodexRenderedWarningSnapshot {
        readCount += 1
        throw DebugWarningReaderError.unexpectedRead
    }

    func cancel() {}
}

private enum DebugWarningReaderError: Error {
    case unexpectedRead
}

@MainActor
private struct LoadedFixture {
    let root: URL
    let now: Date
    let repository: RadarRepository
    let reader: DebugWarningReaderProbe
    let runtime: RadarAppRuntime
}
#endif
