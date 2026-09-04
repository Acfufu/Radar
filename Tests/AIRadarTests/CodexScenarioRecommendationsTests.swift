import Foundation
import Testing
@testable import AIRadar

@Suite("CodexScenarioRecommendationsTests")
struct CodexScenarioRecommendationsTests {
    @Test("the four scenario rules use their stated threshold semantics")
    func thresholdEdgesAndRules() {
        let projected = CodexScenarioRecommendations.project(points: [
            point("edge-54.9", quality: 54.9, averageCost: 9, averageMinutes: 9, combinedCost: 0.1),
            point("edge-55", quality: 55, averageCost: 8, averageMinutes: 8, combinedCost: 5),
            point("edge-84.9", quality: 84.9, averageCost: 1, averageMinutes: 7, combinedCost: 6),
            point("edge-85", quality: 85, averageCost: 0.5, averageMinutes: 6, combinedCost: 4),
            point("edge-89.5", quality: 89.5, averageCost: 0.8, averageMinutes: 5, combinedCost: 7),
            point("edge-95.4", quality: 95.4, averageCost: 0.4, averageMinutes: 4, combinedCost: 2),
            point("edge-95.5", quality: 95.5, averageCost: 0.6, averageMinutes: 3, combinedCost: 3),
        ])

        #expect(projected.groups.map(\.scenario) == CodexScenario.allCases)
        #expect(ids(projected, .dailyDevelopment) == ["edge-95.4", "edge-95.5"])
        #expect(ids(projected, .difficultTasks) == ["edge-95.5", "edge-95.4"])
        #expect(ids(projected, .backgroundAutomation) == ["edge-95.4", "edge-85"])
        #expect(ids(projected, .lobsterTasks) == ["edge-95.4", "edge-95.5"])
        #expect(!ids(projected, .lobsterTasks).contains("edge-54.9"))
        #expect(projected.groups.allSatisfy { $0.provenance.contains("Radar") && $0.provenance.contains("非官网") })
        #expect(projected.groups.allSatisfy { !$0.rule.isEmpty && !$0.rationale.isEmpty })
    }

    @Test("ties deduplicate deterministically and do not depend on input order")
    func stableTiesDuplicatesAndShuffle() {
        let points = [
            point("daily-beta", quality: 92, averageCost: 5, averageMinutes: 5, combinedCost: 2),
            point("daily-alpha", quality: 92, averageCost: 5, averageMinutes: 5, combinedCost: 2),
            point("daily-high", quality: 96, averageCost: 8, averageMinutes: 8, combinedCost: 3),
            point("hard-expensive", quality: 99, averageCost: 4, averageMinutes: 4, combinedCost: 8),
            point("hard-cheap", quality: 99, averageCost: 4, averageMinutes: 4, combinedCost: 1),
            point("automation-slow", quality: 86, averageCost: 1, averageMinutes: 9, combinedCost: 3),
            point("automation-fast", quality: 86, averageCost: 1, averageMinutes: 4, combinedCost: 4),
            point("lobster-low", quality: 56, averageCost: 7, averageMinutes: 7, combinedCost: 0.5),
            point("lobster-high", quality: 70, averageCost: 7, averageMinutes: 7, combinedCost: 0.5),
        ]
        let duplicate = point("lobster-high", quality: 70, averageCost: 7, averageMinutes: 7, combinedCost: 0.5)
        let first = CodexScenarioRecommendations.project(points: points + [duplicate])
        let shuffled = CodexScenarioRecommendations.project(points: [
            duplicate, points[7], points[1], points[5], points[4], points[0], points[8], points[6], points[3], points[2],
        ])

        #expect(first == shuffled)
        #expect(ids(first, .dailyDevelopment) == ["daily-alpha", "hard-cheap"])
        #expect(ids(first, .difficultTasks) == ["hard-cheap", "hard-expensive"])
        #expect(ids(first, .backgroundAutomation) == ["automation-fast", "automation-slow"])
        #expect(ids(first, .lobsterTasks) == ["lobster-high", "lobster-low"])
        #expect(ids(first, .lobsterTasks).filter { $0 == "lobster-high" }.count == 1)
    }

