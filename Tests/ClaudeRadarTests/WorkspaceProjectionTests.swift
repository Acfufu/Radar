import AppKit
import Foundation
import Testing
@testable import ClaudeRadar

@Suite("WorkspaceProjectionTests")
struct WorkspaceProjectionTests {
    @Test("navigation remains a fixed destination set within each source workspace")
    func navigationContract() {
        #expect(WorkspaceDestination.allCases == [.overview, .decisionLens, .models, .trends, .intelligenceCenter, .sourceStatus, .export])
        let decisionLensRoute = WorkspaceRoute.sourcePage(.claudeCodeRadar, .decisionLens)
        #expect(WorkspaceRoute(storageKey: decisionLensRoute.storageKey) == decisionLensRoute)
        #expect(WorkspaceDestination.models.title(for: .sweBenchVerified) == "榜单")
        #expect(WorkspaceDestination.sourceStatus.title(for: .sweBenchVerified) == "来源与口径")
        let route = WorkspaceRoute.sourcePage(.sweBenchVerified, .models)
        #expect(WorkspaceRoute(storageKey: route.storageKey) == route)
        #expect(WorkspaceCopy.exportPlaceholder == "Phase 6 将提供分页 JSON 导出")
        #expect(WorkspaceCopy.sourceStatusTitle == "Claude Code Radar 来源状态")
        #expect(WorkspaceCopy.quotaTitle == "Claude Code Radar 来源额度估算")
        #expect(!WorkspaceCopy.quotaTitle.contains("我的"))
        #expect(!WorkspaceCopy.quotaTitle.contains("个人"))
    }

    @Test("fresh stale validation empty loading disabled and community unavailable remain distinct")
    func stateDistinctions() {
        let fresh = projection(sync: sync(benchmark: state(value: benchmark())))
        #expect(fresh.benchmarkState == .fresh)
        #expect(fresh.communityState == .unavailable("社区评分暂不可用"))
        #expect(fresh.supportState == .disabled("在线来源在当前构建中未启用"))

        let stale = projection(sync: sync(benchmark: state(value: benchmark(), stale: true)))
        #expect(stale.benchmarkState == .stale)

        let invalid = projection(sync: sync(benchmark: state(
            value: benchmark(), error: .init(kind: .validation, message: "upstream <script>alert(1)</script>")
        )))
        #expect(invalid.benchmarkState == .validationFailed(hasLastKnownGood: true))
        #expect(invalid.latestError?.contains("<script>") == false)

        #expect(projection(sync: nil, lifecycle: .starting).benchmarkState == .loading)
        #expect(projection(sync: nil, lifecycle: .failed).benchmarkState == .error("同步运行时不可用"))
        #expect(projection(sync: sync()).benchmarkState == .empty)
        #expect(projection(sync: sync(), support: .experimental).benchmarkState == .empty)
        #expect(projection(sync: sync(status: state(value: sourceStatus(), error: .init(kind: .validation, message: "bad")))).sourceStatusState == .validationFailed(hasLastKnownGood: true))
    }

    @Test("disabled support remains orthogonal to cached benchmark health in menu overview and banner copy")
    @MainActor
    func disabledCachedDisplayState() {
        let cached = projection(sync: sync(benchmark: state(value: benchmark())))
        #expect(cached.benchmarkState == .fresh)
        #expect(cached.benchmarkPresentation.supportState == .disabled("在线来源在当前构建中未启用，显示缓存数据"))
        #expect(cached.benchmarkPresentation.healthState == nil)

        let noCache = projection(sync: sync())
        #expect(noCache.benchmarkPresentation.supportState == .disabled("在线来源在当前构建中未启用"))
        #expect(noCache.benchmarkPresentation.healthState == .empty)

        let stale = projection(sync: sync(benchmark: state(value: benchmark(), stale: true)))
        let staleOverview = OverviewView.presentation(for: stale)
        let staleMenu = MenuBarView.presentation(for: stale)
        #expect(staleOverview.supportState == .disabled("在线来源在当前构建中未启用，显示缓存数据"))
        #expect(staleOverview.healthState == .stale)
        #expect(staleMenu == staleOverview)
        #expect(StateBanner.message(for: staleOverview.healthState!, error: staleOverview.error) == "正在使用最后良好数据；数据可能已过期")

        let validationError = SegmentError(kind: .validation, message: "invalid")
        let invalid = projection(sync: sync(benchmark: state(value: benchmark(), error: validationError)))
        let invalidOverview = OverviewView.presentation(for: invalid)
        let invalidMenu = MenuBarView.presentation(for: invalid)
        #expect(invalidOverview.supportState == .disabled("在线来源在当前构建中未启用，显示缓存数据"))
        #expect(invalidOverview.healthState == .validationFailed(hasLastKnownGood: true))
        #expect(invalidOverview.error == "新数据未通过校验，已保留旧值")
        #expect(invalidMenu == invalidOverview)
        #expect(StateBanner.message(for: invalidOverview.healthState!, error: invalidOverview.error) == "新数据未通过校验，已保留旧值")

        let failed = projection(sync: sync(benchmark: state(value: benchmark())), lifecycle: .failed)
        let failedOverview = OverviewView.presentation(for: failed)
        let failedMenu = MenuBarView.presentation(for: failed)
        #expect(failedOverview.supportState == .disabled("在线来源在当前构建中未启用，显示缓存数据"))
        #expect(failedOverview.healthState == .usingLastKnownGood)
        #expect(failedOverview.error == "同步运行时不可用")
        #expect(failedMenu == failedOverview)
        #expect(StateBanner.message(for: failedOverview.healthState!, error: failedOverview.error) == "正在使用最近一次良好数据\n同步运行时不可用")

        let online = projection(sync: sync(benchmark: state(value: benchmark())), support: .experimental)
        #expect(online.benchmarkPresentation.supportState == nil)
        #expect(online.benchmarkPresentation.healthState == .fresh)
    }

