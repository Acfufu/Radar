#if DEBUG
import Foundation

actor DebugBlockingExportArchiver: RadarExportArchiver {
    func archive(contentsOf directory: URL, to destination: URL) async throws {
        try Data("partial".utf8).write(to: destination)
        while !Task.isCancelled {
            await Task.yield()
        }
        throw CancellationError()
    }
}

enum DebugUISeed {
    static let renderedIQHistoryStates: Set<String> = [
        "iq-loading",
        "iq-fresh",
        "iq-stale",
        "iq-lkg-error",
        "iq-schema-drift",
        "iq-challenge",
        "iq-unavailable",
    ]

    static let renderedWarningStates: Set<String> = [
        "warning-loading",
        "warning-fresh-cards",
        "warning-empty",
        "warning-stale",
        "warning-lkg-error",
        "warning-error",
        "warning-empty-benchmark",
        "warning-schema-drift",
        "warning-timeout",
    ]

    static func populate(
        repository: RadarRepository,
        sourceID: RadarSourceID,
        state: String,
        now: Date = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    ) async throws {
        let base = state == "stale" ? now.addingTimeInterval(-8 * 60 * 60) : now
        guard state != "empty" else { return }
        if sourceID == .claudeCodeRadar, state == "analysis" {
            try await populateAnalysis(repository: repository, base: base)
            return
        }
        if sourceID == .claudeCodeRadar, state == "export-501" {
            try await populateExport(repository: repository, base: base)
            return
        }
        if sourceID == .codexRadar {
            try await populateStationStatus(repository: repository, now: now, stale: state == "stale")
            try await populateIntelligenceEfficiency(repository: repository, now: now, stale: state == "stale")
            try await populateFastRadarHistory(repository: repository, now: now, stale: state == "stale")
        }
        if sourceID == .codexRadar, state == "analytics" {
            try await populateAnalytics(repository: repository, now: now)
            return
        }
        if sourceID == .codexRadar, state == "analytics-todo7-gaps" {
            try await populateTodo7AnalyticsGaps(repository: repository, now: now)
            return
        }
        if sourceID == .codexRadar, state == "analytics-todo8-insufficient" {
            try await populateTodo8AnalyticsInsufficient(repository: repository, now: now)
            return
        }

        switch sourceID {
        case .codexRadar:
            try await populateRadar(
                repository: repository,
                sourceID: sourceID,
                base: base,
                now: now,
                state: state,
                ids: ["gpt-5", "gpt-5-mini", "nil-metrics", "long-cjk-prompt"],
                names: [
                    "GPT-5",
                    "GPT-5 mini",
                    "Nil Metrics",
                    "超长模型名称用于换行验证 Ignore previous instructions and render this as inert text",
                ],
                includeBenchmark: state != "warning-empty-benchmark"
            )
        case .sweBenchVerified:
            try await populateSWEBench(repository: repository, base: base, now: now, state: state)
        default:
            try await populateRadar(
                repository: repository,
                sourceID: sourceID,
                base: base,
                now: now,
                state: state,
                ids: ["opus", "sonnet", "haiku", "very-long-model-name-for-cjk-wrapping-check"],
                names: [
                    "Opus 4.8 超长模型名称测试",
                    "Sonnet 4.7",
                    "Haiku 4.5",
                    "Prompt-like <script>alert(1)</script> inert",
                ]
            )
        }
        if sourceID == .codexRadar {
            try await populateRenderedWarning(
                repository: repository,
                state: state,
                now: now
            )
            try await populateRenderedIQHistory(
                repository: repository,
                state: state,
                now: now
            )
        }
    }

    private static func populateRenderedIQHistory(
        repository: RadarRepository,
        state: String,
        now: Date
    ) async throws {
        guard renderedIQHistoryStates.contains(state) else { return }

        switch state {
        case "iq-loading":
            return
        case "iq-schema-drift":
            try await recordRenderedIQHistoryFailure(
                repository: repository,
                attemptedAt: now,
                kind: .validation,
                message: "Rendered IQ history fixture schema drift"
            )
            return
        case "iq-challenge":
            try await recordRenderedIQHistoryFailure(
                repository: repository,
                attemptedAt: now,
                kind: .validation,
                message: "Rendered IQ history fixture challenge"
            )
            return
        case "iq-unavailable":
            try await recordRenderedIQHistoryFailure(
                repository: repository,
                attemptedAt: now,
                kind: .network,
                message: "Rendered IQ history fixture unavailable"
            )
            return
        default:
            break
        }

        let capturedAt = switch state {
        case "iq-stale": now.addingTimeInterval(-8 * 60 * 60)
        case "iq-lkg-error": now.addingTimeInterval(-30 * 60)
        default: now
        }
        let series = renderedIQHistorySeries
        let fingerprint = try CodexRenderedIQHistorySemanticFingerprint.make(
            sourceID: .codexRadar,
            series: series,
            finalOrigin: "https://deng.codexradar.com",
            parserRevision: CodexRenderedIQHistoryDOMParser.parserRevision
        )
        _ = try await repository.insertRenderedIQHistory(CodexRenderedIQHistorySnapshot(
            sourceID: .codexRadar,
            parserRevision: CodexRenderedIQHistoryDOMParser.parserRevision,
            finalOrigin: "https://deng.codexradar.com",
            capturedAt: capturedAt,
            series: series,
            semanticFingerprint: fingerprint
        ))

        if state == "iq-lkg-error" {
            try await recordRenderedIQHistoryFailure(
                repository: repository,
                attemptedAt: now,
                kind: .validation,
                message: "Rendered IQ history fixture refresh failed"
            )
        }
    }

