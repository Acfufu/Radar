import Foundation
import Testing
@testable import ClaudeRadar

@Suite("CodexEfficiencyAnalyticsTests")
struct CodexEfficiencyAnalyticsTests {
    @Test("identity extracts canonical families and efforts with display-name fallback")
    func identity() {
        #expect(RadarModelIdentity.family(id: id("gpt-5.3-codex-sol-ultra"), displayName: "Codex Sol Ultra") == "Sol")
        #expect(RadarModelIdentity.effort(id: id("gpt-5.3-codex-sol-ultra"), displayName: "Codex Sol Ultra") == "ultra")
        #expect(RadarModelIdentity.family(id: id("mystery-model"), displayName: "Nebula Prime high") == "Nebula Prime")
        #expect(RadarModelIdentity.effort(id: id("mystery-model"), displayName: "Nebula Prime high") == "high")
        #expect(RadarModelIdentity.family(id: id("malformed-low"), displayName: "Fallback Name") == "Fallback Name")
        #expect(RadarModelIdentity.effort(id: id("malformed-low"), displayName: "Fallback Name") == "low")
    }

    @Test("matrix is canonically ordered, deterministically deduplicated, and preserves exact point values")
    func matrixOrderAndValues() {
        let duplicateWinner = point("gpt-5.3-codex-sol-high-a", "Sol A high", quality: 91.25, cost: 0.125, minutes: 3.75, index: 12.5)
        let duplicateLoser = point("gpt-5.3-codex-sol-high-z", "Sol Z high", quality: 99, cost: 9, minutes: 9, index: 99)
        let points = [
            point("zeta", "Zeta high", quality: 80, cost: 2, minutes: 4, index: 40),
            point("gpt-5.5-high", "GPT 5.5 high", quality: 95, cost: 1, minutes: 2, index: 20),
            point("gpt-5.3-codex-luna-low", "Luna low", quality: 70, cost: 3, minutes: 6, index: 60),
            duplicateLoser,
            point("alpha", "Alpha max", quality: 85, cost: 1.5, minutes: 5, index: 30),
            duplicateWinner,
            point("gpt-5.3-codex-terra-xhigh", "Terra xhigh", quality: 90, cost: 0.5, minutes: 1, index: 10),
            point("no-effort", "No Effort", quality: 100, cost: 1, minutes: 1, index: 1),
        ]

        let cells = CodexEfficiencyAnalytics.matrix(points: points)
        let reversed = CodexEfficiencyAnalytics.matrix(points: points.reversed())

        #expect(cells == reversed)
        #expect(cells.map { "\($0.family)/\($0.effort)" } == [
            "Sol/high", "Terra/xhigh", "Luna/low", "GPT-5.5/high", "Alpha/max", "Zeta/high",
        ])
        #expect(Set(cells.map(\.coordinate)).count == cells.count)
        let sol = cells.first { $0.coordinate == .init(family: "Sol", effort: "high") }
        #expect(sol?.point == duplicateWinner)
        #expect(sol?.quality == 91.25)
        #expect(sol?.averageCostUSD == 0.125)
        #expect(sol?.averageMinutes == 3.75)
        #expect(cells.contains { $0.point.id.upstreamKey == "no-effort" } == false)
        let missingMetrics = IntelligenceEfficiency.points(models: [
            benchmark("missing", "Missing high", quality: nil),
        ])
        #expect(CodexEfficiencyAnalytics.matrix(points: missingMetrics).isEmpty)
    }

    @Test("cost versus IQ uses existing coordinates and keeps equal-coordinate models distinct")
    func costVersusIQ() {
        let first = point("gpt-5.3-codex-sol-high", "Sol high", quality: 92, cost: 1, minutes: 2, index: 33)
        let second = point("gpt-5.3-codex-terra-high", "Terra high", quality: 92, cost: 4, minutes: 8, index: 33)

        let projected = CodexEfficiencyAnalytics.costVersusIQ(points: [second, first])

        #expect(projected.count == 2)
        #expect(projected.map(\.point.id) == [first.id, second.id])
        #expect(projected.allSatisfy { $0.x == 33 && $0.y == 92 })
        #expect(Set(projected.map(\.id)).count == 2)
        #expect(projected[0].point == first)
        #expect(projected[1].point == second)
    }

    @Test("Overview family summaries retain canonical order, winner selection, and four-family limit")
    func overviewFamilySummaries() {
        let rows = [
            benchmark("other-high", "Other high", quality: 99),
            benchmark("gpt-5.5-high", "GPT-5.5 high", quality: 88),
            benchmark("gpt-5.3-codex-luna-low", "Luna low", quality: 70),
            benchmark("gpt-5.3-codex-terra-high", "Terra high", quality: 80),
            benchmark("gpt-5.3-codex-sol-low", "Sol low", quality: 75),
            benchmark("gpt-5.3-codex-sol-high", "Sol high", quality: 90),
            benchmark("gpt-5.3-codex-terra-low", "Terra low", quality: nil),
        ].map { WorkspaceModelRow(benchmark: $0, community: nil) }

        let summaries = RadarModelIdentity.familySummaries(rows)

        #expect(summaries.map(\.family) == ["Sol", "Terra", "Luna", "GPT-5.5"])
        #expect(summaries.first?.row.name == "Sol high")
    }

    @Test("QA receipt prints sanitized matrix and C3 coordinates")
    func efficiencyQAReceipt() {
        let points = [
            point("gpt-5.3-codex-terra-xhigh", "Terra xhigh", quality: 90, cost: 0.5, minutes: 1, index: 10),
            point("gpt-5.3-codex-sol-high", "Sol high", quality: 92, cost: 1, minutes: 2, index: 20),
            point("nebula", "Nebula low", quality: 70, cost: 2, minutes: 3, index: 30),
        ]
        let matrix = CodexEfficiencyAnalytics.matrix(points: points)
        let c3 = CodexEfficiencyAnalytics.costVersusIQ(points: points)

        #expect(matrix.map { "\($0.family)/\($0.effort)" } == ["Sol/high", "Terra/xhigh", "Nebula/low"])
        #expect(c3.count == 3)
        if ProcessInfo.processInfo.environment["RADAR_QA_RECEIPT"] == "1" {
            print("RADAR_QA_RECEIPT matrix=\(matrix.map { "\($0.family)/\($0.effort)" }.joined(separator: ","))")
            print("RADAR_QA_RECEIPT c3=\(c3.map { "\($0.x)/\($0.y)/\($0.point.modelName)" }.joined(separator: ","))")
        }
    }

    private func id(_ key: String) -> ModelID {
        ModelID(sourceID: .codexRadar, upstreamKey: key)
    }

    private func point(
        _ key: String,
        _ name: String,
        quality: Double,
        cost: Double,
        minutes: Double,
        index: Double
    ) -> IntelligenceEfficiencyPoint {
        .init(
            id: id(key),
            modelName: name,
            quality: quality,
            averageCostUSD: cost,
            averageMinutes: minutes,
            rawCombinedCost: cost * minutes,
            combinedCostIndex: index
        )
    }

    private func benchmark(_ key: String, _ name: String, quality: Decimal?) -> ModelBenchmark {
        let modelID = id(key)
        return .init(
            id: modelID,
            descriptor: .init(id: modelID, upstreamName: name, displayName: name),
            qualityScore: quality,
            passedTasks: 1,
            validTasks: 1,
            invalidTasks: 0,
            benchmarkCostUSD: 1,
            inputTokens: nil,
            outputTokens: nil,
            cacheReadTokens: nil,
            cacheCreationTokens: nil,
            totalTokens: nil,
            elapsedSeconds: 60,
            agentSteps: nil,
            cacheHitPercent: nil
        )
    }
}