    @Test("recent LKG with HTTP or runtime failure never projects fresh in enabled or disabled builds")
    @MainActor
    func recentLastKnownGoodFailureState() {
        let httpError = SegmentError(kind: .http, message: "HTTP 503")
        let enabledHTTP = projection(
            sync: sync(benchmark: state(value: benchmark(), error: httpError)),
            support: .experimental
        )
        #expect(enabledHTTP.benchmarkState == .usingLastKnownGood)
        #expect(OverviewView.presentation(for: enabledHTTP).supportState == nil)
        #expect(OverviewView.presentation(for: enabledHTTP).healthState == .usingLastKnownGood)
        #expect(MenuBarView.presentation(for: enabledHTTP) == OverviewView.presentation(for: enabledHTTP))
        #expect(StateBanner.message(for: .usingLastKnownGood, error: enabledHTTP.latestError) == "正在使用最近一次良好数据\nHTTP 503")

        let disabledHTTP = projection(sync: sync(benchmark: state(value: benchmark(), error: httpError)))
        #expect(disabledHTTP.benchmarkState == .usingLastKnownGood)
        #expect(disabledHTTP.benchmarkPresentation.supportState == .disabled("在线来源在当前构建中未启用，显示缓存数据"))
        #expect(disabledHTTP.benchmarkPresentation.healthState == .usingLastKnownGood)
        #expect(disabledHTTP.benchmarkPresentation.error == "HTTP 503")

        for support in [SupportLevel.experimental, .disabled] {
            let runtimeFailure = projection(
                sync: sync(benchmark: state(value: benchmark())),
                lifecycle: .failed,
                support: support
            )
            #expect(runtimeFailure.benchmarkState == .usingLastKnownGood)
            #expect(runtimeFailure.benchmarkPresentation.healthState == .usingLastKnownGood)
            #expect(runtimeFailure.benchmarkPresentation.error == "同步运行时不可用")
            #expect(StateBanner.message(for: .usingLastKnownGood, error: runtimeFailure.latestError) == "正在使用最近一次良好数据\n同步运行时不可用")
        }
    }

    @Test("filter and stable single-metric sorting keep nil last")
    func filteringAndSorting() {
        let models = [model("beta", "Beta", quality: 80, cost: nil), model("alpha", "Alpha", quality: 80, cost: 2), model("none", "None", quality: nil, cost: 1)]
        let projection = projection(sync: sync(benchmark: state(value: benchmark(models: models))))
        #expect(projection.filteredModels(query: "alp", sort: .quality, ascending: false).map(\.name) == ["Alpha"])
        #expect(projection.filteredModels(query: "", sort: .quality, ascending: false).map(\.name) == ["Alpha", "Beta", "None"])
        #expect(projection.filteredModels(query: "", sort: .cost, ascending: true).map(\.name) == ["None", "Alpha", "Beta"])
        #expect(projection.availableModelColumns.contains(.passRate))
        #expect(projection.availableModelColumns.contains(.agentSteps))
        #expect(projection.availableModelColumns.contains(.cache))
    }

