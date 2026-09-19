import Foundation
import Testing
@testable import AIRadar

/// v0.4.0 structured panel tests (spec §5.6/§5.7, §4.2 rows 1–2): the
/// view-model mapping for the three-capability tabs and the two structured
/// cards, nil-data empty states, verbatim upstream text, and the VSR /
/// visual_iq no-merge boundary.
@Suite("CodexInsightsPanelsTests")
struct CodexInsightsPanelsTests {
    private func projection(
        insights: RadarInsightsDataset? = nil,
        vsr: VisualSpatialReasoningDataset? = nil
    ) -> WorkspaceProjection {
        var projection = WorkspaceProjection(
            sync: nil,
            lifecycle: .running,
            supportLevel: .authorized
        )
        projection.radarInsightsDataset = insights
        projection.visualSpatialReasoningDataset = vsr
        return projection
    }

    private func insightsDataset() -> RadarInsightsDataset {
        RadarInsightsDataset(
            sourceID: .codexRadar,
            fetchedAt: Date(timeIntervalSince1970: 100),
            benchmarkID: RadarInsightsParser.expectedBenchmarkID,
            comprehensivePoints: [
                .init(model: "m-astra", effort: "ultra", iq: 108.2, softwareIq: 101.4, visualIq: 135.1, samples: 156),
                .init(model: "m-sol", effort: "xhigh", iq: 100.2, softwareIq: nil, visualIq: 121.7, samples: 42),
            ],
            recommendations: [
                .init(
                    key: "daily_development",
                    title: "日常开发（上游原文标题）",
                    rule: "上游原文规则 R-1",
                    items: [
                        .init(
                            model: "m-astra",
                            effort: "high",
                            iq: 105.5,
                            averageCostUSD: 1.82,
                            averageDurationMinutes: 9.4,
                            combinedCostIndex: 17.3,
                            rule: "上游原文条目规则"
                        ),
                    ]
                ),
            ],
            degradationAlerts: .init(
                rule: "上游原文预警规则",
                items: [
                    .init(model: "m-sol", effort: "xhigh", severity: "warning", message: "上游原文预警内容", currentIq: 94.1, baselineIq: 100.2),
                ]
            )
        )
    }

    private func vsrDataset() -> VisualSpatialReasoningDataset {
        VisualSpatialReasoningDataset(
            sourceID: .codexRadar,
            fetchedAt: Date(timeIntervalSince1970: 100),
            benchmarkID: "pompeii-adjacency",
            type: VisualSpatialReasoningParser.expectedType,
            scoreLabel: "Adjacency F1",
            points: [
                .init(model: "m-astra", effort: "high", validTasks: 50, iq: 134.89),
            ]
        )
    }

    @Test("capability tabs map all three planes with independent captions")
    func capabilityTabsMapping() {
        let tabs = projection(insights: insightsDataset(), vsr: vsrDataset()).capabilityTabs
        #expect(tabs.count == 3)
        #expect(tabs[0].title == "综合智能")
        #expect(tabs[0].rows.count == 2)
        #expect(tabs[0].rows[0].score == 108.2)
        #expect(tabs[0].isEmpty == false)

        // Software tab renders only software_iq; rows without the component
        // are dropped rather than shown as blanks.
        #expect(tabs[1].title == "软件工程能力")
        #expect(tabs[1].rows.count == 1)
        #expect(tabs[1].rows[0].score == 101.4)
        #expect(tabs[1].isEmpty == false)

        // Visual tab reads the VSR dataset and its caption names the
        // independent benchmark — never comprehensive visual_iq (spec §5.7).
        #expect(tabs[2].title == "视觉空间推理")
        #expect(tabs[2].rows.count == 1)
        #expect(tabs[2].rows[0].score == 134.89)
        #expect(tabs[2].rows[0].samples == 50)
        #expect(tabs[2].scoreCaption.contains("Adjacency F1"))
        #expect(tabs[2].scoreCaption.contains("不与综合智能 visual_iq 合并"))
    }

    @Test("nil-data sidecars produce all-empty tabs and card empty states")
    func nilDataEmptyStates() {
        let tabs = projection().capabilityTabs
        #expect(tabs.count == 3)
        #expect(tabs.allSatisfy { $0.isEmpty })
        #expect(projection().structuredAlerts.isEmpty)
        #expect(projection().structuredRecommendations.isEmpty)

        // An insights payload with only null software components keeps the
        // software tab empty while the comprehensive tab has rows.
        let partial = RadarInsightsDataset(
            sourceID: .codexRadar,
            fetchedAt: Date(timeIntervalSince1970: 100),
            comprehensivePoints: [.init(model: "m", effort: "high", iq: 80, softwareIq: nil)]
        )
        let partialTabs = projection(insights: partial).capabilityTabs
        #expect(partialTabs[0].isEmpty == false)
        #expect(partialTabs[1].isEmpty)
    }

    @Test("structured cards carry upstream text verbatim with no local derivation")
    func verbatimText() {
        let dataset = insightsDataset()
        let alerts = projection(insights: dataset).structuredAlerts
        #expect(alerts.count == 1)
        #expect(alerts[0].model == "m-sol")
        #expect(alerts[0].message == "上游原文预警内容")
        #expect(alerts[0].currentIq == 94.1)
        #expect(alerts[0].baselineIq == 100.2)

        let scenes = projection(insights: dataset).structuredRecommendations
        #expect(scenes.count == 1)
        #expect(scenes[0].title == "日常开发（上游原文标题）")
        #expect(scenes[0].rule == "上游原文规则 R-1")
        #expect(scenes[0].items[0].rule == "上游原文条目规则")
        #expect(scenes[0].items[0].averageCostUSD == Decimal(string: "1.82"))

        // Empty alerts block → empty card state, not fabricated rows.
        let empty = RadarInsightsDataset(
            sourceID: .codexRadar,
            fetchedAt: Date(timeIntervalSince1970: 100),
            degradationAlerts: .init(rule: "r", items: [])
        )
        #expect(projection(insights: empty).structuredAlerts.isEmpty)
    }
}