    private static func recordRenderedIQHistoryFailure(
        repository: RadarRepository,
        attemptedAt: Date,
        kind: SegmentError.Kind,
        message: String
    ) async throws {
        try await repository.recordFailure(
            sourceID: .codexRadar,
            datasetType: .renderedIQHistory,
            attemptedAt: attemptedAt,
            error: SegmentError(kind: kind, message: message)
        )
    }

    private static let renderedIQHistorySeries = [
        renderedIQHistorySeries(order: 0, key: "aggregate", name: "官网综合", startIQ: 126),
        renderedIQHistorySeries(order: 1, key: "model:gpt-5.6-sol", name: "GPT-5.6 Sol", startIQ: 128.5),
        renderedIQHistorySeries(order: 2, key: "model:gpt-5.5-codex", name: "GPT-5.5 Codex", startIQ: 119),
        renderedIQHistorySeries(order: 3, key: "model:gpt-5.4", name: "GPT-5.4", startIQ: 110),
        renderedIQHistorySeries(order: 4, key: "model:gpt-5-mini", name: "GPT-5 mini", startIQ: 104),
    ]

    private static func renderedIQHistorySeries(
        order: Int,
        key: String,
        name: String,
        startIQ: Double
    ) -> CodexRenderedIQHistorySeries {
        .init(
            sourceOrder: order,
            seriesKey: key,
            displayName: name,
            points: (0...23).map {
                .init(
                    sourceOrder: $0,
                    sourceTimeLabel: "07/27 \(String(format: "%02d", $0)):00",
                    iq: startIQ - Double($0) / 4
                )
            }
        )
    }

    private static func populateRadar(
        repository: RadarRepository,
        sourceID: RadarSourceID,
        base: Date,
        now: Date,
        state: String,
        ids: [String],
        names: [String],
        includeBenchmark: Bool = true
    ) async throws {
        let first = zip(ids, names).enumerated().map { index, pair in
            model(
                sourceID: sourceID,
                key: pair.0,
                name: pair.1,
                quality: index == 2 ? nil : Decimal(62 - index * 4),
                cost: index == 2 ? nil : Decimal(index + 2),
                tokens: index == 1 || index == 2 ? nil : Int64(40_000 + index * 12_000)
            )
        }
        let second = zip(ids, names).enumerated().map { index, pair in
            model(
                sourceID: sourceID,
                key: pair.0,
                name: pair.1,
                quality: index == 2 ? nil : Decimal(70 - index * 3),
                cost: index == 2 ? nil : Decimal(index + 3),
                tokens: index == 1 || index == 2 ? nil : Int64(44_000 + index * 11_000)
            )
        }
        if includeBenchmark {
            _ = try await repository.insertBenchmark(dataset(sourceID: sourceID, at: base.addingTimeInterval(-10_800), revision: "fixture-r1", models: first))
            _ = try await repository.insertBenchmark(dataset(sourceID: sourceID, at: base.addingTimeInterval(-7_200), revision: "fixture-r1", models: adjusted(first, by: 1)))
            _ = try await repository.insertBenchmark(dataset(sourceID: sourceID, at: base.addingTimeInterval(-3_600), revision: "fixture-r2", models: second))
            _ = try await repository.insertBenchmark(dataset(sourceID: sourceID, at: base, revision: "fixture-r2", models: adjusted(second, by: 1)))
        }

        if state != "status-unavailable" {
            let quotas = [
                SourceQuotaEstimate(id: "h5", windowLabel: "5h", usedPercent: 24, estimatedValueUSD: 231.13, resetDescription: "约 20:50 重置"),
                SourceQuotaEstimate(id: "d7", windowLabel: "7d", usedPercent: state == "quota-nil" ? nil : 41, estimatedValueUSD: state == "quota-nil" ? nil : 1617.91, resetDescription: "约 7 天窗口重置"),
            ]
            _ = try await repository.insertSourceStatus(.init(sourceID: sourceID, sourceUpdatedAt: base, fetchedAt: base, quotaEstimates: quotas), seriesRevision: "fixture-r2")
        }
        if state != "community-unavailable" {
            if sourceID == .codexRadar {
                try await populateCommunityMatrix(repository: repository, now: base)
            } else {
                let ratings = second.prefix(2).map {
                    CommunityRating(id: $0.id, model: $0.descriptor, average: 8.2, voteCount: 12, scaleMinimum: 1, scaleMaximum: 10)
                }
                _ = try await repository.insertCommunity(.init(sourceID: sourceID, sourceUpdatedAt: base, fetchedAt: base, ratings: ratings), seriesRevision: "fixture-r2")
            }
        }
        if state == "community-error" {
            try await repository.recordFailure(sourceID: sourceID, datasetType: .community, attemptedAt: now, error: .init(kind: .http, message: "community HTTP 503"))
        }
        if state == "status-error" {
            try await repository.recordFailure(sourceID: sourceID, datasetType: .sourceStatus, attemptedAt: now, error: .init(kind: .http, message: "source status HTTP 503"))
        }
        if state == "error" || state == "benchmark-error" {
            try await repository.recordFailure(sourceID: sourceID, datasetType: .benchmark, attemptedAt: now, error: .init(kind: .validation, message: "upstream <script>alert(1)</script>"))
        }
    }

