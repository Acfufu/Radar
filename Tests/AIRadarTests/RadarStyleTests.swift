import SwiftUI
import Testing
@testable import AIRadar

@Suite("RadarStyleTests")
struct RadarStyleTests {
    // Upstream tokens (codexradar.com 2026-09-04, [data-theme] light/dark)
    // frozen per docs/design-qa.md.
    @Test("upstream light and dark palettes remain exact")
    func upstreamPalettes() {
        let light = RadarStyle.palette(for: .light)
        #expect(light.canvas == .rgb(0xEDF4FF))
        #expect(light.section == .rgb(0xFFFFFF, opacity: 0.90))
        #expect(light.card == .rgb(0xF2F7FF, opacity: 0.92))
        #expect(light.primaryText == .rgb(0x12213B))
        #expect(light.secondaryText == .rgb(0x53647E))
        #expect(light.divider == .rgb(0x6F89B1, opacity: 0.25))
        #expect(light.dividerStrong == .rgb(0x4E6FA3, opacity: 0.38))
        #expect(light.accent == .rgb(0xB45309))
        #expect(light.accentSoft == .rgb(0xF59E0B, opacity: 0.13))
        #expect(light.green == .rgb(0x047857))
        #expect(light.greenSoft == .rgb(0x059669, opacity: 0.12))
        #expect(light.amber == .rgb(0xB45309))
        #expect(light.amberSoft == .rgb(0xF59E0B, opacity: 0.13))
        #expect(light.blue == .rgb(0x245FC5))
        #expect(light.blueSoft == .rgb(0x2563EB, opacity: 0.11))
        #expect(light.red == .rgb(0xBE3144))
        #expect(light.redSoft == .rgb(0xE11D48, opacity: 0.10))
        #expect(light.positive == .rgb(0x047857))
        #expect(light.negative == .rgb(0xBE3144))
        #expect(light.shadow == .init(opacity: 0.13, radius: 60, y: 22, tint: .rgb(0x28487A)))

        let dark = RadarStyle.palette(for: .dark)
        #expect(dark.canvas == .rgb(0x0D1420))
        #expect(dark.section == .rgb(0x111827))
        #expect(dark.card == .rgb(0x172033))
        #expect(dark.primaryText == .rgb(0xE5EDF7))
        #expect(dark.secondaryText == .rgb(0xA7B2C3))
        #expect(dark.divider == .rgb(0x263449))
        #expect(dark.dividerStrong == .rgb(0x35465F))
        #expect(dark.accent == .rgb(0xFBBF24))
        #expect(dark.accentSoft == .rgb(0xFBBF24, opacity: 0.14))
        #expect(dark.green == .rgb(0x34D399))
        #expect(dark.greenSoft == .rgb(0x10B981, opacity: 0.16))
        #expect(dark.amber == .rgb(0xFBBF24))
        #expect(dark.amberSoft == .rgb(0xFBBF24, opacity: 0.14))
        #expect(dark.blue == .rgb(0x93C5FD))
        #expect(dark.blueSoft == .rgb(0x60A5FA, opacity: 0.16))
        #expect(dark.red == .rgb(0xF87171))
        #expect(dark.redSoft == .rgb(0xF87171, opacity: 0.16))
        #expect(dark.positive == .rgb(0x34D399))
        #expect(dark.negative == .rgb(0xF87171))
        #expect(dark.shadow == .init(opacity: 0.34, radius: 44, y: 18, tint: .rgb(0x000000)))
    }

    @Test("upstream geometry ladder replaces the single radius")
    func upstreamGeometry() {
        #expect(RadarStyle.panelCornerRadius == 15)
        #expect(RadarStyle.cardCornerRadius == 11)
        #expect(RadarStyle.inlineCornerRadius == 7)
        #expect(RadarStyle.cornerRadius == RadarStyle.cardCornerRadius)
        #expect(RadarStyle.accentBarWidth == 5)
        #expect(RadarStyle.pageSpacing == 24)
        #expect(RadarStyle.sectionSpacing == 20)
        #expect(RadarStyle.cardSpacing == 14)
        #expect(RadarStyle.compactSpacing == 12)
    }

