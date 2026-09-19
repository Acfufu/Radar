import SwiftUI

// Aggregate-station cross-station comparison view (spec §4.1 v1.1/v1.2,
// D10 hard boundary): a view-layer-only composition over the shared
// intelligence-efficiency sidecar dataset. The four real stations'
// whitelists are united (Codex ∪ DSH ∪ ZCode ∪ Grok); every row carries
// its source-station label; rows keep the upstream payload order inside
// per-station groups — no unified ranking, no composite scores, no
// cross-source metric comparison, no export, no banner.

/// One comparison row: a model tier annotated with its source station.
struct AggregateComparisonRow: Identifiable, Equatable, Sendable {
    let id: String
    let sourceLabel: String
    let model: String
    let effort: String
    let iq: Double?
    let samples: Int?
}

/// One per-station group; group order is the upstream navigator order.
struct AggregateComparisonGroup: Identifiable, Equatable, Sendable {
    let id: String
    let sourceLabel: String
    let rows: [AggregateComparisonRow]
}

enum AggregateComparison {
    /// Station navigator order for the groups (spec §4.1 sidebar note).
    static let groupOrder: [(label: String, models: Set<String>)] = [
        (label: "Codex", models: [
            "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5",
            "deepseek-v4-flash", "deepseek-v4-pro",
        ]),
        (label: "DSH", models: ["dsh-deepseek-v4-flash", "dsh-deepseek-v4-pro"]),
        (label: "ZCode", models: ["glm-5.3"]),
        (label: "Grok", models: ["grok-4.6"]),
    ]

    /// The four-station union; anything outside (e.g. `kimi-k2.8-preview`,
    /// `dsh-deepseek-v4.1-flash`) has no station and never renders.
    static var unionModels: Set<String> {
        var union = Set<String>()
        for group in groupOrder { union.formUnion(group.models) }
        return union
    }

    static func groups(from dataset: IntelligenceEfficiencyDataset?) -> [AggregateComparisonGroup] {
        guard let dataset else { return [] }
        return groupOrder.compactMap { entry in
            let rows: [AggregateComparisonRow] = dataset.points.compactMap { point -> AggregateComparisonRow? in
                guard let model = point.model, entry.models.contains(model) else { return nil }
                return AggregateComparisonRow(
                    id: "\(entry.label)|\(model)@\(point.effort ?? "—")",
                    sourceLabel: entry.label,
                    model: model,
                    effort: point.effort ?? "—",
                    iq: point.iq,
                    samples: point.runsTotal
                )
            }
            guard !rows.isEmpty else { return nil }
            return AggregateComparisonGroup(id: entry.label, sourceLabel: entry.label, rows: rows)
        }
    }
}

/// The aggregate station's comparison section (spec §4.1 聚合站 row).
struct AggregateComparisonCard: View {
    @Environment(\.radarPalette) private var palette
    let groups: [AggregateComparisonGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            ViewHeader(
                title: "跨站同基准对比",
                subtitle: "四实站同一软件工程基准的档位并集；逐点标注来源站，不构成统一排名（D10）"
            )
            if groups.isEmpty {
                Text("暂无对比数据：共享效能数据面尚未同步。")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText.color)
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
                        Text(group.sourceLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.accent.color)
                        ForEach(group.rows) { row in
                            HStack {
                                Text("[\(row.sourceLabel)] \(row.model) · \(row.effort)")
                                    .font(.subheadline)
                                Spacer()
                                if let iq = row.iq {
                                    Text("IQ \(String(format: "%.1f", iq))")
                                        .monospacedDigit()
                                }
                                if let samples = row.samples {
                                    Text("n=\(samples)")
                                        .font(.caption)
                                        .foregroundStyle(palette.secondaryText.color)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                Text("数据来自 Codex 雷达 codexradar.com · 各站口径独立，无组合分数")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarPanel()
    }
}