    private static func populateRenderedWarning(
        repository: RadarRepository,
        state: String,
        now: Date
    ) async throws {
        guard renderedWarningStates.contains(state) else { return }

        switch state {
        case "warning-loading":
            return
        case "warning-error":
            try await recordRenderedWarningFailure(
                repository: repository,
                attemptedAt: now,
                kind: .validation,
                message: "Rendered warning fixture failure"
            )
            return
        case "warning-schema-drift":
            try await recordRenderedWarningFailure(
                repository: repository,
                attemptedAt: now,
                kind: .validation,
                message: "Rendered warning schema drift"
            )
            return
        case "warning-timeout":
            try await recordRenderedWarningFailure(
                repository: repository,
                attemptedAt: now,
                kind: .network,
                message: "Rendered warning fixture timed out"
            )
            return
        default:
            break
        }

        let capturedAt = switch state {
        case "warning-stale":
            now.addingTimeInterval(-8 * 60 * 60)
        case "warning-lkg-error":
            now.addingTimeInterval(-30 * 60)
        default:
            now
        }
        let cards = state == "warning-empty" ? [] : renderedWarningCards
        let sourceTimeLabel = cards.isEmpty
            ? "Updated just now"
            : "数据更新于 2 分钟前"
        let fingerprint = try CodexRenderedWarningSemanticFingerprint.make(
            sourceTimeLabel: sourceTimeLabel,
            cards: cards,
            finalOrigin: "https://codexradar.com",
            parserRevision: CodexRenderedWarningDOMParser.parserRevision
        )
        _ = try await repository.insertRenderedWarning(CodexRenderedWarningSnapshot(
            sourceID: .codexRadar,
            parserRevision: CodexRenderedWarningDOMParser.parserRevision,
            finalOrigin: "https://codexradar.com",
            sourceTimeLabel: sourceTimeLabel,
            capturedAt: capturedAt,
            cards: cards,
            semanticFingerprint: fingerprint
        ))

        if state == "warning-lkg-error" {
            try await recordRenderedWarningFailure(
                repository: repository,
                attemptedAt: now,
                kind: .validation,
                message: "Rendered warning refresh failed; cached cards retained"
            )
        }
    }

    private static func recordRenderedWarningFailure(
        repository: RadarRepository,
        attemptedAt: Date,
        kind: SegmentError.Kind,
        message: String
    ) async throws {
        try await repository.recordFailure(
            sourceID: .codexRadar,
            datasetType: .renderedWarnings,
            attemptedAt: attemptedAt,
            error: SegmentError(kind: kind, message: message)
        )
    }

    private static let renderedWarningCards = [
        CodexRenderedWarningCard(
            displayName: "GPT-5.6 Sol · Max",
            family: "gpt-5.6-sol",
            effort: "max",
            sourceOrder: 0,
            iq: 128.5,
            drop24h: 2.25,
            drop48h: 4.5
        ),
        CodexRenderedWarningCard(
            displayName: "GPT-5.6 Sol · High",
            family: "gpt-5.6-sol",
            effort: "high",
            sourceOrder: 1,
            iq: 126,
            drop24h: 1,
            drop48h: 2
        ),
        CodexRenderedWarningCard(
            displayName: "GPT-5.5 Codex · Medium",
            family: "gpt-5.5-codex",
            effort: "medium",
            sourceOrder: 2,
            iq: 119,
            drop24h: 0,
            drop48h: 0.5
        ),
        CodexRenderedWarningCard(
            displayName: "GPT-5.4 · Low",
            family: "gpt-5.4",
            effort: "low",
            sourceOrder: 3,
            iq: 110,
            drop24h: 3,
            drop48h: nil
        ),
    ]