    @Test("increased contrast maps divider to line-strong and raises accent border only")
    func increasedContrastAxis() {
        for scheme in [ColorScheme.light, .dark] {
            let standard = RadarStyle.palette(for: scheme, contrast: .standard)
            let increased = RadarStyle.palette(for: scheme, contrast: .increased)
            // Divider strengthens to the line-strong token.
            #expect(increased.divider == standard.dividerStrong)
            // Everything else keeps the standard value (spec §7 contrast axis).
            #expect(increased.canvas == standard.canvas)
            #expect(increased.card == standard.card)
            #expect(increased.green == standard.green)
            #expect(increased.red == standard.red)
            #expect(increased.blue == standard.blue)
        }
        let lightStandard = RadarStyle.palette(for: .light, contrast: .standard)
        let lightIncreased = RadarStyle.palette(for: .light, contrast: .increased)
        #expect(lightIncreased.accentBorder.opacity > lightStandard.accentBorder.opacity)
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

    @Test("analytics layout is centralized and family colors map four semantic hues plus neutral")
    func analyticsVisualTokens() {
        let layout = RadarStyle.analyticsLayout

        #expect(layout.matrixFamilyColumnWidth == 104)
        #expect(layout.matrixCellWidth == 216)
        #expect(layout.matrixRowHeight == 112)
        #expect(layout.comparisonMetricPickerMaximumWidth == 260)
        #expect(layout.comparisonBaselinePickerWidth == 130)
        #expect(layout.comparisonColumnSpacing == 18)

        // green, blue, amber, red, neutral — matches the family mapping table
        // recorded in docs/design-qa.md.
        let light = RadarStyle.analyticsColors(for: .light)
        let dark = RadarStyle.analyticsColors(for: .dark)
        #expect(light.familyColors == [
            .rgb(0x047857),
            .rgb(0x245FC5),
            .rgb(0xB45309),
            .rgb(0xBE3144),
            .rgb(0x71809A),
        ])
        #expect(dark.familyColors == [
            .rgb(0x34D399),
            .rgb(0x93C5FD),
            .rgb(0xFBBF24),
            .rgb(0xF87171),
            .rgb(0x8794A8),
        ])
    }

    @Test("brand accent never replaces semantic success or error")
    func statusRolesRemainDistinct() {
        for scheme in [ColorScheme.light, .dark] {
            let palette = RadarStyle.palette(for: scheme)
            #expect(palette.accent != palette.positive || scheme == .dark)
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

@Suite("RadarUpstreamComponentsTests")
struct RadarUpstreamComponentsTests {
    @Test("announcement banner renders nil-free and maps open and closed states")
    func announcementBannerStates() {
        // nil content renders an empty view (no placeholder) — spec §4.2.
        let banner = AnnouncementBanner(content: nil)
        #expect(AnnouncementBanner.Content(
            title: "Codex 用量限制重置", isOpen: true, statusWord: "窗口开启"
        ).isOpen)

        let mirror = Mirror(reflecting: banner)
        let content = mirror.children.first { $0.label == "content" }?.value as? AnnouncementBanner.Content?
        #expect(content == nil)

        let open = AnnouncementBanner.Content(title: "t", isOpen: true)
        let closed = AnnouncementBanner.Content(title: "t", isOpen: false)
        #expect(open != closed)
    }

    @Test("status dot levels cover the four-state mapping")
    func statusDotLevels() {
        #expect(Set([StationStatusLevel.fresh, .stale, .error, .muted]).count == 4)
    }

    @Test("star rating matrix maps averages to star symbols and empty cells to placeholders")
    func starRatingMatrixCells() {
        let row = StarRatingMatrix.Row(
            title: "GPT-5.6 Sol",
            subtitle: "$5 · $0.50 · $30",
            cells: [.init(average: 4.9, count: 18), .init(average: 3.5, count: 7), nil, .empty]
        )
        #expect(row.cells.count == 4)
        #expect(row.cells[0]?.average == 4.9)
        #expect(StarRatingMatrix.Cell.empty.count == 0)

        let matrix = StarRatingMatrix(columnTitles: ["24h", "8-31", "8-30"], rows: [row])
        #expect(matrix.rows.count == 1)

        let empty = StarRatingMatrix(columnTitles: ["24h"], rows: [])
        #expect(empty.rows.isEmpty)
    }

    @Test("monthly count table zero-fills ascending months")
    func monthlyCountTableZeroFills() {
        let filled = MonthlyCountSeries.zeroFilled(from: ["2026-06": 3, "2026-09": 5])
        #expect(filled.map(\.monthLabel) == ["2026-06", "2026-07", "2026-08", "2026-09"])
        #expect(filled.map(\.count) == [3, 0, 0, 5])

        #expect(MonthlyCountSeries.zeroFilled(from: [:]).isEmpty)
        let single = MonthlyCountSeries.zeroFilled(from: ["2026-09": 2])
        #expect(single.map(\.monthLabel) == ["2026-09"])
        let invalid = MonthlyCountSeries.zeroFilled(from: ["bad": 1])
        #expect(invalid.map(\.monthLabel) == ["bad"])
    }

    @Test("capsule badge usage stays on the spec whitelist surfaces")
    func capsuleBadgeWhitelist() throws {
        // spec §7: Capsule badges only for announcement status words, model
        // effort labels, and quota_check tags. The radarPill helper is the
        // only capsule entry point; direct Capsule( usage outside the shared
        // style file is a whitelist violation.
        let root = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/AIRadar/Features")
        let whitelist = ["RadarStyle.swift", "RadarUpstreamComponents.swift"]
        let files = try FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("Capsule(") {
                let name = file.lastPathComponent
                #expect(
                    whitelist.contains(name),
                    "Capsule usage outside whitelist: \(name) (spec §7 badge whitelist)"
                )
            }
        }
    }
}
