import Foundation
import Observation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "跟随系统"
    case light = "亮色"
    case dark = "暗色"

    var id: Self { self }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var refreshIntervalMinutes: Int {
        get { defaults.integer(forKey: "refreshIntervalMinutes").nonzero ?? 30 }
        set { defaults.set(Self.allowedIntervals.contains(newValue) ? newValue : 30, forKey: "refreshIntervalMinutes") }
    }
    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }
    var appearance: AppAppearance {
        get { AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "appearance") }
    }
    private(set) var publicOnlineAccessEnabled = false
    static let allowedIntervals = [15, 30, 60, 120]
}

private extension Int {
    var nonzero: Int? { self == 0 ? nil : self }
}
