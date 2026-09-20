import Foundation

struct CodexRenderedWarningPresentation: Equatable, Sendable {
    enum State: String, CaseIterable, Equatable, Sendable {
        case loading
        case freshCards = "fresh-cards"
        case freshEmpty = "fresh-empty"
        case staleLastKnownGood = "stale-last-known-good"
        case lastKnownGoodWithError = "last-known-good-with-error"
        case errorWithoutLastKnownGood = "error-without-last-known-good"
    }

    let state: State
    let cards: [CodexRenderedWarningCard]
    let sourceTimeLabel: String?
    let capturedAt: Date?
    let errorMessage: String?

    let attribution = CodexRadarConfiguration.descriptor.attributionText
    let sectionAccessibilityIdentifier = "codex-rendered-warning-section"
    let sourceTimeAccessibilityIdentifier = "codex-rendered-warning-source-time"
    let capturedAtAccessibilityIdentifier = "codex-rendered-warning-captured-at"

    init?(
        sourceID: RadarSourceID,
        state: SegmentState<CodexRenderedWarningSnapshot>?,
        history: [CodexRenderedWarningSnapshot]
    ) {
        guard sourceID == .codexRadar else { return nil }

        let snapshot: CodexRenderedWarningSnapshot?
        let presentationState: State
        if let error = state?.error {
            snapshot = state?.value ?? history.last
            presentationState = snapshot == nil ? .errorWithoutLastKnownGood : .lastKnownGoodWithError
            errorMessage = safe(error.message)
        } else if let current = state?.value {
            snapshot = current
            if state?.isStale == true {
                presentationState = .staleLastKnownGood
            } else {
                presentationState = current.cards.isEmpty ? .freshEmpty : .freshCards
            }
            errorMessage = nil
        } else if let lastKnownGood = history.last, state != nil {
            snapshot = lastKnownGood
            presentationState = .staleLastKnownGood
            errorMessage = nil
        } else {
            snapshot = nil
            presentationState = .loading
            errorMessage = nil
        }

        self.state = presentationState
        cards = snapshot?.cards ?? []
        sourceTimeLabel = snapshot?.sourceTimeLabel
        capturedAt = snapshot?.capturedAt
    }

    var stateMessage: String {
        switch state {
        case .loading: "正在读取 Codex Radar 官网降智预警"
        case .freshCards: "官网降智预警已更新"
        case .freshEmpty: "官网当前未显示降智预警"
        case .staleLastKnownGood: "正在显示可能已过期的最近有效官网数据"
        case .lastKnownGoodWithError: "官网预警刷新失败，正在显示最近有效数据"
        case .errorWithoutLastKnownGood: "官网预警暂不可用"
        }
    }

    var sectionAccessibilityLabel: String {
        "Codex Radar 官网降智预警，\(attribution)"
    }

    var stateAccessibilityIdentifier: String {
        "codex-rendered-warning-state-\(state.rawValue)"
    }

    var stateAccessibilityLabel: String {
        [stateMessage, errorMessage].compactMap { $0 }.joined(separator: "：")
    }

    var sourceTimeAccessibilityLabel: String {
        "官网时间：\(sourceTimeLabel ?? "暂无")"
    }

    var capturedAtAccessibilityLabel: String {
        "本地采集时间：\(capturedAt?.ISO8601Format() ?? "暂无")"
    }

    func cardAccessibilityIdentifier(_ card: CodexRenderedWarningCard) -> String {
        "codex-rendered-warning-card-\(card.sourceOrder)"
    }

    func cardAccessibilityLabel(_ card: CodexRenderedWarningCard) -> String {
        var parts = [
            stateAccessibilityLabel,
            card.displayName,
            "家族 \(card.family)",
            "推理强度 \(card.effort)",
            "IQ \(Self.metric(card.iq))",
            "24 小时下降 \(Self.metric(card.drop24h))",
        ]
        if let drop48h = card.drop48h {
            parts.append("48 小时下降 \(Self.metric(drop48h))")
        }
        if sourceTimeLabel != nil {
            parts.append(sourceTimeAccessibilityLabel)
        }
        if capturedAt != nil {
            parts.append(capturedAtAccessibilityLabel)
        }
        parts.append(attribution)
        return parts.joined(separator: "，")
    }

