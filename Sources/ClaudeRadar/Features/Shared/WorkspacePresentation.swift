import Foundation

struct WorkspaceMetricPresentation: Equatable, Sendable {
    let qualityLabel: String
    let qualityUnit: String
    let unavailableValue: String
    let accessibilityLabel: String

    func formattedQuality(_ value: Decimal?) -> String {
        guard value != nil else { return unavailableValue }
        return RadarFormat.decimal(value, suffix: qualityUnit)
    }

    func accessibilityValue(_ value: Decimal?) -> String {
        "\(accessibilityLabel)：\(formattedQuality(value))"
    }

    func title(for metric: TrendMetric) -> String {
        metric == .quality ? qualityLabel : metric.rawValue
    }
}

enum WorkspacePresentation {
    static func metric(for sourceID: RadarSourceID) -> WorkspaceMetricPresentation {
        switch sourceID {
        case .sweBenchVerified:
            .init(
                qualityLabel: "% Resolved",
                qualityUnit: "%",
                unavailableValue: "未发布",
                accessibilityLabel: "已解决比例 % Resolved"
            )
        default:
            .init(
                qualityLabel: "IQ",
                qualityUnit: "",
                unavailableValue: "未发布",
                accessibilityLabel: "质量 IQ"
            )
        }
    }

    static func benchmark(for projection: WorkspaceProjection) -> BenchmarkPresentation {
        projection.benchmarkPresentation
    }

    @MainActor
    static func bannerMessage(for state: WorkspaceState, error: String?, sourceName: String = "Claude Code Radar") -> String {
        StateBanner.message(for: state, error: error, sourceName: sourceName)
    }

    static func stateText(for state: WorkspaceState?) -> String {
        switch state {
        case .fresh: "正常"
        case .stale: "陈旧"
        case .usingLastKnownGood: "LKG"
        case .validationFailed(let hasLastKnownGood): hasLastKnownGood ? "校验失败 · LKG" : "校验失败"
        case .loading: "载入中"
        case .empty, nil: "暂无数据"
        case .disabled: "在线读取关闭"
        case .unavailable, .error: "不可用"
        }
    }

    static func stateIcon(for state: WorkspaceState?) -> String {
        switch state {
        case .fresh: "checkmark.circle.fill"
        case .stale, .usingLastKnownGood, .validationFailed: "clock.arrow.circlepath"
        case .loading: "arrow.triangle.2.circlepath"
        case .empty, nil: "circle.dashed"
        case .disabled: "pause.circle"
        case .unavailable, .error: "exclamationmark.triangle"
        }
    }
}
