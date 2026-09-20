import SwiftUI

// deng crowdtest IQ station card (spec §4.1 v1.2 / §6 v1.2, ADR-0004).
// Components consume locally defined view-models only (spec §7); upstream
// methodology text is verbatim; the crowdtest plane (最近 3 次有效运行、
// 全任务等权) never merges with 综合智能 IQ or local fitting, and the
// aggregate station never consumes it.

/// Display view-model for one crowdtest harness row.
struct CrowdtestIQRowView: Identifiable, Equatable, Sendable {
    let id: String
    let model: String
    let effort: String
    let iq: Double?
    let coveredTasks: Int?
    let totalTasks: Int?
    let coverageInsufficient: Bool
}

/// Display view-model for one station's crowdtest IQ card.
struct CrowdtestIQCardModel: Equatable, Sendable {
    enum Level: Equatable, Sendable {
        case fresh, stale, error, muted
    }

    let harness: String
    let rows: [CrowdtestIQRowView]
    let latestTrendLabel: String?
    let stateMessage: String
    let isEmpty: Bool
    let level: Level
}

enum CrowdtestIQCardMapper {
    /// Independent freshness for the card's own status dot (spec §4.1 v1.2).
    static func statusLevel(_ state: SegmentState<CodexRenderedCrowdtestIQSnapshot>?) -> StationStatusLevel {
        guard let state else { return .muted }
        if state.error != nil { return .error }
        if state.value == nil { return .muted }
        return state.isStale ? .stale : .fresh
    }

    /// Maps the shared crowdtest snapshot onto one station's harness
    /// family. `nil` when the snapshot is absent, stale beyond display, or
    /// the family has no cells (each case renders the card's empty state).
    static func model(
        harness: String,
        state: SegmentState<CodexRenderedCrowdtestIQSnapshot>?
    ) -> CrowdtestIQCardModel? {
        guard let snapshot = state?.value else { return nil }
        let cards = snapshot.harnesses.filter { $0.harness == harness }
        guard !cards.isEmpty else { return nil }

        let rows = cards.flatMap { card in
            card.cells.map { cell in
                CrowdtestIQRowView(
                    id: "\(card.harness)|\(cell.model)@\(cell.effort)",
                    model: cell.model,
                    effort: cell.effort,
                    iq: cell.iqScore,
                    coveredTasks: cell.coveredTasks,
                    totalTasks: cell.totalTasks,
                    coverageInsufficient: cell.coverageInsufficient
                )
            }
        }
        let labels = cards.flatMap(\.trend).map(\.label)
        let stateMessage: String
        let level: CrowdtestIQCardModel.Level
        if state?.error != nil {
            stateMessage = "读取失败，显示最近有效数据"
            level = .error
        } else if state?.isStale == true {
            stateMessage = "正在显示可能已过期的最近有效数据"
            level = .stale
        } else {
            stateMessage = "众测 IQ 已更新"
            level = .fresh
        }
        return CrowdtestIQCardModel(
            harness: harness,
            rows: rows,
            latestTrendLabel: labels.last,
            stateMessage: stateMessage,
            isEmpty: rows.allSatisfy { $0.iq == nil },
            level: level
        )
    }
}

/// The station card itself: header + dot, per-tier rows, verbatim trend
/// label, and the deng attribution with the no-mixing boundary line.
struct CrowdtestIQCard: View {
    @Environment(\.radarPalette) private var palette
    let model: CrowdtestIQCardModel?
    let attributionText: String

    var body: some View {
        VStack(alignment: .leading, spacing: RadarStyle.compactSpacing) {
            HStack(spacing: 6) {
                Label("众测 IQ", systemImage: "person.2.wave.2")
                    .font(.headline)
                Spacer()
                StationStatusDot(level: dotLevel(model))
            }
            if let model {
                if model.isEmpty {
                    Text("暂无有效众测 IQ（覆盖率不足或未判分）")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText.color)
                } else {
                    Text(model.stateMessage)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)
                    ForEach(model.rows) { row in
                        HStack {
                            Text("\(row.model) · \(row.effort)")
                                .font(.subheadline)
                            if row.coverageInsufficient {
                                Text("覆盖率不足")
                                    .font(.caption2)
                                    .foregroundStyle(palette.amber.color)
                            }
                            Spacer()
                            if let iq = row.iq, iq > 0 {
                                Text("IQ \(String(format: "%.0f", iq))")
                                    .monospacedDigit()
                            } else {
                                Text("—")
                                    .foregroundStyle(palette.secondaryText.color)
                            }
                        }
                        .font(.subheadline)
                    }
                    if let trend = model.latestTrendLabel {
                        Text("小时趋势最新：\(trend)")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText.color)
                            .monospacedDigit()
                            .textSelection(.enabled)
                    }
                }
                Text(attributionText + " · 众测口径（最近 3 次有效运行、全任务等权），与站内其他 IQ 分卡展示、永不混算")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText.color)
            } else {
                Text("暂无众测数据（读取器尚未同步或不可用）")
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText.color)
                Text(attributionText)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarPanel()
    }
}

extension CrowdtestIQCard {
    /// Dot: muted without a card or rows; else the mapped snapshot level.
    func dotLevel(_ model: CrowdtestIQCardModel?) -> StationStatusLevel {
        guard let model, !model.rows.isEmpty else { return .muted }
        switch model.level {
        case .error: return .error
        case .stale: return .stale
        case .fresh: return .fresh
        case .muted: return .muted
        }
    }
}
