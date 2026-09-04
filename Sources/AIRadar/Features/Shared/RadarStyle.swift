import Accessibility
import Foundation
import SwiftUI

struct RadarChartPoint {
    let x: Double
    let y: Double
    let label: String
}

struct RadarChartSeries {
    let name: String
    let isContinuous: Bool
    let points: [RadarChartPoint]
}

struct RadarChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let summary: String
    let xAxisTitle: String
    let yAxisTitle: String
    let xValueDescription: (Double) -> String
    let yValueDescription: (Double) -> String
    let series: [RadarChartSeries]

    func makeChartDescriptor() -> AXChartDescriptor {
        AXChartDescriptor(
            title: title,
            summary: summary,
            xAxis: axis(title: xAxisTitle, values: series.flatMap(\.points).map(\.x), description: xValueDescription),
            yAxis: axis(title: yAxisTitle, values: series.flatMap(\.points).map(\.y), description: yValueDescription),
            series: series.map { item in
                AXDataSeriesDescriptor(
                    name: item.name,
                    isContinuous: item.isContinuous,
                    dataPoints: item.points.map { AXDataPoint(x: $0.x, y: $0.y, label: $0.label) }
                )
            }
        )
    }

    static func dateTime(_ value: Double) -> String {
        Date(timeIntervalSince1970: value).formatted(date: .abbreviated, time: .shortened)
    }

    static func number(_ value: Double, unit: String = "") -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    private func axis(
        title: String,
        values: [Double],
        description: @escaping (Double) -> String
    ) -> AXNumericDataAxisDescriptor {
        let finite = values.filter(\.isFinite)
        let lower = finite.min() ?? 0
        let upper = finite.max() ?? 1
        let range = lower == upper ? (lower - 1)...(upper + 1) : lower...upper
        return AXNumericDataAxisDescriptor(
            title: title,
            range: range,
            gridlinePositions: [],
            valueDescriptionProvider: description
        )
    }
}

struct RadarColorToken: Equatable, Sendable {
    let hex: UInt32
    let opacity: Double

    static func rgb(_ hex: UInt32, opacity: Double = 1) -> Self {
        Self(hex: hex, opacity: opacity)
    }

    var color: Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

struct RadarShadow: Equatable, Sendable {
    let opacity: Double
    let radius: CGFloat
    let y: CGFloat
    let tint: RadarColorToken

    init(opacity: Double, radius: CGFloat, y: CGFloat, tint: RadarColorToken = .rgb(0x000000)) {
        self.opacity = opacity
        self.radius = radius
        self.y = y
        self.tint = tint
    }
}

struct RadarChartMetrics: Equatable, Sendable {
    let minimumCardWidth: CGFloat
    let minimumHeight: CGFloat
    let lineWidth: CGFloat
    let symbolSize: CGFloat
}

struct RadarHistoryAxisMetrics: Equatable, Sendable {
    let regularWidth: CGFloat
    let expandedWidth: CGFloat

    func tickCount(for availableWidth: CGFloat) -> Int {
        if availableWidth >= expandedWidth { return 4 }
        if availableWidth >= regularWidth { return 3 }
        return 2
    }
}

struct RadarHorizontalScrollAffordance: Equatable, Sendable {
    let title: String
    let systemImage: String
}

struct RadarAnalyticsLayoutMetrics: Equatable, Sendable {
    let matrixFamilyColumnWidth: CGFloat
    let matrixCellWidth: CGFloat
    let matrixRowHeight: CGFloat
    let comparisonMetricPickerMaximumWidth: CGFloat
    let comparisonBaselinePickerWidth: CGFloat
    let comparisonColumnSpacing: CGFloat
}

struct RadarAnalyticsColors: Equatable, Sendable {
    let familyColors: [RadarColorToken]

