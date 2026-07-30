import Foundation
import Testing
@testable import ClaudeRadar

@Suite("CodexIQHistoryAnalyticsTests")
struct CodexIQHistoryAnalyticsTests {
    @Test("local Codex history groups canonical families and keeps revision and nil gaps separate")
    func groupsAndSegmentsLocalHistory() {
        let history = [
            snapshot(at: 30, revision: "r2", models: [model("gpt-5.6-sol-max", iq: 98)]),
            .init(sourceID: .codexRadar, sourceUpdatedAt: nil, fetchedAt: date(29), benchmarkName: "sanitized", benchmarkVersion: nil, seriesRevision: "r2", models: [model("gpt-5.6-sol-max", iq: 97)]),
            snapshot(at: 10, fetchedAt: 90, revision: "r1", models: [model("gpt-5.6-sol-max", iq: 90)]),
            snapshot(at: 20, fetchedAt: 80, revision: "r1", models: [model("gpt-5.6-sol-max", iq: nil)]),
            snapshot(at: 25, fetchedAt: 70, revision: "r1", models: [model("gpt-5.6-sol-max", iq: 94)]),
            snapshot(at: 15, fetchedAt: 100, revision: "r1", models: [model("gpt-5.6-terra-high", iq: 82)]),
            snapshot(at: 35, revision: "r1", models: [model("gpt-5.6-luna-medium", iq: 76)]),
            snapshot(at: 40, revision: "r1", models: [model("gpt-5.5-high", iq: 73)]),
            snapshot(at: 31, revision: "r2", models: [model("gpt-5.6-sol-max", iq: 99)]),
            snapshot(at: 45, revision: "r1", sourceID: .claudeCodeRadar, models: [model("gpt-5.6-sol-max", iq: 12, sourceID: .claudeCodeRadar)]),
            snapshot(at: 50, revision: "r1", models: [model("gpt-5.6-sol-max", iq: 99, sourceID: .claudeCodeRadar)]),
        ]

        let projected = CodexIQHistoryAnalytics.project(history: history)
        let sol = projected.panels.first { $0.family == "Sol" }!

        #expect(projected.availability == .available)
        #expect(projected.panels.map(\.family) == ["Sol", "Terra", "Luna", "GPT-5.5"])
        #expect(projected.panels.map { $0.lines.map(\.effort) } == [["max"], ["high"], ["medium"], ["high"]])
        #expect(sol.lines[0].segments.map(\.seriesRevision) == ["r1", "r1", "r2"])
        #expect(sol.lines[0].segments.map { $0.points.map(\.date) } == [[date(10)], [date(25)], [date(29), date(30), date(31)]])
        #expect(sol.lines[0].segments.flatMap(\.points).map(\.value) == [90, 94, 97, 98, 99])
    }

    @Test("identical timestamp values dedupe while conflicts become gaps independently of input order")
    func duplicateResolutionIsDeterministic() {
        let snapshots = [
            snapshot(at: 10, revision: "r1", models: [model("gpt-5.6-sol-max", iq: 90)]),
            snapshot(at: 10, fetchedAt: 11, revision: "r1", models: [model("gpt-5.6-sol-max", iq: 90)]),
            snapshot(at: 20, revision: "r1", models: [model("gpt-5.6-sol-max", iq: 91)]),
            snapshot(at: 20, fetchedAt: 21, revision: "r1", models: [model("gpt-5.6-sol-max", iq: 92)]),
            snapshot(at: 30, revision: "r1", models: [model("gpt-5.6-sol-max", iq: 93)]),
        ]

        let first = CodexIQHistoryAnalytics.project(history: snapshots)
        let reversed = CodexIQHistoryAnalytics.project(history: snapshots.reversed())
        let sol = first.panels.first { $0.family == "Sol" }!

        #expect(first == reversed)
        #expect(sol.lines[0].segments.map { $0.points.map(\.date) } == [[date(10)], [date(30)]])
        #expect(sol.lines[0].segments.flatMap(\.points).map(\.value) == [90, 93])
    }

