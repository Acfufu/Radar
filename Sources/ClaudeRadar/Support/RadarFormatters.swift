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
}