    func familyColor(at index: Int?) -> RadarColorToken {
        guard let index, familyColors.indices.contains(index) else {
            return familyColors.last ?? .rgb(0x0F766E)
        }
        return familyColors[index]
    }
}

struct RadarPalette: Equatable, Sendable {
    let canvas: RadarColorToken
    let section: RadarColorToken
    let card: RadarColorToken
    let primaryText: RadarColorToken
    let secondaryText: RadarColorToken
    let divider: RadarColorToken
    let dividerStrong: RadarColorToken
    let accent: RadarColorToken
    let accentSoft: RadarColorToken
    let accentBorder: RadarColorToken
    let positive: RadarColorToken
    let negative: RadarColorToken
    let green: RadarColorToken
    let greenSoft: RadarColorToken
    let amber: RadarColorToken
    let amberSoft: RadarColorToken
    let blue: RadarColorToken
    let blueSoft: RadarColorToken
    let red: RadarColorToken
    let redSoft: RadarColorToken
    let shadow: RadarShadow
}

enum RadarStyle {
    // Upstream geometry ladder (codexradar.com 2026-09-04 snapshot):
    // panels 15px, cards 7-11px, pills fully rounded.
    static let panelCornerRadius: CGFloat = 15
    static let cardCornerRadius: CGFloat = 11
    static let inlineCornerRadius: CGFloat = 7
    /// Legacy single-radius entry point; now card-level.
    static let cornerRadius: CGFloat = cardCornerRadius
    static let pageSpacing: CGFloat = 24
    static let sectionSpacing: CGFloat = 20
    static let cardSpacing: CGFloat = 14
    static let compactSpacing: CGFloat = 12
    static let accentBarWidth: CGFloat = 5
    static let historyAxisMetrics = RadarHistoryAxisMetrics(
        regularWidth: 440,
        expandedWidth: 700
    )
    static let horizontalScrollAffordance = RadarHorizontalScrollAffordance(
        title: "横向滚动查看更多",
        systemImage: "arrow.left.and.right"
    )
    static let analyticsLayout = RadarAnalyticsLayoutMetrics(
        matrixFamilyColumnWidth: 104,
        matrixCellWidth: 216,
        matrixRowHeight: 112,
        comparisonMetricPickerMaximumWidth: 260,
        comparisonBaselinePickerWidth: 130,
        comparisonColumnSpacing: 18
    )

    static func analyticsColors(for scheme: ColorScheme) -> RadarAnalyticsColors {
        // Four semantic families + one neutral, mapped from the upstream
        // green/blue/amber/red tokens (family mapping recorded in design-qa).
        switch scheme {
        case .dark:
            RadarAnalyticsColors(familyColors: [
                .rgb(0x34D399),
                .rgb(0x93C5FD),
                .rgb(0xFBBF24),
                .rgb(0xF87171),
                .rgb(0x8794A8),
            ])
        default:
            RadarAnalyticsColors(familyColors: [
                .rgb(0x047857),
                .rgb(0x245FC5),
                .rgb(0xB45309),
                .rgb(0xBE3144),
                .rgb(0x71809A),
            ])
        }
    }

    static func chartMetrics(for contrast: ColorSchemeContrast) -> RadarChartMetrics {
        RadarChartMetrics(
            minimumCardWidth: 300,
            minimumHeight: 240,
            lineWidth: contrast == .increased ? 4 : 2.5,
            symbolSize: contrast == .increased ? 70 : 45
        )
    }

