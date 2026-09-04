import Foundation
import Testing
@testable import AIRadar

@Suite("CodexRenderedWarningProjectionTests")
struct CodexRenderedWarningProjectionTests {
    @Test("official projection distinguishes all six states")
    func sixStates() {
        let snapshot = warning()
        let error = SegmentError(kind: .network, message: "render unavailable")

        #expect(CodexRenderedWarningPresentation.State.allCases.count == 6)
        #expect(presentation(state: nil)?.state == .loading)
        #expect(presentation(state: segment(value: snapshot))?.state == .freshCards)
        #expect(presentation(state: segment(value: warning(cards: [])))?.state == .freshEmpty)
        #expect(presentation(state: segment(value: snapshot, stale: true))?.state == .staleLastKnownGood)
        #expect(presentation(state: segment(error: error), history: [snapshot])?.state == .lastKnownGoodWithError)
        #expect(presentation(state: segment(error: error))?.state == .errorWithoutLastKnownGood)
    }

    @Test("official projection is Codex-only")
    func sourceGating() {
        let warningState = segment(value: warning())

        for sourceID in [RadarSourceID.claudeCodeRadar, .sweBenchVerified] {
            let projection = workspace(sourceID: sourceID, warningState: warningState)
            #expect(projection.renderedWarningPresentation == nil)
        }

        let codex = workspace(sourceID: .codexRadar, warningState: warningState)
        #expect(codex.renderedWarningPresentation != nil)
    }

    @Test("official state stays visible when benchmark rows are empty")
    func visibleWithEmptyBenchmarks() {
        let projection = workspace(
            sourceID: .codexRadar,
            warningState: segment(value: warning())
        )

        #expect(projection.rows.isEmpty)
        #expect(projection.renderedWarningPresentation?.state == .freshCards)
    }

    @Test("official cards do not replace or join the independent local fit")
    func localFitRemainsIndependent() {
        let hour: TimeInterval = 3_600
        let history = [
            benchmark(at: 0, quality: 100),
            benchmark(at: 12 * hour, quality: 99),
            benchmark(at: 24 * hour, quality: 98),
        ]
        let projection = workspace(
            sourceID: .codexRadar,
            warningState: segment(value: warning()),
            benchmarkState: segment(value: history.last!)
        )

        #expect(projection.renderedWarningPresentation?.cards.first?.displayName == "GPT-5 High")
        #expect(projection.localDeclineSignals(history: history).map(\.modelName) == ["Local-only model"])
    }

    @Test("cards preserve upstream order, family effort values, and missing 48h")
    func cardContract() {
        let cards = [
            CodexRenderedWarningCard(
                displayName: "Second upstream",
                family: "gpt-5.6",
                effort: "xhigh",
                sourceOrder: 2,
                iq: 88.5,
                drop24h: 2.25,
                drop48h: nil
            ),
            CodexRenderedWarningCard(
                displayName: "First key",
                family: "gpt-5.5",
                effort: "high",
                sourceOrder: 0,
                iq: 81,
                drop24h: 4,
                drop48h: 6.5
            ),
        ]

        let projected = presentation(state: segment(value: warning(cards: cards)))

        #expect(projected?.cards == cards)
        #expect(projected?.cards.map(\.sourceOrder) == [2, 0])
        #expect(projected?.cards[0].family == "gpt-5.6")
        #expect(projected?.cards[0].effort == "xhigh")
        #expect(projected?.cards[0].drop48h == nil)
        #expect(projected?.cardAccessibilityLabel(projected!.cards[0]).contains("48 小时") == false)
        #expect(projected?.cardAccessibilityLabel(projected!.cards[0]).contains("12 小时") == false)
        #expect(projected?.cardAccessibilityLabel(projected!.cards[1]).contains("48 小时下降 6.5") == true)
    }

    @Test("source and capture times plus exact attribution survive LKG fallback")
    func provenanceAndTimestamps() {
        let capturedAt = Date(timeIntervalSince1970: 1_721_234_567)
        let snapshot = warning(
            sourceTimeLabel: "3 小时前",
            capturedAt: capturedAt
        )
        let projected = presentation(
            state: segment(error: SegmentError(kind: .validation, message: "schema drift")),
            history: [snapshot]
        )

        #expect(projected?.state == .lastKnownGoodWithError)
        #expect(projected?.sourceTimeLabel == "3 小时前")
        #expect(projected?.capturedAt == capturedAt)
        #expect(projected?.attribution == "数据来自 Codex 雷达 codexradar.com")
        #expect(projected?.sourceTimeAccessibilityIdentifier == "codex-rendered-warning-source-time")
        #expect(projected?.capturedAtAccessibilityIdentifier == "codex-rendered-warning-captured-at")
        #expect(projected?.sourceTimeAccessibilityLabel == "官网时间：3 小时前")
        #expect(projected?.capturedAtAccessibilityLabel.contains(capturedAt.ISO8601Format()) == true)
        let cardLabel = projected!.cardAccessibilityLabel(projected!.cards[0])
        #expect(cardLabel.contains(projected!.stateMessage))
        #expect(cardLabel.contains("schema drift"))
        #expect(cardLabel.contains(projected!.sourceTimeAccessibilityLabel))
        #expect(cardLabel.contains(projected!.capturedAtAccessibilityLabel))
        #expect(cardLabel.contains(projected!.attribution))
    }