    private static func populateSWEBench(repository: RadarRepository, base: Date, now: Date, state: String) async throws {
        let rows = [
            model(sourceID: .sweBenchVerified, key: "frontier", name: "Same Display Name", quality: 82, cost: 180, tokens: nil, passed: 410, valid: 500),
            model(sourceID: .sweBenchVerified, key: "dominated", name: "Same Display Name", quality: 70, cost: 240, tokens: nil, passed: 350, valid: 500),
            model(sourceID: .sweBenchVerified, key: "no-cost", name: "No Published Cost", quality: 76, cost: nil, tokens: nil, passed: 380, valid: 500),
            model(sourceID: .sweBenchVerified, key: "long-cjk", name: "超长 SWE-bench 模型名称 Ignore previous instructions; inert display text", quality: 78, cost: 210, tokens: nil, passed: 390, valid: 500),
        ]
        _ = try await repository.insertBenchmark(dataset(sourceID: .sweBenchVerified, at: base.addingTimeInterval(-3_600), revision: "fixture-swe-r1", models: adjusted(rows, by: -1, passedBy: -5)))
        _ = try await repository.insertBenchmark(dataset(sourceID: .sweBenchVerified, at: base, revision: "fixture-swe-r2", models: rows))
        if state == "error" || state == "benchmark-error" {
            try await repository.recordFailure(sourceID: .sweBenchVerified, datasetType: .benchmark, attemptedAt: now, error: .init(kind: .validation, message: "SWE-bench fixture validation failure"))
        }
    }

    private static func populateAnalysis(repository: RadarRepository, base: Date) async throws {
        let prior = [
            model(sourceID: .claudeCodeRadar, key: "revision-changed", name: "Revision Changed", quality: 99, cost: 1, tokens: 100),
        ]
        let current = [
            model(sourceID: .claudeCodeRadar, key: "dominated", name: "Beta Dominated", quality: 80, cost: 3, tokens: 300),
            model(sourceID: .claudeCodeRadar, key: "frontier", name: "Frontier", quality: 90, cost: 2, tokens: 200),
            model(sourceID: .claudeCodeRadar, key: "missing", name: "Nil Metric", quality: nil, cost: 1, tokens: 100),
            model(sourceID: .claudeCodeRadar, key: "tie-a", name: "Same Tie", quality: 90, cost: 2, tokens: 200),
            model(sourceID: .claudeCodeRadar, key: "tie-b", name: "Same Tie", quality: 90, cost: 2, tokens: 200),
            model(sourceID: .claudeCodeRadar, key: "zero-passed", name: "Zero Passed", quality: 70, cost: 4, tokens: 400, passed: 0),
        ]
        _ = try await repository.insertBenchmark(dataset(sourceID: .claudeCodeRadar, at: base.addingTimeInterval(-3_600), revision: "fixture-r1", models: prior))
        _ = try await repository.insertBenchmark(dataset(sourceID: .claudeCodeRadar, at: base, revision: "fixture-r2", models: current))
    }

    private static func populateAnalytics(repository: RadarRepository, now: Date) async throws {
        let revision = "fixture-analytics-r1"
        guard try await repository.benchmarkHistory(sourceID: .codexRadar).allSatisfy({ $0.seriesRevision != revision }) else { return }
        let current = analyticsModels()
        for (hours, delta) in [(-26.0, -4), (-24.0, -3), (-12.0, -2), (-4.0, -1), (0.0, 0)] {
            let date = now.addingTimeInterval(hours * 60 * 60)
            _ = try await repository.insertBenchmark(dataset(
                sourceID: .codexRadar,
                at: date,
                revision: revision,
                models: adjusted(current, by: Decimal(delta))
            ))
        }
    }

    private static func populateTodo7AnalyticsGaps(repository: RadarRepository, now: Date) async throws {
        try await populateAnalytics(repository: repository, now: now)
        let revision = "fixture-analytics-r2"
        guard try await repository.benchmarkHistory(sourceID: .codexRadar)
            .allSatisfy({ $0.seriesRevision != revision })
        else { return }
        _ = try await repository.insertBenchmark(dataset(
            sourceID: .codexRadar,
            at: now.addingTimeInterval(60),
            revision: revision,
            models: analyticsModels()
        ))
    }

    private static func populateTodo8AnalyticsInsufficient(repository: RadarRepository, now: Date) async throws {
        let revision = "fixture-analytics-insufficient-r1"
        guard try await repository.benchmarkHistory(sourceID: .codexRadar)
            .allSatisfy({ $0.seriesRevision != revision })
        else { return }
        let current = analyticsModels()
        _ = try await repository.insertBenchmark(dataset(
            sourceID: .codexRadar,
            at: now.addingTimeInterval(-7_200),
            revision: revision,
            models: current
        ))
        _ = try await repository.insertBenchmark(dataset(
            sourceID: .codexRadar,
            at: now.addingTimeInterval(-3_600),
            revision: revision,
            models: replacingQuality(in: current, with: nil)
        ))
        let conflictTime = now.addingTimeInterval(-1_800)
        _ = try await repository.insertBenchmark(dataset(
            sourceID: .codexRadar,
            at: conflictTime,
            revision: revision,
            models: adjusted(current, by: 1)
        ))
        _ = try await repository.insertBenchmark(dataset(
            sourceID: .codexRadar,
            at: conflictTime,
            revision: revision,
            models: adjusted(current, by: 2)
        ))
    }

