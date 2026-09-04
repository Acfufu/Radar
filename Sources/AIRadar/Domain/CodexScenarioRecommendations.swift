import Foundation

enum CodexScenario: String, CaseIterable, Identifiable, Sendable {
    case dailyDevelopment
    case difficultTasks
    case backgroundAutomation
    case lobsterTasks

    var id: Self { self }

    var title: String {
        switch self {
        case .dailyDevelopment: "日常开发"
        case .difficultTasks: "困难任务"
        case .backgroundAutomation: "后台自动化"
        case .lobsterTasks: "龙虾类任务"
        }
    }

    var rule: String {
        switch self {
        case .dailyDevelopment: "圆整 IQ 90–95 与 ≥96 各取综合成本最低的 1 个"
        case .difficultTasks: "按 IQ 最高取前 2 个"
        case .backgroundAutomation: "圆整 IQ ≥85，按平均成本最低取前 2 个"
        case .lobsterTasks: "IQ ≥55，按综合成本最低取前 2 个"
        }
    }

    var rationale: String {
        switch self {
        case .dailyDevelopment: "同综合成本时优先 IQ 更高，再按模型键升序。"
        case .difficultTasks: "同 IQ 时优先综合成本更低，再按模型键升序。"
        case .backgroundAutomation: "同平均成本时优先平均耗时更短，再按模型键升序。"
        case .lobsterTasks: "同综合成本时优先 IQ 更高，再按模型键升序。"
        }
    }
}

struct CodexScenarioRecommendationGroup: Identifiable, Equatable, Sendable {
    let scenario: CodexScenario
    let recommendations: [IntelligenceEfficiencyPoint]

    var id: CodexScenario { scenario }
    var rule: String { scenario.rule }
    var rationale: String { scenario.rationale }
    var provenance: String { "Radar 本地派生，基于当前公开摘要；非官网推荐。" }
}

struct CodexScenarioRecommendations: Equatable, Sendable {
    let groups: [CodexScenarioRecommendationGroup]

    static func project(points: [IntelligenceEfficiencyPoint]) -> Self {
        let points = deduplicated(points.filter { $0.id.sourceID == .codexRadar })
        return .init(groups: CodexScenario.allCases.map { scenario in
            .init(scenario: scenario, recommendations: recommendations(for: scenario, from: points))
        })
    }

    private static func recommendations(
        for scenario: CodexScenario,
        from points: [IntelligenceEfficiencyPoint]
    ) -> [IntelligenceEfficiencyPoint] {
        switch scenario {
        case .dailyDevelopment:
            let eligible = points.filter { isFinite($0.quality, $0.combinedCostIndex) }
            return [
                eligible.filter { (90...95).contains(roundedIQ($0.quality)) }.sorted(by: combinedCostOrder).first,
                eligible.filter { roundedIQ($0.quality) >= 96 }.sorted(by: combinedCostOrder).first,
            ].compactMap { $0 }
        case .difficultTasks:
            return points
                .filter { isFinite($0.quality, $0.combinedCostIndex) }
                .sorted(by: difficultTaskOrder)
                .prefix(2)
                .map { $0 }
        case .backgroundAutomation:
            return points
                .filter { isFinite($0.quality, $0.averageCostUSD, $0.averageMinutes) && roundedIQ($0.quality) >= 85 }
                .sorted(by: automationOrder)
                .prefix(2)
                .map { $0 }
        case .lobsterTasks:
            return points
                .filter { $0.quality >= 55 && isFinite($0.quality, $0.combinedCostIndex) }
                .sorted(by: combinedCostOrder)
                .prefix(2)
                .map { $0 }
        }
    }

    private static func roundedIQ(_ quality: Double) -> Int {
        Int(quality.rounded(.toNearestOrAwayFromZero))
    }

    private static func isFinite(_ values: Double...) -> Bool {
        values.allSatisfy(\.isFinite)
    }

    private static func combinedCostOrder(_ lhs: IntelligenceEfficiencyPoint, _ rhs: IntelligenceEfficiencyPoint) -> Bool {
        if lhs.combinedCostIndex != rhs.combinedCostIndex { return lhs.combinedCostIndex < rhs.combinedCostIndex }
        if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
        return lhs.id.upstreamKey < rhs.id.upstreamKey
    }

    private static func difficultTaskOrder(_ lhs: IntelligenceEfficiencyPoint, _ rhs: IntelligenceEfficiencyPoint) -> Bool {
        if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
        if lhs.combinedCostIndex != rhs.combinedCostIndex { return lhs.combinedCostIndex < rhs.combinedCostIndex }
        return lhs.id.upstreamKey < rhs.id.upstreamKey
    }

    private static func automationOrder(_ lhs: IntelligenceEfficiencyPoint, _ rhs: IntelligenceEfficiencyPoint) -> Bool {
        if lhs.averageCostUSD != rhs.averageCostUSD { return lhs.averageCostUSD < rhs.averageCostUSD }
        if lhs.averageMinutes != rhs.averageMinutes { return lhs.averageMinutes < rhs.averageMinutes }
        return lhs.id.upstreamKey < rhs.id.upstreamKey
    }

    private static func deduplicated(_ points: [IntelligenceEfficiencyPoint]) -> [IntelligenceEfficiencyPoint] {
        Dictionary(grouping: points, by: \.id).values.compactMap { duplicates in
            duplicates.min(by: canonicalOrder)
        }
    }

    private static func canonicalOrder(_ lhs: IntelligenceEfficiencyPoint, _ rhs: IntelligenceEfficiencyPoint) -> Bool {
        for (left, right) in zip(canonicalKey(lhs), canonicalKey(rhs)) where left != right {
            return left < right
        }
        return false
    }

    private static func canonicalKey(_ point: IntelligenceEfficiencyPoint) -> [String] {
        [
            point.id.upstreamKey,
            point.modelName,
            String(point.quality.bitPattern),
            String(point.averageCostUSD.bitPattern),
            String(point.averageMinutes.bitPattern),
            String(point.rawCombinedCost.bitPattern),
            String(point.combinedCostIndex.bitPattern),
        ]
    }
}
