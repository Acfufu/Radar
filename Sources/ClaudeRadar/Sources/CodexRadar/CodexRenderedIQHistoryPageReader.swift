import Foundation
import WebKit

@MainActor
protocol CodexRenderedIQHistoryReading: Sendable {
    func read() async throws -> CodexRenderedIQHistorySnapshot
    func cancel()
}

enum CodexRenderedIQHistoryPageReaderError: Error, Equatable, Sendable {
    case readAlreadyInProgress
    case navigationDenied
    case responseDenied
    case downloadDenied
    case navigationFailed
    case javaScriptFailed
    case invalidBridgeValue
    case navigationTimeout
    case totalTimeout
    case cancelled
    case validation(CodexRenderedIQHistoryDOMParserError)
}

typealias CodexRenderedIQHistoryNavigationDecision = CodexRenderedPageNavigationDecision
typealias CodexRenderedIQHistoryNavigationType = CodexRenderedPageNavigationType
typealias CodexRenderedIQHistoryNavigationPolicyInput = CodexRenderedPageNavigationPolicyInput
typealias CodexRenderedIQHistoryResponsePolicyInput = CodexRenderedPageResponsePolicyInput

enum CodexRenderedIQHistoryNavigationPolicy {
    private static let exactOrigin = "https://deng.codexradar.com"

    static func decide(
        _ input: CodexRenderedIQHistoryNavigationPolicyInput
    ) -> CodexRenderedIQHistoryNavigationDecision {
        CodexRenderedPageNavigationPolicy.decide(input, exactOrigin: exactOrigin)
    }

    static func decide(
        _ input: CodexRenderedIQHistoryResponsePolicyInput
    ) -> CodexRenderedIQHistoryNavigationDecision {
        CodexRenderedPageNavigationPolicy.decide(input, exactOrigin: exactOrigin)
    }

    static func isAllowedMainFrameURL(_ url: URL) -> Bool {
        CodexRenderedPageNavigationPolicy.isAllowedMainFrameURL(
            url,
            exactOrigin: exactOrigin
        )
    }
}

enum CodexRenderedIQHistoryReadDecision: Equatable, Sendable {
    case none
    case poll(after: Duration)
    case success(CodexRenderedIQHistorySnapshot)
    case failure(CodexRenderedIQHistoryPageReaderError)
}

struct CodexRenderedIQHistoryStabilizer: Sendable {
    private let navigationTimeout: Duration
    private let totalTimeout: Duration
    private let pollInterval: Duration
    private let stabilizationInterval: Duration
    private let parser = CodexRenderedIQHistoryDOMParser()

    private var didFinishNavigation = false
    private var isComplete = false
    private var candidateFingerprint: String?
    private var candidateSince: Duration?

    init(
        navigationTimeout: Duration = .seconds(15),
        totalTimeout: Duration = .seconds(20),
        pollInterval: Duration = .milliseconds(250),
        stabilizationInterval: Duration = .milliseconds(500)
    ) {
        precondition(pollInterval >= .milliseconds(250))
        precondition(stabilizationInterval >= .milliseconds(500))
        precondition(navigationTimeout > .zero)
        precondition(totalTimeout > .zero)
        self.navigationTimeout = navigationTimeout
        self.totalTimeout = totalTimeout
        self.pollInterval = pollInterval
        self.stabilizationInterval = stabilizationInterval
    }

    mutating func didFinish(at instant: Duration) -> CodexRenderedIQHistoryReadDecision {
        guard !isComplete else { return .none }
        didFinishNavigation = true
        return .poll(after: .zero)
    }

    mutating func receive(
        _ data: Data,
        capturedAt: Date,
        at instant: Duration
    ) -> CodexRenderedIQHistoryReadDecision {
        guard didFinishNavigation, !isComplete else { return .none }

        let snapshot: CodexRenderedIQHistorySnapshot
        do {
            snapshot = try parser.parse(data, capturedAt: capturedAt)
        } catch let error as CodexRenderedIQHistoryDOMParserError {
            if error == .contentPending {
                candidateFingerprint = nil
                candidateSince = nil
                return .poll(after: pollInterval)
            }
            isComplete = true
            return .failure(.validation(error))
        } catch {
            isComplete = true
            return .failure(.validation(.invalidPayload))
        }

        guard candidateFingerprint == snapshot.semanticFingerprint,
              let candidateSince else {
            candidateFingerprint = snapshot.semanticFingerprint
            self.candidateSince = instant
            return .poll(after: pollInterval)
        }
        guard instant - candidateSince >= stabilizationInterval else {
            return .poll(after: pollInterval)
        }

        isComplete = true
        return .success(snapshot)
    }

    mutating func navigationDeadlineReached(
        at instant: Duration
    ) -> CodexRenderedIQHistoryReadDecision {
        guard !isComplete, !didFinishNavigation, instant >= navigationTimeout else {
            return .none
        }
        isComplete = true
        return .failure(.navigationTimeout)
    }