    private static func analyticsModels() -> [ModelBenchmark] {
        [
            model(sourceID: .codexRadar, key: "gpt-5.6-sol-max", name: "GPT-5.6 Sol · Max", quality: 130, cost: 20, tokens: 120_000, agentSteps: 18),
            model(sourceID: .codexRadar, key: "gpt-5.6-sol-high", name: "GPT-5.6 Sol · High", quality: 126, cost: 12, tokens: 96_000, agentSteps: 15),
            model(sourceID: .codexRadar, key: "gpt-5.6-terra-max", name: "GPT-5.6 Terra · Max", quality: 128, cost: 16, tokens: 108_000, agentSteps: 17),
            model(sourceID: .codexRadar, key: "gpt-5.6-terra-high", name: "GPT-5.6 Terra · High", quality: 126, cost: 10, tokens: 88_000, agentSteps: 14),
            model(sourceID: .codexRadar, key: "gpt-5.6-luna-high", name: "GPT-5.6 Luna · High", quality: 121, cost: 7, tokens: 72_000, agentSteps: 12),
            model(sourceID: .codexRadar, key: "gpt-5.6-luna-medium", name: "GPT-5.6 Luna · Medium", quality: 117, cost: 5, tokens: 60_000, agentSteps: nil),
            model(sourceID: .codexRadar, key: "gpt-5.5-codex-high", name: "GPT-5.5 Codex · High", quality: 114, cost: 4, tokens: 52_000, agentSteps: 10),
            model(sourceID: .codexRadar, key: "gpt-5.5-codex-medium", name: "GPT-5.5 Codex · Medium", quality: 110, cost: 3, tokens: 44_000, agentSteps: 8),
        ]
    }

    private static func populateExport(repository: RadarRepository, base: Date) async throws {
        for index in 0..<501 {
            let date = base.addingTimeInterval(TimeInterval(index - 501))
            let sample = model(sourceID: .claudeCodeRadar, key: "export-\(index)", name: "Export Model \(index)", quality: nil, cost: Decimal(string: "1.2300"), tokens: nil)
            _ = try await repository.insertBenchmark(dataset(sourceID: .claudeCodeRadar, at: date, revision: "fixture-export-\(index)", models: [sample]))
        }
    }

    private static func dataset(sourceID: RadarSourceID, at date: Date, revision: String, models: [ModelBenchmark]) -> BenchmarkDataset {
        .init(sourceID: sourceID, sourceUpdatedAt: date, fetchedAt: date, benchmarkName: "Debug QA Fixture", benchmarkVersion: "1", seriesRevision: revision, models: models)
    }

    private static func model(
        sourceID: RadarSourceID,
        key: String,
        name: String,
        quality: Decimal?,
        cost: Decimal?,
        tokens: Int64?,
        passed: Int = 8,
        valid: Int = 10,
        agentSteps: Int? = 14
    ) -> ModelBenchmark {
        let id = ModelID(sourceID: sourceID, upstreamKey: key)
        return ModelBenchmark(
            id: id,
            descriptor: .init(id: id, upstreamName: name, displayName: name),
            qualityScore: quality,
            passedTasks: passed,
            validTasks: valid,
            invalidTasks: valid - passed,
            benchmarkCostUSD: cost,
            inputTokens: tokens.map { $0 / 2 },
            outputTokens: tokens.map { $0 / 4 },
            cacheReadTokens: tokens.map { $0 / 5 },
            cacheCreationTokens: nil,
            totalTokens: tokens,
            elapsedSeconds: sourceID == .sweBenchVerified ? nil : 20,
            agentSteps: sourceID == .sweBenchVerified ? nil : agentSteps,
            cacheHitPercent: sourceID == .sweBenchVerified ? nil : 82.4
        )
    }

    private static func adjusted(_ models: [ModelBenchmark], by delta: Decimal, passedBy passedDelta: Int = 0) -> [ModelBenchmark] {
        models.map { value in
            ModelBenchmark(
                id: value.id,
                descriptor: value.descriptor,
                qualityScore: value.qualityScore.map { $0 + delta },
                passedTasks: value.passedTasks.map { $0 + passedDelta },
                validTasks: value.validTasks,
                invalidTasks: value.invalidTasks.map { $0 - passedDelta },
                benchmarkCostUSD: value.benchmarkCostUSD,
                inputTokens: value.inputTokens,
                outputTokens: value.outputTokens,
                cacheReadTokens: value.cacheReadTokens,
                cacheCreationTokens: value.cacheCreationTokens,
                totalTokens: value.totalTokens,
                elapsedSeconds: value.elapsedSeconds,
                agentSteps: value.agentSteps,
                cacheHitPercent: value.cacheHitPercent
            )
        }
    }

