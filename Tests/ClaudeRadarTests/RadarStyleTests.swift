import SwiftUI
import Testing
@testable import ClaudeRadar

@Suite("RadarStyleTests")
struct RadarStyleTests {
    @Test("frozen light and dark semantic roles remain exact")
    func frozenPalettes() {
        let light = RadarStyle.palette(for: .light)
        #expect(light.canvas == .rgb(0xEEF0F2))
        #expect(light.section == .rgb(0xFAF9F7))
        #expect(light.card == .rgb(0xFFFFFF))
        #expect(light.primaryText == .rgb(0x1F2328))
        #expect(light.secondaryText == .rgb(0x6B7280))
        #expect(light.divider == .rgb(0xE7E5E0))
        #expect(light.accent == .rgb(0xD97706))
        #expect(light.accentSoft == .rgb(0xFFFBEB))
        #expect(light.accentBorder == .rgb(0xFDE68A))
        #expect(light.positive == .rgb(0x166534))
        #expect(light.negative == .rgb(0xE11D48))
        #expect(light.shadow == .init(opacity: 0.06, radius: 3, y: 1))

        let dark = RadarStyle.palette(for: .dark)
        #expect(dark.canvas == .rgb(0x0B111A))
        #expect(dark.section == .rgb(0x111827))
        #expect(dark.card == .rgb(0x172033))
        #expect(dark.primaryText == .rgb(0xE5EDF7))
        #expect(dark.secondaryText == .rgb(0xA7B2C3))
        #expect(dark.divider == .rgb(0x293548))
        #expect(dark.accent == .rgb(0xFBBF24))
        #expect(dark.accentSoft == .rgb(0xFBBF24, opacity: 0.12))
        #expect(dark.accentBorder == .rgb(0xFBBF24, opacity: 0.28))
        #expect(dark.positive == .rgb(0x86EFAC))
        #expect(dark.negative == .rgb(0xFB7185))
        #expect(dark.shadow == .init(opacity: 0.28, radius: 32, y: 12))
    }

    @Test("geometry and increased contrast strengthen boundaries without changing layout")
    func geometryAndContrast() {
        #expect(RadarStyle.cornerRadius == 8)
        #expect(RadarStyle.pageSpacing == 24)
        #expect(RadarStyle.sectionSpacing == 20)
        #expect(RadarStyle.cardSpacing == 14)
        #expect(RadarStyle.compactSpacing == 12)

        for scheme in [ColorScheme.light, .dark] {
            let standard = RadarStyle.palette(for: scheme, contrast: .standard)
            let increased = RadarStyle.palette(for: scheme, contrast: .increased)
            #expect(increased.divider != standard.divider)
            #expect(increased.accentBorder != standard.accentBorder)
            if scheme == .dark {
                #expect(increased.accentBorder.opacity > standard.accentBorder.opacity)
            }
            #expect(increased.canvas == standard.canvas)
            #expect(increased.card == standard.card)
        }
    }

    @Test("shared chart metrics keep layout stable while increasing mark emphasis")
    func sharedChartMetrics() {
        let standard = RadarStyle.chartMetrics(for: .standard)
        let increased = RadarStyle.chartMetrics(for: .increased)

        #expect(standard.minimumCardWidth == increased.minimumCardWidth)
        #expect(standard.minimumHeight == increased.minimumHeight)
        #expect(standard.minimumCardWidth > standard.minimumHeight)
        #expect(increased.lineWidth > standard.lineWidth)
        #expect(increased.symbolSize > standard.symbolSize)
    }

    @Test("horizontal overflow affordance is concise localized and native")
    func horizontalOverflowAffordance() {
        let affordance = RadarStyle.horizontalScrollAffordance

        #expect(affordance.title == "横向滚动查看更多")
        #expect(affordance.systemImage == "arrow.left.and.right")
        #expect(affordance.title.count <= 9)
    }

    @Test("analytics layout and family colors are centralized semantic tokens")
    func analyticsVisualTokens() {
        let layout = RadarStyle.analyticsLayout

        #expect(layout.matrixFamilyColumnWidth == 104)
        #expect(layout.matrixCellWidth == 216)
        #expect(layout.matrixRowHeight == 112)
        #expect(layout.comparisonMetricPickerMaximumWidth == 260)
        #expect(layout.comparisonBaselinePickerWidth == 130)
        #expect(layout.comparisonColumnSpacing == 18)

        let light = RadarStyle.analyticsColors(for: .light)
        let dark = RadarStyle.analyticsColors(for: .dark)
        #expect(light.familyColors == [
            .rgb(0x15803D),
            .rgb(0x7E22CE),
            .rgb(0xC2410C),
            .rgb(0x1D4ED8),
            .rgb(0x0F766E),
        ])
        #expect(dark.familyColors == [
            .rgb(0x4ADE80),
            .rgb(0xC084FC),
            .rgb(0xFB923C),
            .rgb(0x60A5FA),
            .rgb(0x2DD4BF),
        ])
    }

    @Test("brand accent never replaces semantic success or error")
    func statusRolesRemainDistinct() {
        for scheme in [ColorScheme.light, .dark] {
            let palette = RadarStyle.palette(for: scheme)
            #expect(palette.accent != palette.positive)
            #expect(palette.accent != palette.negative)
            #expect(palette.positive != palette.negative)
        }
    }

    @Test("shared chart descriptor preserves axes units series and point labels")
    func chartDescriptorContract() {
        let descriptor = RadarChartDescriptor(
            title: "来源趋势",
            summary: "来源上下文",
            xAxisTitle: "时间",
            yAxisTitle: "成本（USD）",
            xValueDescription: RadarChartDescriptor.dateTime,
            yValueDescription: { RadarChartDescriptor.number($0, unit: "USD") },
            series: [
                .init(
                    name: "模型 · r1",
                    isContinuous: true,
                    points: [.init(x: 1, y: 2.5, label: "模型，成本 2.5 USD")]
                ),
            ]
        ).makeChartDescriptor()

        #expect(descriptor.title == "来源趋势")
        #expect(descriptor.summary == "来源上下文")
        #expect(descriptor.xAxis.title == "时间")
        #expect(descriptor.yAxis?.title == "成本（USD）")
        #expect(descriptor.yAxis?.valueDescriptionProvider(2.5) == "2.5 USD")
        #expect(descriptor.series.first?.name == "模型 · r1")
        #expect(descriptor.series.first?.dataPoints.first?.label == "模型，成本 2.5 USD")
    }
}
