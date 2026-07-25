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

    @Test("brand accent never replaces semantic success or error")
    func statusRolesRemainDistinct() {
        for scheme in [ColorScheme.light, .dark] {
            let palette = RadarStyle.palette(for: scheme)
            #expect(palette.accent != palette.positive)
            #expect(palette.accent != palette.negative)
            #expect(palette.positive != palette.negative)
        }
    }
}