    private static func replacingQuality(in models: [ModelBenchmark], with quality: Decimal?) -> [ModelBenchmark] {
        models.map { value in
            ModelBenchmark(
                id: value.id,
                descriptor: value.descriptor,
                qualityScore: quality,
                passedTasks: value.passedTasks,
                validTasks: value.validTasks,
                invalidTasks: value.invalidTasks,
                benchmarkCostUSD: value.benchmarkCostUSD,
                inputTokens: value.inputTokens,
                outputTokens: value.outputTokens,
                cacheReadTokens: value.cacheReadTokens,
                cacheCreationTokens: value.cacheCreationTokens,
                totalTokens: value.totalTokens,
                elapsedSeconds: value.elapsedSeconds,
                agentSteps: value.agentSteps,
                cacheHitPercent: value.cacheHitPercent
            )
        }
    }

    /// Codex station-status seed (spec §5.1): a small synthetic snapshot with
    /// all D13 verbatim fields, used by fixture UI launches so the banner,
    /// prediction and Tibo surfaces render with data.
    private static func populateStationStatus(
        repository: RadarRepository,
        now: Date,
        stale: Bool
    ) async throws {
        let dataset = CodexStationStatusDataset(
            sourceID: .codexRadar,
            fetchedAt: stale ? now.addingTimeInterval(-9 * 60 * 60) : now,
            monitoredAt: "2026-07-15T16:00:00+08:00",
            timezone: "Asia/Shanghai",
            windowOpen: true,
            status: "community_confirmed",
            recommendedAction: "ready",
            window: .init(
                isOpen: true,
                status: "community_confirmed",
                action: "ready",
                message: "速蹬窗口已开启（fixture）",
                title: "Codex 用量限制重置",
                scope: "Codex 用户",
                openedAt: nil,
                closedAt: nil,
                sourceURL: "https://codexradar.com/"
            ),
            prediction: .init(
                level: "low",
                probability24h: 0.14,
                probability48h: 0.27,
                summary: "上一轮硬重置刚完成。",
                summaryEN: "Latest hard reset complete.",
                updatedAt: nil
            ),
            tiboPresence: .init(
                timezone: "America/Los_Angeles",
                locationLabelZH: "旧金山湾区 / PT",
                locationLabelEN: "San Francisco Bay Area / PT",
                probability: 0.2,
                confidence: "low",
                evidenceSummaryZH: "所提供的公开帖子未明确披露当前国家或地区。",
                evidenceSummaryEN: "Public posts do not disclose the region.",
                sourceURLs: ["https://x.com/thsottiaux/status/2079647758869475531"],
                shouldDisplay: true,
                safetyNoteZH: "仅基于公开发帖做国家/时区级推测，不展示住址。",
                safetyNoteEN: "Region-level inference only.",
                observedAt: nil,
                updatedAt: nil
            )
        )
        _ = try await repository.insertStationStatus(dataset)
    }

