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

enum CodexRenderedIQHistoryChartSource: String, CaseIterable, Identifiable, Sendable {
    case official24h = "官网 24h"
    case localFit = "本地拟合"

    var id: Self { self }
}

struct CodexRenderedIQHistoryPresentation: Equatable, Sendable {
    enum State: String, CaseIterable, Equatable, Sendable {
        case loading
        case fresh
        case staleLastKnownGood = "stale-last-known-good"
        case lastKnownGoodWithError = "last-known-good-with-error"
        case schemaDriftWithoutLastKnownGood = "schema-drift-without-last-known-good"
        case challengeWithoutLastKnownGood = "challenge-without-last-known-good"
        case unavailableWithoutLastKnownGood = "unavailable-without-last-known-good"
    }

    enum Selection: Hashable, Sendable {
        case aggregate
        case model(String)
    }

    struct Point: Identifiable, Equatable, Sendable {
        let ordinal: Int
        let sourceTimeLabel: String
        let iq: Double
        var id: Int { ordinal }
    }

    struct Series: Identifiable, Equatable, Sendable {
        let sourceOrder: Int
        let seriesKey: String
        let displayName: String
        let points: [Point]
        var id: String { seriesKey }
    }

    let state: State
    let selection: Selection
    let series: [Series]
    let selectedSeries: Series?
    let lastSuccessfulAt: Date?
    let capturedAt: Date?
    let errorMessage: String?

    let attribution = "数据来自分布式雷达 deng.codexradar.com · powered by codexradar"
    let backlink = "https://deng.codexradar.com/"
    let sectionAccessibilityIdentifier = "codex-rendered-iq-history-section"

    init?(
        sourceID: RadarSourceID,
        state: SegmentState<CodexRenderedIQHistorySnapshot>?,
        selection: Selection = .aggregate
    ) {
        guard sourceID == .codexRadar else { return nil }

        let snapshot = state?.value
        self.state = Self.presentationState(state)
        self.series = snapshot?.series.map {
            Series(
                sourceOrder: $0.sourceOrder,
                seriesKey: $0.seriesKey,
                displayName: $0.displayName,
                points: $0.points.map {
                    Point(ordinal: $0.sourceOrder, sourceTimeLabel: $0.sourceTimeLabel, iq: $0.iq)
                }
            )
        } ?? []
        self.selection = Self.reconciled(selection, in: series)
        self.selectedSeries = Self.selectedSeries(selection: self.selection, in: series)
        self.lastSuccessfulAt = state?.lastSuccessfulAt
        self.capturedAt = snapshot?.capturedAt
        self.errorMessage = state?.error.map { safe($0.message) }
    }

    var modelChoices: [Series] {
        series.filter { $0.seriesKey != "aggregate" }
    }

    var stateMessage: String {
        switch state {
        case .loading: "正在读取 Codex Radar 官网 24 小时 IQ 曲线"
        case .fresh: "官网 24 小时 IQ 曲线已更新"
        case .staleLastKnownGood: "正在显示可能已过期的最近有效官网 24 小时 IQ 曲线"
        case .lastKnownGoodWithError: "官网 24 小时 IQ 曲线刷新失败，正在显示最近有效数据"
        case .schemaDriftWithoutLastKnownGood: "官网 24 小时 IQ 曲线格式已变化，暂不可用"
        case .challengeWithoutLastKnownGood: "官网 24 小时 IQ 曲线访问受限，暂不可用"
        case .unavailableWithoutLastKnownGood: "官网 24 小时 IQ 曲线暂不可用"
        }
    }

    var stateAccessibilityIdentifier: String {
        "codex-rendered-iq-history-state-\(state.rawValue)"
    }

    var stateAccessibilityLabel: String {
        [stateMessage, errorMessage].compactMap { $0 }.joined(separator: "：")
    }

    var selectedSeriesAccessibilityIdentifier: String {
        "codex-rendered-iq-history-series-\(selectedSeries?.seriesKey ?? "none")"
    }

    var selectedSeriesAccessibilityLabel: String {
        guard let selectedSeries else { return "\(stateAccessibilityLabel)，\(attribution)" }
        let labels = selectedSeries.points.map(\.sourceTimeLabel).joined(separator: "、")
        return "\(stateAccessibilityLabel)，\(selectedSeries.displayName)，\(selectedSeries.points.count) 个点，\(labels)，\(attribution)"
    }

    private static func presentationState(
        _ state: SegmentState<CodexRenderedIQHistorySnapshot>?
    ) -> State {
        guard let state else { return .loading }
        if state.value != nil {
            if state.error != nil { return .lastKnownGoodWithError }
            return state.isStale ? .staleLastKnownGood : .fresh
        }
        guard let error = state.error else { return .loading }
        let message = error.message.lowercased()
        if error.kind == .validation, message.contains("challenge") || message.contains("consent") {
            return .challengeWithoutLastKnownGood
        }
        if error.kind == .validation {
            return .schemaDriftWithoutLastKnownGood
        }
        return .unavailableWithoutLastKnownGood
    }

    private static func reconciled(_ selection: Selection, in series: [Series]) -> Selection {
        switch selection {
        case .aggregate:
            return .aggregate
        case .model(let key):
            return series.contains { $0.seriesKey == key } ? .model(key) : .aggregate
        }
    }

    private static func selectedSeries(selection: Selection, in series: [Series]) -> Series? {
        switch selection {
        case .aggregate:
            return series.first { $0.seriesKey == "aggregate" }
        case .model(let key):
            return series.first { $0.seriesKey == key }
        }
    }
}