    @Test("model columns appear only when at least one row supplies the metric")
    func dynamicModelColumns() {
        let emptyMetrics = model(
            "empty", "Empty", quality: nil, cost: nil, passed: nil, valid: nil,
            tokens: nil, elapsed: nil, steps: nil, cache: nil
        )
        let minimal = projection(sync: sync(benchmark: state(value: benchmark(models: [emptyMetrics]))))
        #expect(minimal.availableModelColumns == [.model])

        let qualityAndTokens = model(
            "partial", "Partial", quality: 42, cost: nil, passed: nil, valid: nil,
            tokens: 100, elapsed: nil, steps: nil, cache: nil
        )
        let partial = projection(sync: sync(benchmark: state(value: benchmark(models: [emptyMetrics, qualityAndTokens]))))
        #expect(partial.availableModelColumns == [.model, .quality, .tokens])

        let community = CommunityDataset(
            sourceID: .claudeCodeRadar, sourceUpdatedAt: Date(timeIntervalSince1970: 1),
            fetchedAt: Date(timeIntervalSince1970: 1),
            ratings: [.init(
                id: qualityAndTokens.id,
                model: qualityAndTokens.descriptor,
                average: 8,
                voteCount: 3,
                scaleMinimum: 1,
                scaleMaximum: 10
            )]
        )
        let withCommunity = projection(sync: sync(
            benchmark: state(value: benchmark(models: [qualityAndTokens])),
            community: state(value: community)
        ))
        #expect(withCommunity.availableModelColumns == [.model, .quality, .tokens, .community])
    }

    @Test("trend series are separated by model and revision")
    func revisionSeparatedSeries() {
        let modelID = ModelID(sourceID: .claudeCodeRadar, upstreamKey: "alpha")
        let snapshots = [
            benchmark(at: 1, revision: "r1", models: [model("alpha", "Alpha", quality: 60)]),
            benchmark(at: 2, revision: "r1", models: [model("alpha", "Alpha", quality: 61)]),
            benchmark(at: 3, revision: "r2", models: [model("alpha", "Alpha", quality: 70)]),
        ]
        let series = WorkspaceProjection.trendSeries(history: snapshots, metric: .quality, selected: [modelID])
        #expect(series.count == 2)
        #expect(series.map(\.points.count) == [2, 1])
        #expect(Set(series.map(\.seriesRevision)) == ["r1", "r2"])
        #expect(Set(series.flatMap(\.points).map(\.id)).count == 3)
        #expect(series.allSatisfy { $0.id.contains("claude-code-radar") })
    }

    @Test("trend series omit selected models with no values for the metric")
    func trendSeriesOmitEmptyMetricGroups() {
        let modelID = ModelID(sourceID: .claudeCodeRadar, upstreamKey: "empty")
        let snapshots = [
            benchmark(at: 1, revision: "r1", models: [model("empty", "Empty", quality: nil)]),
            benchmark(at: 2, revision: "r2", models: [model("empty", "Empty", quality: nil)]),
        ]

        let series = WorkspaceProjection.trendSeries(
            history: snapshots,
            metric: .quality,
            selected: [modelID]
        )

        #expect(series.isEmpty)
    }

    @Test("overview exposes a transparent exact best cost per passed task")
    func bestCostEfficiencyUsesExactDerivedMetric() {
        let exactWinnerCost = Decimal(string: "3.000000000000000003")!
        let models = [
            model("winner", "精确胜者", quality: 60, cost: exactWinnerCost, passed: 3),
            model("runner-up", "次优", quality: 90, cost: Decimal(string: "1.000000000000000002")!, passed: 1),
            model("missing", "缺失", quality: 100, cost: nil, passed: 10),
        ]
        let projection = projection(sync: sync(benchmark: state(value: benchmark(models: models))))

        let leader = projection.bestCostEfficiency

        #expect(leader?.modelID.upstreamKey == "winner")
        #expect(leader?.modelName == "精确胜者")
        #expect(leader?.costPerPassedTask == exactWinnerCost / Decimal(3))
        #expect(leader?.formula == .costPerPassedTask)
    }

    @Test("decision lens changes recommendation with the selected goal")
    func decisionLensRecommendation() {
        let quality = model("quality", "Quality", quality: 100, cost: 20, passed: 10, valid: 10, elapsed: 100)
        let value = model("value", "Value", quality: 80, cost: 2, passed: 10, valid: 10, elapsed: 80)
        let fast = model("fast", "Fast", quality: 60, cost: 5, passed: 10, valid: 10, elapsed: 10)
        let rows = [quality, value, fast].map { WorkspaceModelRow(benchmark: $0, community: nil) }

        #expect(RadarDecisionLens.recommendation(in: rows, for: .quality)?.id == quality.id)
        #expect(RadarDecisionLens.recommendation(in: rows, for: .value)?.id == value.id)
        #expect(RadarDecisionLens.recommendation(in: rows, for: .quota)?.id == value.id)
        #expect(RadarDecisionLens.recommendation(in: rows, for: .speed)?.id == fast.id)
    }

