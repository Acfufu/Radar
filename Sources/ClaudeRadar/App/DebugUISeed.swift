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
            let ratings = second.prefix(2).map {
                CommunityRating(id: $0.id, model: $0.descriptor, average: 8.2, voteCount: 12, scaleMinimum: 1, scaleMaximum: 10)
            }
            _ = try await repository.insertCommunity(.init(sourceID: sourceID, sourceUpdatedAt: base, fetchedAt: base, ratings: ratings), seriesRevision: "fixture-r2")
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
        valid: Int = 10
    ) -> ModelBenchmark {
        let id = ModelID(sourceID: sourceID, upstreamKey: key)
        return .init(
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
            agentSteps: sourceID == .sweBenchVerified ? nil : 14,
            cacheHitPercent: sourceID == .sweBenchVerified ? nil : 82.4
        )
    }

    private static func adjusted(_ models: [ModelBenchmark], by delta: Decimal, passedBy passedDelta: Int = 0) -> [ModelBenchmark] {
        models.map { value in
            .init(
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
}
#endif
