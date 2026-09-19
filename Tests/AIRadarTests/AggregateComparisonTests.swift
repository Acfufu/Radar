import Foundation
import Testing
@testable import AIRadar

/// v0.4.0 aggregate comparison view tests (spec §4.1 v1.1/v1.2, D10): the
/// four-station union scope, per-point source-station labels, no local
/// re-ranking, nil-data empty state, and the kimi exclusion.
@Suite("AggregateComparisonTests")
struct AggregateComparisonTests {
    private func dataset(points: [IntelligenceEfficiencyDataset.Point]) -> IntelligenceEfficiencyDataset {
        IntelligenceEfficiencyDataset(
            sourceID: .codexRadar,
            fetchedAt: Date(timeIntervalSince1970: 100),
            points: points
        )
    }

    @Test("groups follow station navigator order with payload order preserved inside")
    func groupOrderAndPayloadOrder() {
        let dataset = dataset(points: [
            .init(model: "glm-5.3", effort: "high", iq: 97),
            .init(model: "gpt-6-astra", effort: "ultra", iq: 108),
            .init(model: "grok-4.6", effort: "xhigh", iq: 108),
            .init(model: "gpt-5.6-sol", effort: "xhigh", iq: 101),
            .init(model: "dsh-deepseek-v4-pro", effort: "max", iq: 82),
        ])
        let groups = AggregateComparison.groups(from: dataset)
        #expect(groups.map(\.sourceLabel) == ["Codex", "DSH", "ZCode", "Grok"])
        // Within a group, the upstream payload order is preserved verbatim —
        // the comparison never constructs a global ranking (D10).
        #expect(groups[0].rows.map(\.model) == ["gpt-6-astra", "gpt-5.6-sol"])
        #expect(groups[1].rows.map(\.model) == ["dsh-deepseek-v4-pro"])
        #expect(groups[2].rows.map(\.model) == ["glm-5.3"])
        #expect(groups[3].rows.map(\.model) == ["grok-4.6"])
        #expect(groups[0].rows[0].sourceLabel == "Codex")
        #expect(groups[1].rows[0].sourceLabel == "DSH")
    }

    @Test("union scope excludes stationless models (kimi-k2.8-preview, data-plane extras)")
    func unionScope() {
        let dataset = dataset(points: [
            .init(model: "kimi-k2.8-preview", effort: "high", iq: 100),
            .init(model: "dsh-deepseek-v4.1-flash", effort: "max", iq: 97),
            .init(model: "gemini-3.8-flash", effort: "high", iq: 90),
            .init(model: "glm-5.3", effort: "high", iq: 97),
        ])
        let groups = AggregateComparison.groups(from: dataset)
        #expect(groups.count == 1)
        #expect(groups[0].sourceLabel == "ZCode")
        #expect(groups[0].rows.count == 1)
        // The union itself never grows beyond the four stations' sets.
        #expect(AggregateComparison.unionModels.contains("deepseek-v4-pro"))
        #expect(!AggregateComparison.unionModels.contains("kimi-k2.8-preview"))
        #expect(!AggregateComparison.unionModels.contains("glm-5.3-flash"))
        #expect(!AggregateComparison.unionModels.contains("dsh-deepseek-v4-flash-vision-exp"))
    }

    @Test("nil dataset yields an empty group list (card shows its empty state)")
    func nilData() {
        #expect(AggregateComparison.groups(from: nil).isEmpty)
        #expect(AggregateComparison.groups(from: dataset(points: [])).isEmpty)
    }
}
