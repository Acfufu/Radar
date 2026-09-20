import Charts
import SwiftUI

extension OfficialOverviewSections {
    /// Row 1 IQ trend card. The deng v1 rendered reader is retired
    /// (ADR-0002); the official side returns sourced from the public
    /// intelligence-efficiency `history[]` data plane (spec §6 v1.1).
    @ViewBuilder var officialIQHistoryTrend: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("IQ 趋势")
                    .font(.headline)
                LocalIQTrendChart(projection: projection, history: history)
            }
            .padding(.top, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("codex-iq-trend-section")
    }
}