    @Test("recent performance ranks current models and compares the previous compatible snapshot")
    func recentPerformance() {
        let prior = model("alpha", "Alpha", quality: 60, cost: 10, passed: 5, valid: 5, elapsed: 50)
        let alpha = model("alpha", "Alpha", quality: 65, cost: 10, passed: 5, valid: 5, elapsed: 50)
        let beta = model("beta", "Beta", quality: 70, cost: 8, passed: 4, valid: 4, elapsed: 20)
        let rows = [alpha, beta].map { WorkspaceModelRow(benchmark: $0, community: nil) }

        let performance = RadarRecentPerformance.rows(
            current: rows,
            history: [
                benchmark(at: 1, models: [prior]),
                benchmark(at: 2, models: [alpha, beta]),
            ]
        )

        #expect(performance.map(\.id.upstreamKey) == ["beta", "alpha"])
        #expect(performance.first { $0.id == alpha.id }?.delta == 5)
        #expect(performance.first { $0.id == beta.id }?.delta == nil)
        #expect(performance.first?.costPerTask == 2)
        #expect(performance.first?.secondsPerTask == 5)
    }

    @Test("overview heatmap keeps stable keys while reading the current descriptor tier")
    func heatmapIdentityUsesCurrentDescriptorTier() {
        let opaque = model("m8", "Opus 4.8 xhigh", quality: 90)
        let sol = model("gpt-5.6-sol-max", "GPT-5.6 Sol xhigh", quality: 80)
        let unknown = model("mystery", "Mystery experimental", quality: 70)

        let rows = RadarRecentPerformance.rows(
            current: [opaque, sol, unknown].map { WorkspaceModelRow(benchmark: $0, community: nil) },
            history: []
        )

        #expect(rows.first { $0.id == opaque.id }?.family == "Opus 4.8")
        #expect(rows.first { $0.id == opaque.id }?.tier == "xhigh")
        #expect(rows.first { $0.id == sol.id }?.family == "Sol")
        #expect(rows.first { $0.id == sol.id }?.tier == "max")
        #expect(rows.first { $0.id == unknown.id }?.tier == nil)
    }

    @Test("overview surfaces an independent community refresh failure beside fresh benchmark data")
    @MainActor
    func overviewCommunityFailureIsIndependent() {
        let alpha = model("alpha", "Alpha", quality: 60)
        let community = CommunityDataset(
            sourceID: .claudeCodeRadar,
            sourceUpdatedAt: Date(timeIntervalSince1970: 1),
            fetchedAt: Date(timeIntervalSince1970: 1),
            ratings: [.init(
                id: alpha.id,
                model: alpha.descriptor,
                average: 8,
                voteCount: 3,
                scaleMinimum: 1,
                scaleMaximum: 10
            )]
        )
        let refreshError = SegmentError(kind: .http, message: "community HTTP 503")
        let projection = projection(sync: sync(
            benchmark: state(value: benchmark(models: [alpha])),
            community: state(value: community, error: refreshError)
        ))

        let presentation = OverviewView.communityPresentation(for: projection)

        #expect(projection.benchmarkState == .fresh)
        #expect(presentation?.state == .usingLastKnownGood)
        #expect(presentation?.message == "社区评分刷新失败，正在使用最近一次良好数据\ncommunity HTTP 503")
    }

    @Test("model detail history includes only the selected model and never joins revisions")
    func singleModelHistoryIsSelectedAndRevisionSafe() {
        let alpha = ModelID(sourceID: .claudeCodeRadar, upstreamKey: "alpha")
        let snapshots = [
            benchmark(at: 1, revision: "r1", models: [model("alpha", "Alpha", quality: 60), model("beta", "Beta", quality: 80)]),
            benchmark(at: 2, revision: "r1", models: [model("alpha", "Alpha", quality: 61), model("beta", "Beta", quality: 81)]),
            benchmark(at: 3, revision: "r2", models: [model("alpha", "Alpha", quality: 70), model("beta", "Beta", quality: 82)]),
        ]

        let series = WorkspaceProjection.singleModelHistory(
            history: snapshots,
            modelID: alpha,
            metric: .quality
        )

        #expect(series.count == 2)
        #expect(series.allSatisfy { $0.modelID == alpha })
        #expect(Set(series.map(\.seriesRevision)) == ["r1", "r2"])
        #expect(series.map(\.points.count) == [2, 1])
    }

    @Test("trend time range filters snapshots before grouping and never bridges revisions")
    func trendTimeRangePreservesRevisionBoundaries() {
        let day: TimeInterval = 86_400
        let alpha = ModelID(sourceID: .claudeCodeRadar, upstreamKey: "alpha")
        let snapshots = [
            benchmark(at: 0, revision: "r1", models: [model("alpha", "Alpha", quality: 50)]),
            benchmark(at: day * 3, revision: "r1", models: [model("alpha", "Alpha", quality: 60)]),
            benchmark(at: day * 7, revision: "r2", models: [model("alpha", "Alpha", quality: 70)]),
            benchmark(at: day * 8, revision: "r2", models: [model("alpha", "Alpha", quality: 71)]),
        ]

        let series = WorkspaceProjection.trendSeries(
            history: snapshots,
            metric: .quality,
            selected: [alpha],
            timeRange: .lastSevenDays
        )

        #expect(Set(series.map(\.seriesRevision)) == ["r1", "r2"])
        #expect(series.map(\.points.count) == [1, 2])
        #expect(series.flatMap(\.points).map(\.date).min() == Date(timeIntervalSince1970: day * 3))
    }