    static func palette(
        for scheme: ColorScheme,
        contrast: ColorSchemeContrast = .standard
    ) -> RadarPalette {
        // Upstream tokens (codexradar.com 2026-09-04): [data-theme=light] and
        // [data-theme=dark] columns. color-mix tinted surfaces are realized
        // as opacity-layered soft tokens; increased contrast strengthens the
        // divider to line-strong and raises accent-border opacity only.
        let increased = contrast == .increased
        if scheme == .dark {
            return RadarPalette(
                canvas: .rgb(0x0D1420),
                section: .rgb(0x111827),
                card: .rgb(0x172033),
                primaryText: .rgb(0xE5EDF7),
                secondaryText: .rgb(0xA7B2C3),
                divider: .rgb(increased ? 0x35465F : 0x263449),
                dividerStrong: .rgb(0x35465F),
                accent: .rgb(0xFBBF24),
                accentSoft: .rgb(0xFBBF24, opacity: 0.14),
                accentBorder: .rgb(0xFBBF24, opacity: increased ? 0.55 : 0.28),
                positive: .rgb(0x34D399),
                negative: .rgb(0xF87171),
                green: .rgb(0x34D399),
                greenSoft: .rgb(0x10B981, opacity: 0.16),
                amber: .rgb(0xFBBF24),
                amberSoft: .rgb(0xFBBF24, opacity: 0.14),
                blue: .rgb(0x93C5FD),
                blueSoft: .rgb(0x60A5FA, opacity: 0.16),
                red: .rgb(0xF87171),
                redSoft: .rgb(0xF87171, opacity: 0.16),
                shadow: .init(opacity: 0.34, radius: 44, y: 18)
            )
        }
        return RadarPalette(
            canvas: .rgb(0xEDF4FF),
            section: .rgb(0xFFFFFF, opacity: 0.90),
            card: .rgb(0xF2F7FF, opacity: 0.92),
            primaryText: .rgb(0x12213B),
            secondaryText: .rgb(0x53647E),
            divider: increased ? .rgb(0x4E6FA3, opacity: 0.38) : .rgb(0x6F89B1, opacity: 0.25),
            dividerStrong: .rgb(0x4E6FA3, opacity: increased ? 0.55 : 0.38),
            accent: .rgb(0xB45309),
            accentSoft: .rgb(0xF59E0B, opacity: 0.13),
            accentBorder: .rgb(0xB45309, opacity: increased ? 0.60 : 0.30),
            positive: .rgb(0x047857),
            negative: .rgb(0xBE3144),
            green: .rgb(0x047857),
            greenSoft: .rgb(0x059669, opacity: 0.12),
            amber: .rgb(0xB45309),
            amberSoft: .rgb(0xF59E0B, opacity: 0.13),
            blue: .rgb(0x245FC5),
            blueSoft: .rgb(0x2563EB, opacity: 0.11),
            red: .rgb(0xBE3144),
            redSoft: .rgb(0xE11D48, opacity: 0.10),
            shadow: .init(opacity: 0.13, radius: 60, y: 22, tint: .rgb(0x28487A))
        )
    }
}

private struct RadarPaletteKey: EnvironmentKey {
    static let defaultValue = RadarStyle.palette(for: .light)
}

extension EnvironmentValues {
    var radarPalette: RadarPalette {
        get { self[RadarPaletteKey.self] }
        set { self[RadarPaletteKey.self] = newValue }
    }
}

private struct RadarAppModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let palette = RadarStyle.palette(for: colorScheme, contrast: contrast)
        content
            .environment(\.radarPalette, palette)
            .tint(palette.accent.color)
            .foregroundStyle(palette.primaryText.color)
            .background(palette.canvas.color)
    }
}

private struct RadarPageModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: RadarPalette {
        RadarStyle.palette(for: colorScheme, contrast: contrast)
    }

    func body(content: Content) -> some View {
        content
            .padding(RadarStyle.pageSpacing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.canvas.color)
    }
}

private struct RadarPanelModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: RadarPalette {
        RadarStyle.palette(for: colorScheme, contrast: contrast)
    }

    func body(content: Content) -> some View {
        content
            .padding(RadarStyle.cardSpacing)
            .background(palette.card.color, in: .rect(cornerRadius: RadarStyle.panelCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: RadarStyle.panelCornerRadius)
                    .stroke(palette.divider.color)
            }
            .shadow(
                color: palette.shadow.tint.color.opacity(palette.shadow.opacity),
                radius: palette.shadow.radius,
                y: palette.shadow.y
            )
    }
}

private struct RadarMetricCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: RadarPalette {
        RadarStyle.palette(for: colorScheme, contrast: contrast)
    }

    func body(content: Content) -> some View {
        content
            .padding(RadarStyle.cardSpacing)
            .background(palette.accentSoft.color, in: .rect(cornerRadius: RadarStyle.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: RadarStyle.cardCornerRadius)
                    .stroke(palette.accentBorder.color)
            }
    }
}

