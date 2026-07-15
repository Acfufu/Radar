import Foundation
import Observation

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
    private(set) var publicOnlineAccessEnabled = false
    static let allowedIntervals = [15, 30, 60, 120]
}

private extension Int {
    var nonzero: Int? { self == 0 ? nil : self }
}