    @Test("48 hour trend range is inclusive and drops older snapshots")
    func fortyEightHourTrendRange() {
        let hour: TimeInterval = 3_600
        let epsilon: TimeInterval = 0.001
        let alpha = ModelID(sourceID: .claudeCodeRadar, upstreamKey: "alpha")
        let snapshots = [
            benchmark(at: 0, models: [model("alpha", "Alpha", quality: 49)]),
            benchmark(at: hour - epsilon, models: [model("alpha", "Alpha", quality: 49.5)]),
            benchmark(at: hour, models: [model("alpha", "Alpha", quality: 50)]),
            benchmark(at: 25 * hour, models: [model("alpha", "Alpha", quality: 60)]),
            benchmark(at: 49 * hour, models: [model("alpha", "Alpha", quality: 70)]),
        ]

        let points = WorkspaceProjection.trendSeries(
            history: snapshots,
            metric: .quality,
            selected: [alpha],
            timeRange: .lastTwoDays
        ).flatMap(\.points)

        #expect(points.map(\.date) == [
            Date(timeIntervalSince1970: hour),
            Date(timeIntervalSince1970: 25 * hour),
            Date(timeIntervalSince1970: 49 * hour),
        ])
    }

    @Test("all six historical metrics preserve missing values as gaps")
    func allHistoricalMetricsPreserveGaps() {
        let alpha = ModelID(sourceID: .claudeCodeRadar, upstreamKey: "alpha")
        let complete = model(
            "alpha",
            "Alpha",
            quality: 8,
            cost: 7,
            tokens: 123,
            elapsed: 4,
            steps: 5,
            cache: 6
        )
        let missing = model(
            "alpha",
            "Alpha",
            quality: nil,
            cost: nil,
            tokens: nil,
            elapsed: nil,
            steps: nil,
            cache: nil
        )
        let history = [
            benchmark(at: 1, models: [complete]),
            benchmark(at: 2, models: [missing]),
            benchmark(at: 3, models: [complete]),
        ]
        let expected: [TrendMetric: Double] = [
            .quality: 8,
            .cost: 7,
            .elapsed: 4,
            .agentSteps: 5,
            .cache: 6,
            .tokens: 123,
        ]

        for metric in TrendMetric.allCases {
            let expectedValue = expected[metric] ?? .nan
            let points = WorkspaceProjection.trendSeries(
                history: history,
                metric: metric,
                selected: [alpha]
            ).flatMap(\.points)
            #expect(points.count == 2)
            #expect(points.map(\.date) == [
                Date(timeIntervalSince1970: 1),
                Date(timeIntervalSince1970: 3),
            ])
            #expect(points.map(\.value) == [expectedValue, expectedValue])
            #expect(points.map(\.segmentIndex) == [0, 1])
        }
    }

    @Test("local decline signals include exact threshold and suppress just below it")
    func localDeclineThreshold() {
        let hour: TimeInterval = 3_600
        let qualifying = [
            benchmark(at: 0, revision: "r1", models: [
                model("alpha", "Same", quality: 100),
                model("beta", "Same", quality: 100),
            ]),
            benchmark(at: 12 * hour, revision: "r1", models: [
                model("alpha", "Same", quality: 99),
                model("beta", "Same", quality: 99),
            ]),
            benchmark(at: 24 * hour, revision: "r1", models: [
                model("alpha", "Same", quality: 98),
                model("beta", "Same", quality: Decimal(string: "98.0000001")!),
            ]),
        ]

        let signals = RadarDeclineAnalysis.signals(
            history: qualifying,
            sourceID: .claudeCodeRadar
        )

        #expect(signals.count == 1)
        #expect(signals.first?.modelID.upstreamKey == "alpha")
        #expect(signals.first?.drop24Hours == Decimal(string: "2.0")!)
        #expect(signals.first?.drop12Hours == 1)
    }

    @Test("local decline signals use predecessor windows within inclusive six hour tolerance")
    func localDeclineTolerance() {
        let hour: TimeInterval = 3_600
        let epsilon: TimeInterval = 0.001
        let history = [
            benchmark(at: -epsilon, models: [
                model("outside", "Outside", quality: 100),
            ]),
            benchmark(at: 0, models: [
                model("exact", "Exact", quality: 100),
            ]),
            benchmark(at: 12 * hour, models: [
                model("exact", "Exact", quality: 99),
                model("outside", "Outside", quality: 99),
            ]),
            benchmark(at: 30 * hour, models: [
                model("exact", "Exact", quality: 97),
                model("outside", "Outside", quality: 97),
            ]),
        ]

        let signals = RadarDeclineAnalysis.signals(history: history, sourceID: .claudeCodeRadar)

        #expect(signals.map(\.modelID.upstreamKey) == ["exact"])
    }

    @Test("local decline signals require three unique points and suppress equal-time conflicts")
    func localDeclineEqualTimeHandling() {
        let hour: TimeInterval = 3_600
        let twoPoints = [
            benchmark(at: 0, models: [model("alpha", "Alpha", quality: 100)]),
            benchmark(at: 24 * hour, models: [model("alpha", "Alpha", quality: 98)]),
        ]
        #expect(RadarDeclineAnalysis.signals(
            history: twoPoints,
            sourceID: .claudeCodeRadar
        ).isEmpty)

        let unique = [
            benchmark(at: 0, models: [model("alpha", "Alpha", quality: 100)]),
            benchmark(at: 12 * hour, models: [model("alpha", "Alpha", quality: 99)]),
            benchmark(at: 24 * hour, models: [model("alpha", "Alpha", quality: 98)]),
        ]
        #expect(RadarDeclineAnalysis.signals(
            history: unique + [unique[1]],
            sourceID: .claudeCodeRadar
        ).count == 1)

        let conflict = benchmark(
            at: 12 * hour,
            models: [model("alpha", "Alpha", quality: 80)]
        )
        #expect(RadarDeclineAnalysis.signals(
            history: unique + [conflict],
            sourceID: .claudeCodeRadar
        ).isEmpty)
    }

    @Test("local decline signals isolate source model and revision with deterministic custom limits")
    func localDeclineIsolationAndOrdering() {
        let hour: TimeInterval = 3_600
        let sourceMismatch = ModelID(sourceID: .sweBenchVerified, upstreamKey: "foreign")
        let history = [
            benchmark(at: 0, revision: "r1", models: [
                model("z", "Same", quality: 100),
                model("a", "Same", quality: 100),
                model(sourceMismatch, "Foreign", quality: 100),
            ]),
            benchmark(at: 12 * hour, revision: "r1", models: [
                model("z", "Same", quality: 99),
                model("a", "Same", quality: 99),
                model(sourceMismatch, "Foreign", quality: 99),
            ]),
            benchmark(at: 24 * hour, revision: "r1", models: [
                model("z", "Same", quality: 98),
                model("a", "Same", quality: 98),
                model(sourceMismatch, "Foreign", quality: 98),
            ]),
        ]

        #expect(RadarDeclineAnalysis.signals(
            history: history,
            sourceID: .claudeCodeRadar,
            limit: 1
        ).map(\.modelID.upstreamKey) == ["a"])
        #expect(RadarDeclineAnalysis.signals(
            history: history,
            sourceID: .claudeCodeRadar,
            limit: 0
        ).isEmpty)
        #expect(RadarDeclineAnalysis.signals(
            history: history,
            sourceID: .sweBenchVerified
        ).isEmpty)

        let splitRevision = [
            benchmark(at: 0, revision: "r1", models: [model("alpha", "Alpha", quality: 100)]),
            benchmark(at: 12 * hour, revision: "r1", models: [model("alpha", "Alpha", quality: 99)]),
            benchmark(at: 24 * hour, revision: "r2", models: [model("alpha", "Alpha", quality: 80)]),
        ]
        #expect(RadarDeclineAnalysis.signals(
            history: splitRevision,
            sourceID: .claudeCodeRadar
        ).isEmpty)
    }

    @Test("local insight projection is available only for fresh benchmark state")
    func localInsightsRequireFreshBenchmark() {
        let hour: TimeInterval = 3_600
        let models = [model("alpha", "Alpha", quality: 98, cost: 1, valid: 1, elapsed: 60)]
        let history = [
            benchmark(at: 0, models: [model("alpha", "Alpha", quality: 100)]),
            benchmark(at: 12 * hour, models: [model("alpha", "Alpha", quality: 99)]),
            benchmark(at: 24 * hour, models: models),
        ]
        let dataset = benchmark(at: 24 * hour, models: models)
        let fresh = projection(sync: sync(benchmark: state(value: dataset)))
        let stale = projection(sync: sync(benchmark: state(value: dataset, stale: true)))
        let lkg = projection(sync: sync(benchmark: state(
            value: dataset,
            error: SegmentError(kind: .http, message: "offline")
        )))
        let failed = projection(sync: sync(benchmark: state(value: dataset)), lifecycle: .failed)

        #expect(fresh.intelligenceEfficiency.count == 1)
        #expect(fresh.localDeclineSignals(history: history).count == 1)
        for suppressed in [stale, lkg, failed] {
            #expect(suppressed.intelligenceEfficiency.isEmpty)
            #expect(suppressed.localDeclineSignals(history: history).isEmpty)
        }
    }

    @Test("trend axis pads edge timestamps so localized labels remain readable")
    func trendAxisPadsEdgeTimestamps() {
        let dates = [
            Date(timeIntervalSince1970: 3_600),
            Date(timeIntervalSince1970: 10_800),
        ]

        let domain = TrendChartDomain.padded(dates)

        #expect(domain?.lowerBound == Date(timeIntervalSince1970: 0))
        #expect(domain?.upperBound == Date(timeIntervalSince1970: 14_400))
    }

    @Test("renamed model remains one stable trend series per revision")
    func renamedModelStableSeries() {
        let modelID = ModelID(sourceID: .claudeCodeRadar, upstreamKey: "alpha")
        let snapshots = [
            benchmark(at: 1, revision: "r1", models: [model("alpha", "Zulu Name", quality: 60)]),
            benchmark(at: 2, revision: "r1", models: [model("alpha", "Alpha Name", quality: 61)]),
        ]
        let series = WorkspaceProjection.trendSeries(history: snapshots, metric: .quality, selected: [modelID])
        #expect(series.count == 1)
        #expect(series[0].id == "claude-code-radar|alpha|r1")
        #expect(series[0].modelName == "Alpha Name")
        #expect(series[0].points.count == 2)
    }

    @Test("public support overrides an experimental source descriptor")
    func publicSupportWins() {
        let sourceProjection = RadarSyncProjection(supportLevel: .experimental, benchmark: state(value: benchmark()), community: state(), sourceStatus: state())
        #expect(projection(sync: sourceProjection, support: .disabled).supportState == .disabled("在线来源在当前构建中未启用"))
        #expect(projection(sync: sourceProjection, support: .experimental).supportState == .fresh)
    }

    @Test("stable ties use display name then upstream key")
    func stableTieBreak() {
        let sameName = [model("z", "Same", quality: 10), model("a", "Same", quality: 10)]
        let rows = projection(sync: sync(benchmark: state(value: benchmark(models: sameName))))
            .filteredModels(query: "", sort: .quality, ascending: false)
        #expect(rows.map(\.id.upstreamKey) == ["a", "z"])

        let nilRows = [
            model("z", "Same", quality: nil, cost: nil),
            model("a", "Same", quality: nil, cost: nil),
            model("b", "Before", quality: nil, cost: nil),
        ]
        let nilSorted = projection(sync: sync(benchmark: state(value: benchmark(models: nilRows))))
            .filteredModels(query: "", sort: .quality, ascending: false)
        #expect(nilSorted.map(\.id.upstreamKey) == ["b", "a", "z"])
    }

    @Test("quality and cost sorting preserve exact Decimal ordering")
    func exactDecimalSorting() {
        let lower = Decimal(string: "0.123456789012345678")!
        let higher = Decimal(string: "0.123456789012345679")!
        let rows = [
            model("low", "Zulu", quality: lower, cost: lower),
            model("high", "Alpha", quality: higher, cost: higher),
        ]
        let projection = projection(sync: sync(benchmark: state(value: benchmark(models: rows))))
        #expect(projection.filteredModels(query: "", sort: .quality, ascending: true).map(\.id.upstreamKey) == ["low", "high"])
        #expect(projection.filteredModels(query: "", sort: .quality, ascending: false).map(\.id.upstreamKey) == ["high", "low"])
        #expect(projection.filteredModels(query: "", sort: .cost, ascending: true).map(\.id.upstreamKey) == ["low", "high"])
    }


    @Test("validation copy distinguishes retained LKG from no available old value")
    func validationCopyMatchesLKGAvailability() {
        let error = SegmentError(kind: .validation, message: "invalid")
        let retained = projection(sync: sync(benchmark: state(value: benchmark(), error: error)))
        #expect(retained.latestError == "新数据未通过校验，已保留旧值")

        let unavailable = projection(sync: sync(benchmark: state(error: error)))
        #expect(unavailable.benchmarkState == .validationFailed(hasLastKnownGood: false))
        #expect(unavailable.latestError == "新数据未通过校验，暂无可用旧值")
    }

    @Test("trend selection initializes after async data and preserves a valid user choice")
    func trendSelectionReconciliation() {
        let alpha = model("alpha", "Alpha", quality: 1)
        let beta = model("beta", "Beta", quality: 2)
        let rows = projection(sync: sync(benchmark: state(value: benchmark(models: [beta, alpha])))).rows

        var selection = TrendSelectionState()
        selection = TrendSelection.reconcile(state: selection, rows: rows, history: [])
        #expect(selection.selected.isEmpty)
        #expect(selection.hasInitializedSelection == false)

        let history = [benchmark(models: [beta, alpha])]
        selection = TrendSelection.reconcile(state: selection, rows: rows, history: history)
        #expect(selection.selected == [alpha.id])
        #expect(selection.hasInitializedSelection)

        selection = TrendSelection.userChanged(selection, selected: [beta.id])
        selection = TrendSelection.reconcile(state: selection, rows: rows, history: history)
        #expect(selection.selected == [beta.id])

        selection = TrendSelection.reconcile(state: selection, rows: [WorkspaceModelRow(benchmark: alpha, community: nil)], history: [benchmark(models: [alpha])])
        #expect(selection.selected.isEmpty)
        #expect(selection.hasInitializedSelection)

        selection = TrendSelection.userChanged(selection, selected: [])
        let newRows = projection(sync: sync(benchmark: state(value: benchmark(models: [alpha, beta])))).rows
        selection = TrendSelection.reconcile(state: selection, rows: newRows, history: [benchmark(models: [alpha, beta])])
        #expect(selection.selected.isEmpty)
        #expect(selection.hasInitializedSelection)
    }

    @Test("menu exposes refresh open and quit while close is non-terminating")
    func lifecycleActions() {
        #expect(MenuBarAction.allCases == [.refresh, .openWorkspace, .quit])
        #expect(AppLifecycleAction.closeWorkspace.terminatesProcess == false)
        #expect(AppLifecycleAction.quit.terminatesProcess == true)
    }

    @Test("refresh remains visible but is disabled for unsupported builds")
    func refreshActionAvailability() {
        #expect(MenuBarAction.allCases.contains(.refresh))
        #expect(RefreshActionAvailability.isEnabled(supportLevel: .disabled) == false)
        #expect(RefreshActionAvailability.isEnabled(supportLevel: .experimental))
    }

    @Test("close workspace targets the focused singleton window without matching its destination title")
    @MainActor
    func closeWorkspaceIgnoresDestinationTitle() {
        let exportWindow = NSWindow()
        exportWindow.title = "导出"

        #expect(WorkspaceWindowActions.closeTarget(from: exportWindow) === exportWindow)
        #expect(WorkspaceWindowActions.closeTarget(from: nil) == nil)
    }

    private func sync(
        benchmark: SegmentState<BenchmarkDataset>? = nil,
        community: SegmentState<CommunityDataset>? = nil,
        status: SegmentState<SourceStatusDataset>? = nil
    ) -> RadarSyncProjection {
        RadarSyncProjection(
            supportLevel: .disabled,
            benchmark: benchmark ?? state(),
            community: community ?? state(),
            sourceStatus: status ?? state()
        )
    }

    private func state<T: Sendable>(value: T? = nil, error: SegmentError? = nil, stale: Bool = false) -> SegmentState<T> {
        SegmentState(value: value, lastSuccessfulAt: value == nil ? nil : Date(timeIntervalSince1970: 1), lastAttemptedAt: nil, error: error, isStale: stale)
    }

    private func projection(sync: RadarSyncProjection?, lifecycle: RadarAppLifecycleState = .running, support: SupportLevel = .disabled) -> WorkspaceProjection {
        WorkspaceProjection(sync: sync, lifecycle: lifecycle, supportLevel: support)
    }

    private func benchmark(at: TimeInterval = 1, revision: String = "r1", models: [ModelBenchmark]? = nil) -> BenchmarkDataset {
        BenchmarkDataset(sourceID: .claudeCodeRadar, sourceUpdatedAt: Date(timeIntervalSince1970: at), fetchedAt: Date(timeIntervalSince1970: at), benchmarkName: "Fixture", benchmarkVersion: "1", seriesRevision: revision, models: models ?? [model("alpha", "Alpha", quality: 60)])
    }

    private func model(
        _ key: String,
        _ name: String,
        quality: Decimal?,
        cost: Decimal? = nil,
        passed: Int? = 1,
        valid: Int? = 2,
        tokens: Int64? = nil,
        elapsed: Double? = nil,
        steps: Int? = 2,
        cache: Decimal? = 50
    ) -> ModelBenchmark {
        let id = ModelID(sourceID: .claudeCodeRadar, upstreamKey: key)
        return ModelBenchmark(id: id, descriptor: .init(id: id, upstreamName: name, displayName: name), qualityScore: quality, passedTasks: passed, validTasks: valid, invalidTasks: nil, benchmarkCostUSD: cost, inputTokens: nil, outputTokens: nil, cacheReadTokens: nil, cacheCreationTokens: nil, totalTokens: tokens, elapsedSeconds: elapsed, agentSteps: steps, cacheHitPercent: cache)
    }

    private func model(
        _ id: ModelID,
        _ name: String,
        quality: Decimal?
    ) -> ModelBenchmark {
        ModelBenchmark(
            id: id,
            descriptor: .init(id: id, upstreamName: name, displayName: name),
            qualityScore: quality,
            passedTasks: 1,
            validTasks: 1,
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


    private func sourceStatus() -> SourceStatusDataset {
        .init(sourceID: .claudeCodeRadar, sourceUpdatedAt: Date(timeIntervalSince1970: 1), fetchedAt: Date(timeIntervalSince1970: 1), quotaEstimates: [])
    }
}