    @Test("section state and cards expose stable accessibility semantics")
    func accessibilityContract() {
        let projected = presentation(state: segment(value: warning()))
        let card = projected!.cards[0]

        #expect(projected?.sectionAccessibilityIdentifier == "codex-rendered-warning-section")
        #expect(projected?.stateAccessibilityIdentifier == "codex-rendered-warning-state-fresh-cards")
        #expect(projected?.cardAccessibilityIdentifier(card) == "codex-rendered-warning-card-0")
        #expect(projected?.sectionAccessibilityLabel.contains("codexradar.com") == true)
        #expect(projected?.stateAccessibilityLabel.isEmpty == false)
        #expect(projected?.cardAccessibilityLabel(card).contains("IQ 80") == true)
        #expect(projected?.cardAccessibilityLabel(card).contains("24 小时下降 3") == true)
        #expect(projected?.cardAccessibilityLabel(card).contains(projected!.stateMessage) == true)
        #expect(projected?.cardAccessibilityLabel(card).contains("官网时间：刚刚") == true)
        #expect(projected?.cardAccessibilityLabel(card).contains(
            "本地采集时间：\(projected!.capturedAt!.ISO8601Format())"
        ) == true)
        #expect(projected?.cardAccessibilityLabel(card).contains("codexradar.com") == true)
    }

    private func presentation(
        state: SegmentState<CodexRenderedWarningSnapshot>?,
        history: [CodexRenderedWarningSnapshot] = []
    ) -> CodexRenderedWarningPresentation? {
        CodexRenderedWarningPresentation(
            sourceID: .codexRadar,
            state: state,
            history: history
        )
    }

    private func workspace(
        sourceID: RadarSourceID,
        warningState: SegmentState<CodexRenderedWarningSnapshot>,
        benchmarkState: SegmentState<BenchmarkDataset>? = nil
    ) -> WorkspaceProjection {
        let descriptor: RadarSourceDescriptor = switch sourceID {
        case .codexRadar: CodexRadarConfiguration.descriptor
        case .sweBenchVerified: SWEBenchConfiguration.descriptor
        default: ClaudeRadarConfiguration.descriptor
        }
        return WorkspaceProjection(
            sync: RadarSyncProjection(
                supportLevel: .authorized,
                benchmark: benchmarkState ?? segment(),
                community: segment() as SegmentState<CommunityDataset>,
                sourceStatus: segment() as SegmentState<SourceStatusDataset>
            ),
            lifecycle: .running,
            supportLevel: .authorized,
            source: descriptor,
            renderedWarningState: warningState,
            renderedWarningHistory: warningState.value.map { [$0] } ?? []
        )
    }

    private func benchmark(at time: TimeInterval, quality: Decimal) -> BenchmarkDataset {
        let id = ModelID(sourceID: .codexRadar, upstreamKey: "local-only")
        let model = ModelBenchmark(
            id: id,
            descriptor: ModelDescriptor(
                id: id,
                upstreamName: "Local-only model",
                displayName: "Local-only model"
            ),
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
        let date = Date(timeIntervalSince1970: time)
        return BenchmarkDataset(
            sourceID: .codexRadar,
            sourceUpdatedAt: date,
            fetchedAt: date,
            benchmarkName: "Fixture",
            benchmarkVersion: "1",
            seriesRevision: "r1",
            models: [model]
        )
    }

    private func segment<T: Sendable>(
        value: T? = nil,
        error: SegmentError? = nil,
        stale: Bool = false
    ) -> SegmentState<T> {
        SegmentState(
            value: value,
            lastSuccessfulAt: value.map { _ in Date(timeIntervalSince1970: 100) },
            lastAttemptedAt: Date(timeIntervalSince1970: 200),
            error: error,
            isStale: stale
        )
    }

    private func warning(
        cards: [CodexRenderedWarningCard]? = nil,
        sourceTimeLabel: String = "刚刚",
        capturedAt: Date = Date(timeIntervalSince1970: 100)
    ) -> CodexRenderedWarningSnapshot {
        CodexRenderedWarningSnapshot(
            sourceID: .codexRadar,
            parserRevision: CodexRenderedWarningDOMParser.parserRevision,
            finalOrigin: "https://codexradar.com",
            sourceTimeLabel: sourceTimeLabel,
            capturedAt: capturedAt,
            cards: cards ?? [
                CodexRenderedWarningCard(
                    displayName: "GPT-5 High",
                    family: "gpt-5",
                    effort: "high",
                    sourceOrder: 0,
                    iq: 80,
                    drop24h: 3,
                    drop48h: nil
                ),
            ],
            semanticFingerprint: "fixture"
        )
    }
}
