import Foundation

enum RadarFormat {
    static func decimal(_ value: Decimal?, suffix: String = "") -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...2))) + suffix
    }
    static func derived(_ value: DerivedMetricValue) -> String {
        switch value {
        case .decimal(let decimal): decimal.description
        case .unavailable(let reason): reason.explanation
        }
    }
    static func integer<T: BinaryInteger>(_ value: T?) -> String {
        value.map { $0.formatted() } ?? "—"
    }
    static func seconds(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(0...2))) + " s" } ?? "—"
    }
    static func date(_ value: Date?) -> String {
        value?.formatted(date: .abbreviated, time: .shortened) ?? "无可用时间"
    }

    /// Relative age ("8天前"/"8 days ago") for data-age annotations
    /// (spec §4.2 v1.3 note). Locale-driven; never invented locally. Clamps
    /// slightly into the past so a future/fresh-now timestamp (seed skew,
    /// clock drift, zero interval) never reads as "X 后".
    static func relativeTime(_ value: Date, now: Date = Date()) -> String {
        RelativeDateTimeFormatter()
            .localizedString(for: min(value, now.addingTimeInterval(-1)), relativeTo: now)
    }

    /// Tolerant upstream ISO-8601 parse: current.json carries fractional
    /// seconds ("…T13:05:52.704532+08:00") while other fields do not.
    static func parseUpstreamTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