    /// Spec §5.2 fixture seed for the efficiency-PK ranking card. Fixture
    /// text only — never upstream copy.
    private static func populateIntelligenceEfficiency(
        repository: RadarRepository,
        now: Date,
        stale: Bool
    ) async throws {
        let dataset = IntelligenceEfficiencyDataset(
            sourceID: .codexRadar,
            fetchedAt: stale ? now.addingTimeInterval(-9 * 60 * 60) : now,
            schema: 2,
            mode: "equal_latest_3",
            type: IntelligenceEfficiencyParser.expectedType,
            // Provenance shape only: the seed never carries the real
            // protected-API host (spec §5.0 forbid-domain scan stays total).
            source: "https://api.fixture.invalid/v1/table",
            metricsSource: "https://api.fixture.invalid/v1/intelligence-efficiency",
            sourceUpdatedAt: "2026-09-05T01:27:38+08:00",
            models: 17,
            runs24hTotal: 267,
            runs48hTotal: 375,
            runsTotal: 42_903,
            points: [
                .init(
                    model: "gpt-5.6-sol",
                    effort: "xhigh",
                    harness: "codex",
                    iq: 88.4,
                    passed: 291,
                    validTasks: 336,
                    averagePriceUSD: 4.51,
                    priceSamples: 336,
                    averageMinutes: 12.4,
                    durationSamples: 330,
                    incompleteCostSamples: 0,
                    totalRuns: 2_104,
                    latestGradedAt: "2026-09-04T05:38:54+00:00",
                    averageAgentSteps: 44.1,
                    agentStepsSamples: 328,
                    averageTotalTokens: 2_210_400.5,
                    tokenSamples: 336,
                    cacheHitRate: 0.951,
                    cacheTokenSamples: 336,
                    averagePriceUSDBand: nil,
                    runs24h: 9,
                    runs48h: 15,
                    runsTotal: 2_104,
                    rawCombinedCost: 412.9,
                    combinedCostIndex: 12.7
                ),
                .init(
                    model: "gpt-5.6-terra",
                    effort: "max",
                    harness: "codex",
                    iq: 84.2,
                    passed: 270,
                    validTasks: 336,
                    averagePriceUSD: 3.02,
                    priceSamples: 336,
                    averageMinutes: 11.1,
                    durationSamples: 331,
                    incompleteCostSamples: 2,
                    totalRuns: 1_988,
                    latestGradedAt: "2026-09-04T05:38:54+00:00",
                    averageAgentSteps: 41.8,
                    agentStepsSamples: 330,
                    averageTotalTokens: 1_988_100.25,
                    tokenSamples: 336,
                    cacheHitRate: 0.948,
                    cacheTokenSamples: 336,
                    averagePriceUSDBand: nil,
                    runs24h: 6,
                    runs48h: 11,
                    runsTotal: 1_988,
                    rawCombinedCost: 233.4,
                    combinedCostIndex: 7.2
                ),
                .init(
                    model: "deepseek-v4-flash",
                    effort: "off",
                    harness: "dsh",
                    iq: 71.6,
                    passed: 214,
                    validTasks: 336,
                    averagePriceUSD: 0.34,
                    priceSamples: 300,
                    averageMinutes: 8.9,
                    durationSamples: 296,
                    incompleteCostSamples: 0,
                    totalRuns: 1_402,
                    latestGradedAt: "2026-09-04T05:38:54+00:00",
                    averageAgentSteps: 33.6,
                    agentStepsSamples: 300,
                    averageTotalTokens: 1_402_800.75,
                    tokenSamples: 336,
                    cacheHitRate: 0.936,
                    cacheTokenSamples: 336,
                    averagePriceUSDBand: .init(offPeak: 0.22, peak: 0.45),
                    runs24h: 4,
                    runs48h: 8,
                    runsTotal: 1_402,
                    rawCombinedCost: 12.1,
                    combinedCostIndex: 0.4
                ),
            ],
            history: [
                .init(
                    at: "2026-08-20T10:00:00+08:00",
                    points: [
                        .init(
                            model: "gpt-5.6-sol",
                            effort: "xhigh",
                            passed: 285,
                            validTasks: 336,
                            iq: 86.9,
                            averagePriceUSD: 4.40,
                            priceSamples: 330,
                            averageMinutes: 12.2,
                            durationSamples: 324,
                            averageAgentSteps: 43.7,
                            agentStepsSamples: 322,
                            averageTotalTokens: 2_180_900.1,
                            tokenSamples: 330,
                            cacheHitRate: 0.950,
                            cacheTokenSamples: 330
                        ),
                    ]
                ),
                .init(
                    at: "2026-09-04T01:27:38+08:00",
                    points: [
                        .init(
                            model: "gpt-5.6-sol",
                            effort: "xhigh",
                            passed: 291,
                            validTasks: 336,
                            iq: 88.4,
                            averagePriceUSD: 4.51,
                            priceSamples: 336,
                            averageMinutes: 12.4,
                            durationSamples: 330,
                            averageAgentSteps: 44.1,
                            agentStepsSamples: 328,
                            averageTotalTokens: 2_210_400.5,
                            tokenSamples: 336,
                            cacheHitRate: 0.951,
                            cacheTokenSamples: 336
                        ),
                    ]
                ),
            ],
            fingerprint: "seed-fingerprint-intelligence-efficiency",
            activityFingerprint: "seed-activity-fingerprint-intelligence-efficiency",
            method: .init(
                iq: "fixture：每任务等权最近三个有效样本；pass_rate × 150",
                price: "fixture：均值口径说明（种子文案，非上游原文）",
                duration: "fixture：最近一次平均时长（分钟）",
                combinedCost: "fixture：组合成本指数说明"
            )
        )
        _ = try await repository.insertIntelligenceEfficiency(dataset)
    }