private struct RadarAccentCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    let accent: RadarColorToken
    let soft: RadarColorToken

    private var palette: RadarPalette {
        RadarStyle.palette(for: colorScheme, contrast: contrast)
    }

    func body(content: Content) -> some View {
        content
            .padding(RadarStyle.cardSpacing)
            .background(soft.color, in: .rect(cornerRadius: RadarStyle.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: RadarStyle.cardCornerRadius)
                    .stroke(accent.color.opacity(0.27))
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: RadarStyle.inlineCornerRadius)
                    .fill(accent.color)
                    .frame(width: RadarStyle.accentBarWidth)
                    .padding(.vertical, RadarStyle.compactSpacing)
                    .padding(.leading, 3)
            }
    }
}

private struct RadarPillModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    let accent: RadarColorToken
    let soft: RadarColorToken

    private var palette: RadarPalette {
        RadarStyle.palette(for: colorScheme, contrast: contrast)
    }

    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(soft.color, in: .capsule)
            .overlay { Capsule().stroke(accent.color.opacity(0.27)) }
    }
}

extension View {
    func radarAppStyle() -> some View { modifier(RadarAppModifier()) }
    func radarPage() -> some View { modifier(RadarPageModifier()) }
    func radarPanel() -> some View { modifier(RadarPanelModifier()) }
    func radarMetricCard() -> some View { modifier(RadarMetricCardModifier()) }
    /// Upstream accent card: left 5px accent bar over a soft tinted card.
    func radarAccentCard(accent: RadarColorToken, soft: RadarColorToken) -> some View {
        modifier(RadarAccentCardModifier(accent: accent, soft: soft))
    }
    /// Capsule badge. Whitelist (spec §7): announcement-banner status words,
    /// model effort-suffix labels, quota_check limit/plan tags.
    func radarPill(accent: RadarColorToken, soft: RadarColorToken) -> some View {
        modifier(RadarPillModifier(accent: accent, soft: soft))
    }
}

struct RadarGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: RadarStyle.cardSpacing) {
            configuration.label.font(.headline)
            configuration.content
        }
        .radarPanel()
    }
}

struct ViewHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    let title: String
    let subtitle: String

    private var palette: RadarPalette {
        RadarStyle.palette(for: colorScheme, contrast: contrast)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(palette.primaryText.color)
            Text(subtitle)
                .foregroundStyle(palette.secondaryText.color)
                .textSelection(.enabled)
        }
    }
}

struct StateBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    let state: WorkspaceState
    let error: String?
    let sourceName: String

    private var palette: RadarPalette {
        RadarStyle.palette(for: colorScheme, contrast: contrast)
    }

    init(state: WorkspaceState, error: String?, sourceName: String = "Claude Code Radar") {
        self.state = state
        self.error = error
        self.sourceName = sourceName
    }

    var body: some View {
        Label(Self.message(for: state, error: error, sourceName: sourceName), systemImage: icon)
            .foregroundStyle(stateColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(palette.section.color, in: .rect(cornerRadius: RadarStyle.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: RadarStyle.cornerRadius)
                    .stroke(palette.divider.color)
            }
    }

    static func message(
        for state: WorkspaceState,
        error: String?,
        sourceName: String = "Claude Code Radar"
    ) -> String {
        switch state {
        case .loading: "正在载入 \(sourceName) 数据"
        case .empty: "当前没有可显示的数据"
        case .fresh: "刚刚同步成功"
        case .stale: "正在使用最后良好数据；数据可能已过期"
        case .usingLastKnownGood: error.map { "正在使用最近一次良好数据\n\($0)" } ?? "正在使用最近一次良好数据"
        case .validationFailed(let hasLastKnownGood):
            error ?? (hasLastKnownGood ? "新数据未通过校验，已保留旧值" : "新数据未通过校验，暂无可用旧值")
        case .unavailable(let text), .disabled(let text), .error(let text): text
        }
    }

    private var icon: String {
        switch state {
        case .fresh: "checkmark.circle"
        case .loading: "arrow.triangle.2.circlepath"
        case .empty: "tray"
        case .stale: "clock.badge.exclamationmark"
        case .usingLastKnownGood, .validationFailed, .error: "exclamationmark.triangle"
        case .unavailable: "questionmark.circle"
        case .disabled: "lock.shield"
        }
    }

    private var stateColor: Color {
        switch state {
        case .fresh: palette.positive.color
        case .validationFailed, .error: palette.negative.color
        default: palette.secondaryText.color
        }
    }
}
