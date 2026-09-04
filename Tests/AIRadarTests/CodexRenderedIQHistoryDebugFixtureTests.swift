import Foundation
import Testing
@testable import AIRadar

#if DEBUG
@Suite("CodexRenderedIQHistoryDebugFixtureTests", .serialized)
struct CodexRenderedIQHistoryDebugFixtureTests {
    private let states = [
        "iq-loading",
        "iq-fresh",
        "iq-stale",
        "iq-lkg-error",
        "iq-schema-drift",
        "iq-challenge",
        "iq-unavailable",
    ]

    @Test("Debug selectors expose every official IQ-history state and open Codex")
    func launchSelectors() {
        // Given
        let variables = ["RADAR_UI_SOURCE": "codexRadar"]

        // When
        let source = AppEnvironment.debugInitialSourceID(fixtureMode: .ui, variables: variables)

        // Then
        #expect(DebugUISeed.renderedIQHistoryStates == Set(states))
        #expect(source == .codexRadar)
    }

    @MainActor
    @Test("official IQ-history fixtures hydrate through the Codex workspace without reads")
    func persistedStateMatrix() async throws {
        // Given
        for state in states {
            let fixture = try await load(state: state)
            defer { try? FileManager.default.removeItem(at: fixture.root) }

            // When
            let projection = try #require(fixture.model.projection?.renderedIQHistoryPresentation)

            // Then
            #expect(fixture.reader.readCount == 0, "Unexpected IQ-history read for \(state)")
            #expect(fixture.runtime.lifecycleState == .running)
            #expect(fixture.model.selectedSourceID == .codexRadar)
            #expect(!fixture.runtime.environment.synchronizationEnabled(for: .codexRadar))
            #expect((try await RawSampleStore(dataRoot: fixture.root).samples(sourceID: .codexRadar)).isEmpty)
            #expect(projection.sectionAccessibilityIdentifier == "codex-rendered-iq-history-section")
            #expect(projection.stateAccessibilityIdentifier == "codex-rendered-iq-history-state-\(expectedState(state).rawValue)")

            switch state {
            case "iq-loading":
                #expect(projection.state == .loading)
                #expect(projection.series.isEmpty)
                #expect(projection.lastSuccessfulAt == nil)
                #expect(projection.errorMessage == nil)
            case "iq-fresh":
                try assertSnapshot(projection, capturedAt: fixture.now)
                #expect(projection.state == .fresh)
                #expect(projection.lastSuccessfulAt == fixture.now)
                #expect(projection.errorMessage == nil)
            case "iq-stale":
                let capturedAt = fixture.now.addingTimeInterval(-8 * 60 * 60)
                try assertSnapshot(projection, capturedAt: capturedAt)
                #expect(projection.state == .staleLastKnownGood)
                #expect(projection.lastSuccessfulAt == capturedAt)
                #expect(projection.errorMessage == nil)
            case "iq-lkg-error":
                let capturedAt = fixture.now.addingTimeInterval(-30 * 60)
                try assertSnapshot(projection, capturedAt: capturedAt)
                #expect(projection.state == .lastKnownGoodWithError)
                #expect(projection.lastSuccessfulAt == capturedAt)
                #expect(projection.errorMessage == "Rendered IQ history fixture refresh failed")
            case "iq-schema-drift":
                #expect(projection.state == .schemaDriftWithoutLastKnownGood)
                #expect(projection.series.isEmpty)
                #expect(projection.lastSuccessfulAt == nil)
                #expect(projection.errorMessage == "Rendered IQ history fixture schema drift")
            case "iq-challenge":
                #expect(projection.state == .challengeWithoutLastKnownGood)
                #expect(projection.series.isEmpty)
                #expect(projection.lastSuccessfulAt == nil)
                #expect(projection.errorMessage == "Rendered IQ history fixture challenge")
            case "iq-unavailable":
                #expect(projection.state == .unavailableWithoutLastKnownGood)
                #expect(projection.series.isEmpty)
                #expect(projection.lastSuccessfulAt == nil)
                #expect(projection.errorMessage == "Rendered IQ history fixture unavailable")
            default:
                Issue.record("Unhandled fixture state \(state)")
            }

            await fixture.model.stop()
        }
    }