    mutating func totalDeadlineReached(
        at instant: Duration
    ) -> CodexRenderedIQHistoryReadDecision {
        guard !isComplete, instant >= totalTimeout else { return .none }
        isComplete = true
        return .failure(.totalTimeout)
    }

    mutating func cancel() -> CodexRenderedIQHistoryReadDecision {
        guard !isComplete else { return .none }
        isComplete = true
        return .failure(.cancelled)
    }
}

@MainActor
final class CodexRenderedIQHistoryPageReader: CodexRenderedIQHistoryReading {
    static let fixedURL = URL(string: "https://deng.codexradar.com/")!
    static let extractionScript = #"""
    (() => {
      "use strict";
      const revision = "codex-radar-rendered-iq-history-v1";
      const clean = (value) => typeof value === "string"
        ? value.replace(/\s+/g, " ").trim()
        : "";
      const visible = (element) => {
        if (!element || element.hidden || element.getAttribute("aria-hidden") === "true") {
          return false;
        }
        const style = getComputedStyle(element);
        const rect = element.getBoundingClientRect();
        return style.display !== "none"
          && style.visibility !== "hidden"
          && rect.width > 0
          && rect.height > 0;
      };
      const accessibleName = (element) => {
        const direct = clean(element.getAttribute("aria-label"));
        if (direct) return direct;
        const labelled = clean(element.getAttribute("aria-labelledby"))
          .split(/\s+/)
          .map((id) => clean(document.getElementById(id)?.textContent))
          .filter(Boolean)
          .join(" ");
        return labelled || clean(element.querySelector("title")?.textContent);
      };
      const is24hIQTrend = (name) =>
        /(?:^|\D)24\s*(?:h|小时)(?:\D|$)/i.test(name)
        && /(?:^|\W)iq(?:\W|$)/i.test(name)
        && /(?:趋势|走势|trend)/i.test(name)
        && /(?:最近|近期|近|recent|last|past)/i.test(name);
      const visible24h = Array.from(
        document.querySelectorAll('.iq-range button[data-iq-hours="24"]')
      ).find(visible);
      if (visible24h && visible24h.getAttribute("aria-pressed") !== "true") {
        visible24h.click();
      }
      const selected = Array.from(
        document.querySelectorAll(".iq-range button[data-iq-hours]")
      ).find((button) => button.getAttribute("aria-pressed") === "true");
      const root = document.querySelector(
        "#iq-body.iq, #iq-body, #iqbody.iq, #iqbody"
      );
      const blocked = document.documentElement.querySelector(
        "[data-radar-challenge], [data-radar-consent], #challenge-form, [class*='cf-challenge'], [aria-label*='consent' i]"
      );
      const blockedText = blocked ? clean(blocked.getAttribute("aria-label")) : "";
      const qualifying = (card) => {
        if (!visible(card)) return false;
        const trend = Array.from(
          card.querySelectorAll("svg")
        ).find((svg) => visible(svg) && is24hIQTrend(accessibleName(svg)));
        return trend || false;
      };
      const totalCards = root ? Array.from(root.querySelectorAll(
        ":scope > .iqcard.total-iq:not([data-model])"
      )).filter(qualifying) : [];
      const modelCards = root ? Array.from(root.querySelectorAll(
        ":scope > .iqcard[data-model]:not(.total-iq)"
      )).filter(qualifying) : [];
      const cards = totalCards.concat(modelCards);
      const series = cards.map((card, sourceOrder) => {
        const model = clean(card.getAttribute("data-model"));
        const trend = qualifying(card);
        const labels = Array.from(
          trend.querySelectorAll(".iq-trend-hit[data-trend-label]")
        ).map((point) => clean(point.getAttribute("data-trend-label")));
        const points = labels.map((label, pointOrder) => {
          const match = label.match(/^(.*?)\s*·\s*([-+]?\d+(?:\.\d+)?)\s*IQ$/i);
          return match
            ? { sourceOrder: pointOrder, sourceTimeLabel: clean(match[1]), iq: Number(match[2]) }
            : { sourceOrder: pointOrder, sourceTimeLabel: "", iq: null };
        });
        return {
          sourceOrder,
          seriesKey: card.matches(".total-iq") ? "aggregate" : `model:${model}`,
          displayName: clean(card.querySelector(".m")?.textContent),
          points
        };
      });
      const dto = {
        revision,
        finalOrigin: location.origin,
        rootPresent: !!root,
        selectedRange: selected ? `${selected.getAttribute("data-iq-hours")}h` : null,
        pageState: blocked
          ? (/consent/i.test(blockedText) ? "consent" : "challenge")
          : "ready",
        series
      };
      const json = JSON.stringify(dto);
      return new TextEncoder().encode(json).byteLength <= 65536
        ? json
        : "__CODEX_RADAR_OVERSIZE__";
    })();
    """#

    private let navigationTimeout: Duration
    private let totalTimeout: Duration
    private let pollInterval: Duration
    private let stabilizationInterval: Duration
    private var continuation: CheckedContinuation<CodexRenderedIQHistorySnapshot, any Error>?
    private var stabilizer = CodexRenderedIQHistoryStabilizer()
    private var lifecycle: CodexRenderedPageLifecycle?
    private var generation = 0

    convenience init() {
        self.init(
            navigationTimeout: .seconds(15),
            totalTimeout: .seconds(20),
            pollInterval: .milliseconds(250),
            stabilizationInterval: .milliseconds(500)
        )
    }

    init(
        navigationTimeout: Duration,
        totalTimeout: Duration,
        pollInterval: Duration,
        stabilizationInterval: Duration
    ) {
        self.navigationTimeout = navigationTimeout
        self.totalTimeout = totalTimeout
        self.pollInterval = pollInterval
        self.stabilizationInterval = stabilizationInterval
    }

    static func makeConfiguration() -> WKWebViewConfiguration {
        CodexRenderedPageLifecycle.makeConfiguration()
    }

    func read() async throws -> CodexRenderedIQHistorySnapshot {
        guard continuation == nil else {
            throw CodexRenderedIQHistoryPageReaderError.readAlreadyInProgress
        }
        guard !Task.isCancelled else {
            throw CodexRenderedIQHistoryPageReaderError.cancelled
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(
                        throwing: CodexRenderedIQHistoryPageReaderError.cancelled
                    )
                    return
                }
                begin(continuation)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    func cancel() {
        handle(stabilizer.cancel(), generation: generation)
    }

    deinit {
        let lifecycle = lifecycle
        Task { @MainActor in
            lifecycle?.stop()
        }
        continuation?.resume(
            throwing: CodexRenderedIQHistoryPageReaderError.cancelled
        )
    }

    private func begin(
        _ continuation: CheckedContinuation<CodexRenderedIQHistorySnapshot, any Error>
    ) {
        generation &+= 1
        let currentGeneration = generation
        self.continuation = continuation
        stabilizer = CodexRenderedIQHistoryStabilizer(
            navigationTimeout: navigationTimeout,
            totalTimeout: totalTimeout,
            pollInterval: pollInterval,
            stabilizationInterval: stabilizationInterval
        )
        let lifecycle = CodexRenderedPageLifecycle(
            fixedURL: Self.fixedURL,
            exactOrigin: "https://deng.codexradar.com",
            extractionScript: Self.extractionScript,
            maximumBridgePayloadBytes: CodexRenderedIQHistoryDOMParser.maximumBridgePayloadBytes,
            navigationTimeout: navigationTimeout,
            totalTimeout: totalTimeout,
            pollInterval: pollInterval,
            stabilizationInterval: stabilizationInterval,
            onDidFinish: { [weak self] elapsed in
                guard let self, generation == currentGeneration else { return }
                handle(stabilizer.didFinish(at: elapsed), generation: currentGeneration)
            },
            onPayload: { [weak self] data, elapsed in
                guard let self, generation == currentGeneration else { return }
                handle(
                    stabilizer.receive(data, capturedAt: Date(), at: elapsed),
                    generation: currentGeneration
                )
            },
            onFailure: { [weak self] failure in
                guard let self, generation == currentGeneration else { return }
                finish(
                    .failure(Self.error(for: failure)),
                    generation: currentGeneration
                )
            }
        )
        self.lifecycle = lifecycle
        lifecycle.start()
    }

    private func handle(_ decision: CodexRenderedIQHistoryReadDecision, generation: Int) {
        guard generation == self.generation else { return }
        switch decision {
        case .none:
            break
        case let .poll(delay):
            lifecycle?.schedulePoll(after: delay)
        case let .success(snapshot):
            finish(.success(snapshot), generation: generation)
        case let .failure(error):
            finish(.failure(error), generation: generation)
        }
    }

    private func finish(
        _ result: Result<CodexRenderedIQHistorySnapshot, CodexRenderedIQHistoryPageReaderError>,
        generation expectedGeneration: Int
    ) {
        guard generation == expectedGeneration, let continuation else { return }
        self.continuation = nil
        lifecycle?.stop()
        lifecycle = nil
        switch result {
        case let .success(snapshot): continuation.resume(returning: snapshot)
        case let .failure(error): continuation.resume(throwing: error)
        }
    }

    private static func error(
        for failure: CodexRenderedPageLifecycleFailure
    ) -> CodexRenderedIQHistoryPageReaderError {
        switch failure {
        case .navigationDenied: .navigationDenied
        case .responseDenied: .responseDenied
        case .downloadDenied: .downloadDenied
        case .navigationFailed: .navigationFailed
        case .javaScriptFailed: .javaScriptFailed
        case .invalidBridgeValue: .invalidBridgeValue
        case .bridgePayloadTooLarge: .validation(.bridgePayloadTooLarge)
        case .navigationTimeout: .navigationTimeout
        case .totalTimeout: .totalTimeout
        }
    }
}