    private static func metric(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

/// Official IQ trend presentation (spec §6 v1.1, ADR-0002 successor of the
/// retired deng reader): rendered from the public intelligence-efficiency
/// sidecar's `history[]` observations — the full window, never a local
/// derivation. Series are `model@effort` keys discovered in the latest
/// observation; a series skips observations where that tier has no IQ
/// (breakpoint tolerance), never interpolating across gaps.
struct OfficialIQHistoryPresentation: Equatable, Sendable {
    enum State: String, CaseIterable, Equatable, Sendable {
        case loading
        case fresh
        case staleLastKnownGood = "stale-last-known-good"
        case lastKnownGoodWithError = "last-known-good-with-error"
        case unavailableWithoutLastKnownGood = "unavailable-without-last-known-good"
    }

    struct Point: Identifiable, Equatable, Sendable {
        let ordinal: Int
        let sourceTimeLabel: String
        let iq: Double
        var id: Int { ordinal }
    }

    struct Series: Identifiable, Equatable, Sendable {
        let seriesKey: String
        let displayName: String
        let points: [Point]
        var id: String { seriesKey }
    }

    let state: State
    let series: [Series]
    let selectedSeries: Series?
    let lastSuccessfulAt: Date?
    let observationCount: Int
    let errorMessage: String?

    let attribution = CodexRadarConfiguration.descriptor.attributionText
    let sectionAccessibilityIdentifier = "codex-official-iq-trend-section"

    init?(
        sourceID: RadarSourceID,
        state: SegmentState<IntelligenceEfficiencyDataset>?
    ) {
        guard sourceID == .codexRadar else { return nil }

        let dataset = state?.value
        observationCount = dataset?.history.count ?? 0

        if let error = state?.error {
            self.state = dataset == nil ? .unavailableWithoutLastKnownGood : .lastKnownGoodWithError
            errorMessage = Self.safe(error.message)
        } else if dataset != nil {
            self.state = state?.isStale == true ? .staleLastKnownGood : .fresh
            errorMessage = nil
        } else {
            self.state = .loading
            errorMessage = nil
        }

        // Series roster comes from the latest observation's point order so
        // the picker mirrors the upstream current ranking.
        let latest = dataset?.history.last
        let roster: [(key: String, display: String)] = (latest?.points ?? []).compactMap { point in
            guard let model = point.model, let effort = point.effort else { return nil }
            return (key: "\(model)@\(effort)", display: "\(model) · \(effort)")
        }

        let history = dataset?.history ?? []
        series = roster.map { entry in
            let model = entry.key.split(separator: "@").first.map(String.init) ?? entry.key
            let effort = entry.key.split(separator: "@").dropFirst().joined(separator: "@")
            var points: [Point] = []
            for (index, observation) in history.enumerated() {
                // Breakpoint tolerance: an observation without this tier's
                // IQ yields no point; the chart never bridges the gap with
                // an invented value.
                guard let match = observation.points.first(where: { $0.model == model && $0.effort == effort }),
                      let iq = match.iq else { continue }
                points.append(Point(ordinal: index, sourceTimeLabel: observation.at ?? "#\(index)", iq: iq))
            }
            return Series(seriesKey: entry.key, displayName: entry.display, points: points)
        }
        selectedSeries = series.first
        lastSuccessfulAt = state?.lastSuccessfulAt
    }

    var stateMessage: String {
        switch state {
        case .loading: "正在读取官网效能 IQ 历史"
        case .fresh: "官网 IQ 历史已更新"
        case .staleLastKnownGood: "正在显示可能已过期的最近有效官网 IQ 历史"
        case .lastKnownGoodWithError: "官网 IQ 历史刷新失败，正在显示最近有效数据"
        case .unavailableWithoutLastKnownGood: "官网 IQ 历史暂不可用"
        }
    }

    var stateAccessibilityIdentifier: String {
        "codex-official-iq-trend-state-\(state.rawValue)"
    }

    var stateAccessibilityLabel: String {
        [stateMessage, errorMessage].compactMap { $0 }.joined(separator: "：")
    }

    private static func safe(_ message: String) -> String {
        String(message.prefix(160))
    }
}
