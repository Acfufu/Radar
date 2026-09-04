import Charts
import SwiftUI

struct OfficialOverviewSections: View {
    @Environment(\.radarPalette) var palette
    let projection: WorkspaceProjection
    let history: [BenchmarkDataset]

    @State var codexIQChartSource: CodexRenderedIQHistoryChartSource = .official24h
    @State var officialIQSelection: CodexRenderedIQHistoryPresentation.Selection = .aggregate

    var body: some View {
        Group {
            officialWarnings
            officialIQHistoryTrend
        }
    }

    @ViewBuilder private var officialWarnings: some View {
        if let warning = projection.renderedWarningPresentation {
            radarOverviewSection("Codex Radar 官网降智预警") {
                VStack(alignment: .leading, spacing: 12) {
                    Label(warning.stateMessage, systemImage: warningStateIcon(warning.state))
                        .foregroundStyle(warningStateColor(warning.state))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(warning.stateAccessibilityIdentifier)
                        .accessibilityLabel(warning.stateAccessibilityLabel)

                    if let error = warning.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(palette.negative.color)
                            .textSelection(.enabled)
                    }

                    if !warning.cards.isEmpty {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 220), alignment: .top)],
                            spacing: RadarStyle.cardSpacing
                        ) {
                            ForEach(warning.cards, id: \.sourceOrder) { card in
                                officialWarningCard(card, presentation: warning)
                            }
                        }
                    }

                    if warning.sourceTimeLabel != nil || warning.capturedAt != nil {
                        HStack(spacing: 14) {
                            if let sourceTime = warning.sourceTimeLabel {
                                Text("官网时间：\(sourceTime)")
                                    .accessibilityIdentifier(warning.sourceTimeAccessibilityIdentifier)
                                    .accessibilityLabel(warning.sourceTimeAccessibilityLabel)
                            }
                            if let capturedAt = warning.capturedAt {
                                Text("本地采集时间：\(capturedAt.ISO8601Format())")
                                    .accessibilityIdentifier(warning.capturedAtAccessibilityIdentifier)
                                    .accessibilityLabel(warning.capturedAtAccessibilityLabel)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    }

                    Text(warning.attribution)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.top, 4)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(warning.sectionAccessibilityIdentifier)
            .accessibilityLabel(warning.sectionAccessibilityLabel)
        }
    }

    private func officialWarningCard(
        _ card: CodexRenderedWarningCard,
        presentation: CodexRenderedWarningPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.displayName)
                .font(.headline)
                .lineLimit(2)
            Text("\(card.family) · \(card.effort)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("IQ \(officialMetric(card.iq))")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            HStack(spacing: 12) {
                Text("24h ↓\(officialMetric(card.drop24h))")
                if let drop48h = card.drop48h {
                    Text("48h ↓\(officialMetric(drop48h))")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(palette.negative.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .radarMetricCard()
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(presentation.cardAccessibilityIdentifier(card))
        .accessibilityLabel(presentation.cardAccessibilityLabel(card))
    }

    private func warningStateIcon(_ state: CodexRenderedWarningPresentation.State) -> String {
        switch state {
        case .loading: "arrow.triangle.2.circlepath"
        case .freshCards: "checkmark.circle.fill"
        case .freshEmpty: "checkmark.circle"
        case .staleLastKnownGood: "clock.fill"
        case .lastKnownGoodWithError, .errorWithoutLastKnownGood: "exclamationmark.triangle.fill"
        }
    }

    private func warningStateColor(_ state: CodexRenderedWarningPresentation.State) -> Color {
        switch state {
        case .freshCards, .freshEmpty: .green
        case .loading: palette.secondaryText.color
        case .staleLastKnownGood: .orange
        case .lastKnownGoodWithError, .errorWithoutLastKnownGood: palette.negative.color
        }
    }

    func officialMetric(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