    @Test("non-finite or absent inputs never fabricate a recommendation")
    func malformedAndInsufficientCandidates() {
        let missing: IntelligenceEfficiencyPoint? = nil
        let finite = point("finite", quality: 90, averageCost: 1, averageMinutes: 1, combinedCost: 1)
        let costNaN = point("cost-nan", quality: 97, averageCost: .nan, averageMinutes: 1, combinedCost: 1)
        let combinedInfinity = point("combined-infinity", quality: 97, averageCost: 1, averageMinutes: 1, combinedCost: .infinity)
        let qualityNaN = point("quality-nan", quality: .nan, averageCost: 1, averageMinutes: 1, combinedCost: 1)
        let foreign = point("foreign", quality: 100, averageCost: 0.1, averageMinutes: 1, combinedCost: 0.1, sourceID: .claudeCodeRadar)
        let projected = CodexScenarioRecommendations.project(points: [missing, finite, costNaN, combinedInfinity, qualityNaN, foreign].compactMap { $0 })

        #expect(ids(projected, .dailyDevelopment) == ["finite", "cost-nan"])
        #expect(ids(projected, .difficultTasks) == ["cost-nan", "finite"])
        #expect(ids(projected, .backgroundAutomation) == ["combined-infinity", "finite"])
        #expect(ids(projected, .lobsterTasks) == ["cost-nan", "finite"])
        #expect(projected.groups.flatMap(\.recommendations).allSatisfy { $0.id.upstreamKey != "foreign" && $0.id.upstreamKey != "quality-nan" })

        let oneCandidate = CodexScenarioRecommendations.project(points: [finite])
        #expect(oneCandidate.groups.allSatisfy { $0.recommendations.map(\.id.upstreamKey) == ["finite"] })
    }

    @Test("qaReceipt")
    func qaReceipt() {
        let projected = CodexScenarioRecommendations.project(points: [
            point("daily-mid", quality: 92, averageCost: 3, averageMinutes: 4, combinedCost: 2),
            point("daily-high", quality: 97, averageCost: 4, averageMinutes: 5, combinedCost: 3),
            point("hard-best", quality: 100, averageCost: 9, averageMinutes: 8, combinedCost: 9),
            point("auto-low", quality: 86, averageCost: 0.5, averageMinutes: 2, combinedCost: 4),
            point("lobster-low", quality: 55, averageCost: 2, averageMinutes: 6, combinedCost: 1),
        ])
        let receipt = projected.groups.map { group in
            "\(group.scenario.rawValue):\(group.recommendations.count):\(group.recommendations.map(\.id.upstreamKey).joined(separator: ","))"
        }
        if ProcessInfo.processInfo.environment["RADAR_QA_RECEIPT"] == "1" {
            print("RADAR_QA_RECEIPT \(receipt.joined(separator: " | "))")
        }
        #expect(receipt == [
            "dailyDevelopment:2:daily-mid,daily-high",
            "difficultTasks:2:hard-best,daily-high",
            "backgroundAutomation:2:auto-low,daily-mid",
            "lobsterTasks:2:lobster-low,daily-mid",
        ])
    }

    private func ids(_ projected: CodexScenarioRecommendations, _ scenario: CodexScenario) -> [String] {
        projected.groups.first { $0.scenario == scenario }!.recommendations.map(\.id.upstreamKey)
    }

    private func point(
        _ key: String,
        quality: Double,
        averageCost: Double,
        averageMinutes: Double,
        combinedCost: Double,
        sourceID: RadarSourceID = .codexRadar
    ) -> IntelligenceEfficiencyPoint {
        let id = ModelID(sourceID: sourceID, upstreamKey: key)
        return .init(
            id: id,
            modelName: key,
            quality: quality,
            averageCostUSD: averageCost,
            averageMinutes: averageMinutes,
            rawCombinedCost: combinedCost,
            combinedCostIndex: combinedCost
        )
    }
}
