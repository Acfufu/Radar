import Foundation
import SwiftData
import Testing
@testable import AIRadar

@Suite("CodexIQHistoryPanelContractTests")
struct CodexIQHistoryPanelContractTests {
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test("C4 renders four honest effort-colored local-history small multiples")
    func panelContract() throws {
        let panel = try source("Sources/AIRadar/Features/Analytics/CodexIQHistoryPanel.swift")

        #expect(panel.contains("CodexIQHistoryAnalytics.project(history: history)"))
        #expect(panel.contains("RadarModelIdentity.canonicalFamilies"))
        #expect(panel.contains("LineMark("))
        #expect(panel.contains("PointMark("))
        #expect(panel.contains("foregroundStyle(by: .value(\"努力等级\""))
        #expect(panel.contains(".chartLegend(position: .bottom"))
        #expect(panel.contains("努力等级图例"))
        #expect(panel.contains("series: .value(\"分段\", segment.id)"))
        #expect(panel.contains("来源更新时间，缺失时使用本地抓取时间"))
        #expect(panel.contains("努力等级 \\(effort)"))
        #expect(panel.contains("IQ \\(number(point.value))"))
        #expect(panel.contains("数据版本 \\(segment.seriesRevision)"))
        #expect(panel.contains("同数据版本的\\n有效 IQ 点。\\n缺失或冲突值"))
        #expect(panel.contains("不会以 0 代替"))
        #expect(panel.contains(".accessibilityIdentifier(\"codex-iq-history\")"))
    }

    @Test("C4 compact axis policy emits separated unambiguous date-time ticks")
    func compactAxisPolicy() throws {
        let calendar = try #require(Calendar(identifier: .gregorian).configuredForAxisTest())
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 30,
            hour: 8,
            minute: 15
        )))
        let end = try #require(calendar.date(byAdding: .hour, value: 24, to: start))
        let domain = start ... end

        let compact = CodexIQHistoryAxisPolicy.projection(
            domain: domain,
            availableWidth: 320,
            calendar: calendar
        )
        let regular = CodexIQHistoryAxisPolicy.projection(
            domain: domain,
            availableWidth: 520,
            calendar: calendar
        )
        let expanded = CodexIQHistoryAxisPolicy.projection(
            domain: domain,
            availableWidth: 760,
            calendar: calendar
        )

        #expect(compact.labels == ["07/30\n14:15", "07/31\n02:15"])
        #expect(regular.labels == ["07/30\n12:15", "07/30\n20:15", "07/31\n04:15"])
        #expect(expanded.labels == [
            "07/30\n11:15",
            "07/30\n17:15",
            "07/30\n23:15",
            "07/31\n05:15",
        ])
        #expect(Set(compact.labels).count == compact.labels.count)
        #expect(Set(regular.labels).count == regular.labels.count)
        #expect(Set(expanded.labels).count == expanded.labels.count)
    }

    @Test("intelligence center composes C1 through C5 with explicit provenance")
    func integrationAndProvenanceContract() throws {
        let center = try source("Sources/AIRadar/Features/Analytics/CodexIntelligenceCenterView.swift")

        #expect(center.contains("CodexIQHistorySmallMultiplesPanel("))
        #expect(!center.contains("IntelligenceCenterSlot"))
        #expect(center.contains("C1-C3"))
        #expect(center.contains("C4-C5"))
        #expect(center.contains("projection.source.attributionText"))
    }

    @Test("source contract distinguishes summary derivations from persisted history")
    func sourceContract() throws {
        let contract = try source("docs/source-contract.md")

        #expect(contract.contains("C1-C3"))
        #expect(contract.contains("C4-C5"))
        #expect(contract.contains("本地持久化"))
        #expect(contract.contains("不消费新的网页 API"))
    }

    #if DEBUG
    @Test("Debug-only insufficient fixture is guarded idempotent and never flattens gaps to zero")
    func insufficientFixture() async throws {
        let dataRoot = FileManager.default.temporaryDirectory
            .appending(path: "Radar-Todo8-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: dataRoot) }
        let now = Date(timeIntervalSince1970: 1_900_100_000)
        let environment = AppEnvironment(dataRoot: dataRoot, fixtureMode: .ui, onlineSourceEnabled: false)
        let repository = RadarRepository(
            container: try environment.makeModelContainer(),
            metadataStore: SyncMetadataStore(root: dataRoot)
        )

        try await DebugUISeed.populate(
            repository: repository,
            sourceID: .codexRadar,
            state: "analytics-todo8-insufficient",
            now: now
        )
        let initial = try await repository.benchmarkHistory(sourceID: .codexRadar)
        try await DebugUISeed.populate(
            repository: repository,
            sourceID: .codexRadar,
            state: "analytics-todo8-insufficient",
            now: now.addingTimeInterval(3_600)
        )
        let repeated = try await repository.benchmarkHistory(sourceID: .codexRadar)
        let projected = CodexIQHistoryAnalytics.project(history: repeated)

        #expect(initial.count == 4)
        #expect(repeated.count == initial.count)
        #expect(projected.availability == .insufficientHistory)
        #expect(projected.panels.map(\.family) == ["Sol", "Terra", "Luna", "GPT-5.5"])
        #expect(projected.panels.allSatisfy {
            $0.lines.flatMap(\.segments).allSatisfy { $0.points.count == 1 && $0.points[0].value > 0 }
        })

        let fixture = try source("Sources/AIRadar/App/DebugUISeed.swift")
        #expect(fixture.hasPrefix("#if DEBUG"))
        #expect(fixture.contains("state == \"analytics-todo8-insufficient\""))
    }
    #endif

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }
}

private extension Calendar {
    func configuredForAxisTest() -> Calendar? {
        var calendar = self
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
