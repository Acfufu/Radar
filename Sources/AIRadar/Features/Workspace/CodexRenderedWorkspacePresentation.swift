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