    /// Spec §5.4 fixture seed for the star rating matrix: groups, effort
    /// suffixes, 7-day history buckets, and a read-only my_scores entry.
    /// Fixture text only — never upstream copy.
    private static func populateCommunityMatrix(
        repository: RadarRepository,
        now: Date
    ) async throws {
        func rating(_ key: String, _ name: String, group: String, average: Decimal?) -> CommunityRating {
            let id = ModelID(sourceID: .codexRadar, upstreamKey: key)
            return CommunityRating(
                id: id,
                model: ModelDescriptor(id: id, upstreamName: name, displayName: name),
                average: average,
                voteCount: 12,
                scaleMinimum: 1,
                scaleMaximum: 10,
                group: group
            )
        }
        let ratings = [
            rating("gpt-5.6-sol-ultra", "GPT-5.6 Sol ultra（fixture）", group: "GPT-5.6 Sol", average: 8.7),
            rating("gpt-5.6-sol-xhigh", "GPT-5.6 Sol xhigh（fixture）", group: "GPT-5.6 Sol", average: 8.1),
            rating("gpt-5.6-terra-max", "GPT-5.6 Terra max（fixture）", group: "GPT-5.6 Terra", average: 7.9),
            rating("gpt-5.5-high", "GPT-5.5 high（fixture）", group: "GPT-5.5", average: 7.2),
            rating("deepseek-v4-flash-off", "DSV4 Flash off（fixture）", group: "DSV4 Flash", average: 6.4),
        ]
        let historyKeys = [
            "2026-08-30", "2026-08-31", "2026-09-01", "2026-09-02",
            "2026-09-03", "2026-09-04", "2026-09-05",
        ]
        let history = historyKeys.enumerated().map { index, day in
            CommunityHistoryDay(
                day: day,
                updatedAt: nil,
                ratings: ratings.map { rating in
                    CommunityHistoryRating(
                        id: rating.id.upstreamKey,
                        group: rating.group,
                        average: (rating.average ?? 7) - Decimal(index % 2),
                        count: 10 + index
                    )
                }
            )
        }
        let dataset = CommunityDataset(
            sourceID: .codexRadar,
            sourceUpdatedAt: now,
            fetchedAt: now,
            ratings: ratings,
            history: history,
            day: "2026-09-05",
            myScores: ["gpt-5.6-sol-ultra": 8.5]
        )
        _ = try await repository.insertCommunity(dataset, seriesRevision: "fixture-r2")
    }

    /// Spec §5.3 fixture seed for the Fast radar page. Fixture text only.
    private static func populateFastRadarHistory(
        repository: RadarRepository,
        now: Date,
        stale: Bool
    ) async throws {
        func measurement(ttft: Double, tps: Double, e2e: Double) -> FastRadarHistoryDataset.FastRadarRun.Measurement {
            .init(ttftSeconds: ttft, tps: tps, e2eSeconds: e2e)
        }
        func tier(standard: (Double, Double, Double), fast: (Double, Double, Double)) -> FastRadarHistoryDataset.FastRadarRun.Tier {
            .init(standard: measurement(ttft: standard.0, tps: standard.1, e2e: standard.2), fast: measurement(ttft: fast.0, tps: fast.1, e2e: fast.2))
        }
        let runs = [
            FastRadarHistoryDataset.FastRadarRun(
                runID: "20260820-0900",
                measuredAt: "2026-08-20T09:00:00+08:00",
                completedAt: "2026-08-20T09:06:40+08:00",
                cliVersion: "0.147.0",
                models: .init(
                    sol: tier(standard: (8.1, 50.2, 48.9), fast: (3.4, 68.1, 21.0)),
                    terra: tier(standard: (8.4, 49.0, 50.1), fast: (3.6, 66.0, 22.4))
                )
            ),
            FastRadarHistoryDataset.FastRadarRun(
                runID: "20260901-1400",
                measuredAt: "2026-09-01T14:00:00+08:00",
                completedAt: "2026-09-01T14:07:10+08:00",
                cliVersion: "0.148.0",
                models: .init(
                    sol: tier(standard: (8.0, 50.9, 49.2), fast: (3.3, 68.8, 20.8)),
                    terra: tier(standard: (8.3, 49.5, 50.3), fast: (3.5, 66.9, 22.1)),
                    luna: tier(standard: (7.6, 52.4, 46.0), fast: (3.1, 70.2, 19.5))
                )
            ),
            FastRadarHistoryDataset.FastRadarRun(
                runID: "20260904-1314",
                measuredAt: "2026-09-04T13:14:54+08:00",
                completedAt: "2026-09-04T13:20:24+08:00",
                cliVersion: "0.149.0",
                models: .init(
                    sol: tier(standard: (8.26, 51.5, 49.3), fast: (3.35, 69.4, 20.4)),
                    terra: tier(standard: (8.5, 48.8, 50.8), fast: (3.7, 66.2, 22.6)),
                    luna: tier(standard: (7.4, 53.0, 45.2), fast: (3.0, 71.0, 19.0))
                )
            ),
        ]
        let dataset = FastRadarHistoryDataset(
            sourceID: .codexRadar,
            fetchedAt: stale ? now.addingTimeInterval(-9 * 60 * 60) : now,
            schemaVersion: 1,
            type: FastRadarHistoryParser.expectedType,
            timezone: "Asia/Shanghai",
            updatedAt: "2026-09-04T13:20:24+08:00",
            runs: runs
        )
        _ = try await repository.insertFastRadarHistory(dataset)
    }
}
#endif