    @Test("only the Codex fixture writes official IQ-history rows")
    func sourceIsolation() async throws {
        // Given
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        for sourceID in [RadarSourceID.claudeCodeRadar, .sweBenchVerified] {
            let root = temporaryRoot("SourceIsolation-\(sourceID.rawValue)")
            defer { try? FileManager.default.removeItem(at: root) }
            let environment = AppEnvironment(dataRoot: root, fixtureMode: .ui, onlineSourceEnabled: false)
            let repository = RadarRepository(
                container: try environment.makeModelContainer(),
                metadataStore: SyncMetadataStore(root: root)
            )

            // When
            try await DebugUISeed.populate(
                repository: repository,
                sourceID: sourceID,
                state: "iq-fresh",
                now: now
            )

            // Then
            for historySourceID in [RadarSourceID.claudeCodeRadar, .codexRadar, .sweBenchVerified] {
                #expect(try await repository.snapshotCount(
                    datasetType: .renderedIQHistory,
                    sourceID: historySourceID
                ) == 0)
            }
        }
    }

    @MainActor
    private func load(state: String) async throws -> LoadedFixture {
        let root = temporaryRoot(state)
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        let environment = AppEnvironment(dataRoot: root, fixtureMode: .ui, onlineSourceEnabled: false)
        let repository = RadarRepository(
            container: try environment.makeModelContainer(),
            metadataStore: SyncMetadataStore(root: root)
        )
        try await DebugUISeed.populate(repository: repository, sourceID: .codexRadar, state: state, now: now)

        let reader = DebugIQHistoryReaderProbe()
        let runtime = RadarAppRuntime(
            environment: environment,
            sourceID: .codexRadar,
            renderedIQHistoryReaderFactory: { reader }
        )
        let model = RadarWorkspaceModel(runtimes: [.codexRadar: runtime], selectedSourceID: .codexRadar)
        await model.start()
        return LoadedFixture(root: root, now: now, reader: reader, runtime: runtime, model: model)
    }

    private func expectedState(_ state: String) -> CodexRenderedIQHistoryPresentation.State {
        switch state {
        case "iq-loading": .loading
        case "iq-fresh": .fresh
        case "iq-stale": .staleLastKnownGood
        case "iq-lkg-error": .lastKnownGoodWithError
        case "iq-schema-drift": .schemaDriftWithoutLastKnownGood
        case "iq-challenge": .challengeWithoutLastKnownGood
        default: .unavailableWithoutLastKnownGood
        }
    }

    private func assertSnapshot(
        _ projection: CodexRenderedIQHistoryPresentation,
        capturedAt: Date
    ) throws {
        let selected = try #require(projection.selectedSeries)
        #expect(projection.selection == .aggregate)
        #expect(selected.seriesKey == "aggregate")
        #expect(selected.points.map(\.ordinal) == Array(0...23))
        #expect(selected.points.map(\.sourceTimeLabel) == (0...23).map { "07/27 \(String(format: "%02d", $0)):00" })
        #expect(projection.capturedAt == capturedAt)
        #expect(projection.series.map(\.seriesKey) == [
            "aggregate",
            "model:gpt-5.6-sol",
            "model:gpt-5.5-codex",
            "model:gpt-5.4",
            "model:gpt-5-mini",
        ])
        #expect(projection.series.allSatisfy { $0.points.count == 24 })
    }

    private func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "CodexRenderedIQHistoryDebugFixtureTests-\(name)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }
}

@MainActor
private final class DebugIQHistoryReaderProbe: CodexRenderedIQHistoryReading {
    private(set) var readCount = 0

    func read() async throws -> CodexRenderedIQHistorySnapshot {
        readCount += 1
        throw DebugIQHistoryReaderError.unexpectedRead
    }

    func cancel() {}
}

private enum DebugIQHistoryReaderError: Error {
    case unexpectedRead
}

@MainActor
private struct LoadedFixture {
    let root: URL
    let now: Date
    let reader: DebugIQHistoryReaderProbe
    let runtime: RadarAppRuntime
    let model: RadarWorkspaceModel
}
#endif
