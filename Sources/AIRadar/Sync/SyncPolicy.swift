import Foundation

protocol RadarClock: Sendable {
    func now() -> Date
}

struct SystemRadarClock: RadarClock {
    func now() -> Date { Date() }
}

struct SyncPolicy: Sendable {
    let refreshInterval: TimeInterval
    let recoveryMinimumInterval: TimeInterval
    let maximumBackoff: TimeInterval

    init(
        refreshInterval: TimeInterval = 30 * 60,
        recoveryMinimumInterval: TimeInterval = 60,
        maximumBackoff: TimeInterval = 6 * 60 * 60
    ) {
        self.refreshInterval = refreshInterval
        self.recoveryMinimumInterval = recoveryMinimumInterval
        self.maximumBackoff = maximumBackoff
    }

    var staleInterval: TimeInterval { max(2 * refreshInterval, 60 * 60) }

    func backoff(failureCount: Int) -> TimeInterval {
        let schedule: [TimeInterval] = [60, 5 * 60, 15 * 60, 30 * 60, 2 * 60 * 60, 6 * 60 * 60]
        return schedule[min(max(failureCount - 1, 0), schedule.count - 1)]
    }
}

enum SyncTrigger: Sendable {
    case startup
    case manual
    case periodic
    case networkRecovery
    case sleepRecovery
}

extension SyncTrigger {
    var isManual: Bool {
        if case .manual = self { return true }
        return false
    }

    var priority: Int {
        switch self {
        case .manual: 3
        case .startup: 2
        case .networkRecovery, .sleepRecovery: 1
        case .periodic: 0
        }
    }
}