    @Test("zero or one comparable local points explicitly reports insufficient history")
    func insufficientHistory() {
        let empty = CodexIQHistoryAnalytics.project(history: [])
        let one = CodexIQHistoryAnalytics.project(history: [
            snapshot(at: 1, revision: "r1", models: [model("gpt-5.6-sol-max", iq: 90)]),
            snapshot(at: 2, revision: "r2", models: [model("gpt-5.6-sol-max", iq: 91)]),
        ])

        #expect(empty.availability == .insufficientHistory)
        #expect(one.availability == .insufficientHistory)
        #expect(empty.panels.map(\.family) == ["Sol", "Terra", "Luna", "GPT-5.5"])
    }

    @Test("non-finite IQ is an unavailable gap")
    func nonFiniteIQIsUnavailableGap() {
        let projected = CodexIQHistoryAnalytics.project(history: [
            snapshot(at: 10, revision: "r1", models: [model("gpt-5.6-sol-max", iq: 90)]),
            snapshot(at: 20, revision: "r1", models: [model("gpt-5.6-sol-max", iq: .nan)]),
            snapshot(at: 30, revision: "r1", models: [model("gpt-5.6-sol-max", iq: 91)]),
        ])
        let sol = projected.panels.first { $0.family == "Sol" }!

        #expect(projected.availability == .insufficientHistory)
        #expect(sol.lines[0].segments.map { $0.points.map(\.date) } == [[date(10)], [date(30)]])
    }

    @Test("qa receipt counts local family effort revision segments and points")
    func qaReceipt() {
        let history = [
            snapshot(at: 0, revision: "r1", models: [model("gpt-5.6-sol-max", iq: 90)]),
            snapshot(at: 12 * 60 * 60, revision: "r1", models: [model("gpt-5.6-sol-max", iq: nil)]),
            snapshot(at: 18 * 60 * 60, revision: "r1", models: [model("gpt-5.6-sol-max", iq: 91)]),
            snapshot(at: 25 * 60 * 60, revision: "r2", models: [model("gpt-5.6-sol-max", iq: 95)]),
            snapshot(at: 26 * 60 * 60, revision: "r2", models: [model("gpt-5.6-sol-max", iq: 96)]),
            snapshot(at: 27 * 60 * 60, revision: "r1", models: [model("gpt-5.6-terra-high", iq: 80)]),
            snapshot(at: 28 * 60 * 60, revision: "r1", models: [model("gpt-5.6-terra-high", iq: 81)]),
        ]
        let projected = CodexIQHistoryAnalytics.project(history: history)

        if ProcessInfo.processInfo.environment["RADAR_QA_RECEIPT"] == "1" {
            for panel in projected.panels {
                let efforts = panel.lines.count
                let segments = panel.lines.flatMap(\.segments).count
                let points = panel.lines.flatMap(\.segments).flatMap(\.points).count
                let revisions = panel.lines.flatMap(\.segments).map(\.seriesRevision).joined(separator: ",")
                print("IQ_HISTORY_RECEIPT family=\(panel.family) efforts=\(efforts) segments=\(segments) points=\(points) revisions=\(revisions)")
            }
        }
        let sol = projected.panels.first { $0.family == "Sol" }!
        #expect(projected.availability == .available)
        #expect(sol.lines[0].segments.map(\.seriesRevision) == ["r1", "r1", "r2"])
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func snapshot(
        at seconds: TimeInterval,
        fetchedAt: TimeInterval? = nil,
        revision: String,
        sourceID: RadarSourceID = .codexRadar,
        models: [ModelBenchmark]
    ) -> BenchmarkDataset {
        .init(
            sourceID: sourceID,
            sourceUpdatedAt: date(seconds),
            fetchedAt: date(fetchedAt ?? seconds),
            benchmarkName: "sanitized",
            benchmarkVersion: nil,
            seriesRevision: revision,
            models: models
        )
    }

    private func model(
        _ key: String,
        iq: Decimal?,
        sourceID: RadarSourceID = .codexRadar
    ) -> ModelBenchmark {
        let id = ModelID(sourceID: sourceID, upstreamKey: key)
        return .init(
            id: id,
            descriptor: .init(id: id, upstreamName: key, displayName: key.replacingOccurrences(of: "-", with: " ")),
            qualityScore: iq,
            passedTasks: nil,
            validTasks: nil,
            invalidTasks: nil,
            benchmarkCostUSD: nil,
            inputTokens: nil,
            outputTokens: nil,
            cacheReadTokens: nil,
            cacheCreationTokens: nil,
            totalTokens: nil,
            elapsedSeconds: nil,
            agentSteps: nil,
            cacheHitPercent: nil
        )
    }
}
