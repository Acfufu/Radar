import Foundation
import Testing
@testable import AIRadar

@Suite("WorkspacePresentationContractTests")
struct WorkspacePresentationContractTests {
    @Test("quality vocabulary, units, availability, and accessibility stay source-local")
    func metricDescriptors() {
        let claude = WorkspacePresentation.metric(for: .claudeCodeRadar)
        let codex = WorkspacePresentation.metric(for: .codexRadar)
        let swe = WorkspacePresentation.metric(for: .sweBenchVerified)

        #expect(claude.qualityLabel == "IQ")
        #expect(codex.qualityLabel == "IQ")
        #expect(swe.qualityLabel == "% Resolved")
        #expect(claude.qualityUnit == "")
        #expect(codex.qualityUnit == "")
        #expect(swe.qualityUnit == "%")
        #expect(claude.unavailableValue == "未发布")
        #expect(codex.unavailableValue == "未发布")
        #expect(swe.unavailableValue == "未发布")
        #expect(claude.accessibilityLabel == "质量 IQ")
        #expect(codex.accessibilityLabel == "质量 IQ")
        #expect(swe.accessibilityLabel == "已解决比例 % Resolved")
        #expect(claude.formattedQuality(Decimal(91)) == "91")
        #expect(codex.accessibilityValue(Decimal(91)) == "质量 IQ：91")
        #expect(swe.formattedQuality(Decimal(91)) == "91%")
        #expect(swe.accessibilityValue(Decimal(91)) == "已解决比例 % Resolved：91%")
        #expect(swe.title(for: .quality) == "% Resolved")
        #expect(claude.title(for: .quality) == "IQ")
        #expect(codex.title(for: .cost) == "费用")
    }

    @Test("existing benchmark precedence passes through presentation unchanged")
    @MainActor
    func benchmarkStatePrecedence() {
        let validation = SegmentError(kind: .validation, message: "<b>invalid</b>")
        let http = SegmentError(kind: .http, message: "HTTP <strong>503</strong>")
        let cases: [(String, WorkspaceProjection, BenchmarkPresentation)] = [
            ("validation", projection(benchmark: segment(value: benchmark(), error: validation), lifecycle: .failed), .init(supportState: nil, healthState: .validationFailed(hasLastKnownGood: true), error: "新数据未通过校验，已保留旧值")),
            ("lifecycle LKG", projection(benchmark: segment(value: benchmark()), lifecycle: .failed), .init(supportState: nil, healthState: .usingLastKnownGood, error: "同步运行时不可用")),
            ("segment LKG", projection(benchmark: segment(value: benchmark(), error: http)), .init(supportState: nil, healthState: .usingLastKnownGood, error: "HTTP 503")),
            ("error", projection(benchmark: segment(error: http)), .init(supportState: nil, healthState: .error("HTTP 503"), error: "HTTP 503")),
            ("loading", projection(lifecycle: .starting), .init(supportState: nil, healthState: .loading, error: nil)),
            ("empty", projection(), .init(supportState: nil, healthState: .empty, error: nil)),
            ("stale", projection(benchmark: segment(value: benchmark(), stale: true)), .init(supportState: nil, healthState: .stale, error: nil)),
            ("fresh", projection(benchmark: segment(value: benchmark())), .init(supportState: nil, healthState: .fresh, error: nil)),
            ("disabled", projection(benchmark: segment(value: benchmark(), error: http), support: .disabled), .init(supportState: .disabled("在线来源在当前构建中未启用，显示缓存数据"), healthState: .usingLastKnownGood, error: "HTTP 503")),
        ]

        for (name, workspace, expected) in cases {
            let actual = WorkspacePresentation.benchmark(for: workspace)
            #expect(actual == expected, "\(name) must retain the projection precedence")
        }

        let error = WorkspacePresentation.benchmark(for: projection(benchmark: segment(error: http)))
        #expect(WorkspacePresentation.bannerMessage(for: error.healthState!, error: error.error) == "HTTP 503")
    }

    private func projection(
        benchmark: SegmentState<BenchmarkDataset>? = nil,
        lifecycle: RadarAppLifecycleState = .running,
        support: SupportLevel = .authorized
    ) -> WorkspaceProjection {
        let sync = benchmark.map {
            RadarSyncProjection(
                supportLevel: support,
                benchmark: $0,
                community: segment(),
                sourceStatus: segment()
            )
        }
        return WorkspaceProjection(sync: sync, lifecycle: lifecycle, supportLevel: support)
    }

    private func segment<T: Sendable>(
        value: T? = nil,
        error: SegmentError? = nil,
        stale: Bool = false
    ) -> SegmentState<T> {
        .init(
            value: value,
            lastSuccessfulAt: value == nil ? nil : Date(timeIntervalSince1970: 1),
            lastAttemptedAt: nil,
            error: error,
            isStale: stale
        )
    }

    private func benchmark() -> BenchmarkDataset {
        .init(
            sourceID: .claudeCodeRadar,
            sourceUpdatedAt: Date(timeIntervalSince1970: 1),
            fetchedAt: Date(timeIntervalSince1970: 1),
            benchmarkName: "Fixture",
            benchmarkVersion: "1",
            seriesRevision: "r1",
            models: []
        )
    }
}
