import Foundation
import WebKit

@MainActor
protocol CodexRenderedWarningReading: Sendable {
    func read() async throws -> CodexRenderedWarningSnapshot
    func cancel()
}

enum CodexRenderedWarningPageReaderError: Error, Equatable, Sendable {
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
    case validation(CodexRenderedWarningDOMParserError)
}

typealias CodexRenderedWarningNavigationDecision = CodexRenderedPageNavigationDecision
typealias CodexRenderedWarningNavigationType = CodexRenderedPageNavigationType
typealias CodexRenderedWarningNavigationPolicyInput = CodexRenderedPageNavigationPolicyInput
typealias CodexRenderedWarningResponsePolicyInput = CodexRenderedPageResponsePolicyInput

enum CodexRenderedWarningNavigationPolicy {
    private static let exactOrigin = "https://codexradar.com"

    static func decide(
        _ input: CodexRenderedWarningNavigationPolicyInput
    ) -> CodexRenderedWarningNavigationDecision {
        CodexRenderedPageNavigationPolicy.decide(input, exactOrigin: exactOrigin)
    }

    static func decide(
        _ input: CodexRenderedWarningResponsePolicyInput
    ) -> CodexRenderedWarningNavigationDecision {
        CodexRenderedPageNavigationPolicy.decide(input, exactOrigin: exactOrigin)
    }

    static func isAllowedMainFrameURL(_ url: URL) -> Bool {
        CodexRenderedPageNavigationPolicy.isAllowedMainFrameURL(
            url,
            exactOrigin: exactOrigin
        )
    }
}

enum CodexRenderedWarningReadDecision: Equatable, Sendable {
    case none
    case poll(after: Duration)
    case success(CodexRenderedWarningSnapshot)
    case failure(CodexRenderedWarningPageReaderError)
}

struct CodexRenderedWarningStabilizer: Sendable {
    private let navigationTimeout: Duration
    private let totalTimeout: Duration
    private let pollInterval: Duration
    private let stabilizationInterval: Duration
    private let parser = CodexRenderedWarningDOMParser()

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

    mutating func didFinish(at instant: Duration) -> CodexRenderedWarningReadDecision {
        guard !isComplete else { return .none }
        didFinishNavigation = true
        return .poll(after: .zero)
    }

    mutating func receive(
        _ data: Data,
        capturedAt: Date,
        at instant: Duration
    ) -> CodexRenderedWarningReadDecision {
        guard didFinishNavigation, !isComplete else { return .none }

        let snapshot: CodexRenderedWarningSnapshot
        do {
            snapshot = try parser.parse(data, capturedAt: capturedAt)
        } catch let error as CodexRenderedWarningDOMParserError {
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

        let stableFor = instant - candidateSince
        guard stableFor >= stabilizationInterval else {
            return .poll(after: pollInterval)
        }

        isComplete = true
        return .success(snapshot)
    }

    mutating func navigationDeadlineReached(
        at instant: Duration
    ) -> CodexRenderedWarningReadDecision {
        guard !isComplete, !didFinishNavigation, instant >= navigationTimeout else {
            return .none
        }
        isComplete = true
        return .failure(.navigationTimeout)
    }

    mutating func totalDeadlineReached(
        at instant: Duration
    ) -> CodexRenderedWarningReadDecision {
        guard !isComplete, instant >= totalTimeout else { return .none }
        isComplete = true
        return .failure(.totalTimeout)
    }

    mutating func cancel() -> CodexRenderedWarningReadDecision {
        guard !isComplete else { return .none }
        isComplete = true
        return .failure(.cancelled)
    }
}

@MainActor
final class CodexRenderedWarningPageReader: NSObject, CodexRenderedWarningReading {
    static let fixedURL = URL(string: "https://codexradar.com/")!
    static let extractionScript = #"""
    (() => {
      "use strict";
      const revision = "codex-radar-rendered-dom-v1";
      const clean = (value) => typeof value === "string"
        ? value.replace(/\s+/g, " ").trim()
        : "";
      const token = (value) => clean(value)
        .toLowerCase()
        .replace(/\s+/g, "-")
        .replace(/[^a-z0-9+._-]/g, "");
      const root = document.querySelector("section[data-radar-degradation]");
      const blocked = document.documentElement.querySelector(
        "[data-radar-challenge], [data-radar-consent], #challenge-form, [class*='cf-challenge'], [aria-label*='consent' i]"
      );
      const blockedText = blocked ? clean(blocked.getAttribute("aria-label")) : "";
      const grid = root ? root.querySelector("[data-radar-degradation-grid]") : null;
      const live = root ? root.querySelector("[data-radar-degradation-live]") : null;
      const articles = grid ? Array.from(grid.querySelectorAll(":scope > article")) : [];
      const numberFrom = (value) => {
        const matches = clean(value).replace(/,/g, "").match(/[-+]?\d+(?:\.\d+)?/g);
        return matches && matches.length ? Number(matches[matches.length - 1]) : null;
      };
      const metric = (article, kind) => {
        const patterns = {
          iq: /(^|[^a-z])iq([^a-z]|$)|智商/i,
          drop24h: /24\s*(?:h|小时)/i,
          drop48h: /48\s*(?:h|小时)/i
        };
        const observedNode = kind === "iq"
          ? article.querySelector(".degradation-card-score strong")
          : Array.from(article.querySelectorAll(".degradation-deltas > span"))
              .find((candidate) => patterns[kind].test(clean(candidate.textContent)));
        const nodes = Array.from(article.querySelectorAll("[data-radar-metric], [aria-label]"));
        const node = observedNode || nodes.find((candidate) => {
          const label = [
            candidate.getAttribute("data-radar-metric"),
            candidate.getAttribute("aria-label"),
            candidate.textContent
          ].map(clean).join(" ");
          return patterns[kind].test(label);
        });
        if (!node) return null;
        const value = numberFrom(
          node.getAttribute("data-value")
          || node.getAttribute("aria-valuenow")
          || node.textContent
        );
        if (!Number.isFinite(value)) return null;
        return kind === "iq" ? value : Math.abs(value);
      };
      const cards = articles.map((article, sourceOrder) => {
        const heading = article.querySelector("h3");
        const displayName = clean(heading ? heading.textContent : "");
        const parts = displayName.split(/\s*[·•]\s*/);
        const words = displayName.split(/\s+/);
        const fallbackFamily = words.length > 1
          ? words.slice(0, -1).join("-")
          : displayName;
        const fallbackEffort = words.length > 1 ? words[words.length - 1] : "";
        const family = token(
          article.getAttribute("data-model-family")
          || (heading && heading.getAttribute("data-model-family"))
          || (parts.length > 1 ? parts[0] : fallbackFamily)
        );
        const effort = token(
          article.getAttribute("data-model-effort")
          || (heading && heading.getAttribute("data-model-effort"))
          || (parts.length > 1 ? parts[parts.length - 1] : fallbackEffort)
        );
        const values = [
          { kind: "iq", value: metric(article, "iq") },
          { kind: "drop24h", value: metric(article, "drop24h") },
          { kind: "drop48h", value: metric(article, "drop48h") }
        ].filter((entry) => entry.value !== null);
        return { sourceOrder, displayName, family, effort, metrics: values };
      });
      const rootText = root ? clean(root.textContent) : "";
      const explicitEmpty = !!(root && (
        root.querySelector("[data-radar-degradation-empty]")
        || /(?:暂无|没有|无)\s*(?:降智)?预警|no\s+(?:degradation\s+)?alerts?/i.test(rootText)
      ));
      const pageState = blocked
        ? (/consent/i.test(blockedText) ? "consent" : "challenge")
        : (explicitEmpty ? "empty" : "ready");
      const dto = {
        revision,
        finalOrigin: location.origin,
        rootPresent: !!root,
        gridPresent: !!grid,
        liveTimePresent: !!live,
        sourceTimeLabel: live ? clean(live.textContent) : null,
        pageState,
        cards
      };
      const json = JSON.stringify(dto);
      return new TextEncoder().encode(json).byteLength <= 16384
        ? json
        : "__CODEX_RADAR_OVERSIZE__";
    })();
    """#

    private let navigationTimeout: Duration
    private let totalTimeout: Duration
    private let pollInterval: Duration
    private let stabilizationInterval: Duration

    private var continuation: CheckedContinuation<CodexRenderedWarningSnapshot, any Error>?
    private var stabilizer = CodexRenderedWarningStabilizer()
    private var lifecycle: CodexRenderedPageLifecycle?
    private var generation = 0

    override convenience init() {
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
        super.init()
    }

    static func makeConfiguration() -> WKWebViewConfiguration {
        CodexRenderedPageLifecycle.makeConfiguration()
    }

    func read() async throws -> CodexRenderedWarningSnapshot {
        guard continuation == nil else {
            throw CodexRenderedWarningPageReaderError.readAlreadyInProgress
        }
        guard !Task.isCancelled else {
            throw CodexRenderedWarningPageReaderError.cancelled
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(
                        throwing: CodexRenderedWarningPageReaderError.cancelled
                    )
                    return
                }
                self.begin(continuation)
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
        continuation?.resume(throwing: CodexRenderedWarningPageReaderError.cancelled)
    }

    private func begin(
        _ continuation: CheckedContinuation<CodexRenderedWarningSnapshot, any Error>
    ) {
        generation &+= 1
        let currentGeneration = generation
        self.continuation = continuation
        stabilizer = CodexRenderedWarningStabilizer(
            navigationTimeout: navigationTimeout,
            totalTimeout: totalTimeout,
            pollInterval: pollInterval,
            stabilizationInterval: stabilizationInterval
        )
        let lifecycle = CodexRenderedPageLifecycle(
            fixedURL: Self.fixedURL,
            exactOrigin: "https://codexradar.com",
            extractionScript: Self.extractionScript,
            maximumBridgePayloadBytes: CodexRenderedWarningDOMParser.maximumBridgePayloadBytes,
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

    private func handle(_ decision: CodexRenderedWarningReadDecision, generation: Int) {
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
        _ result: Result<CodexRenderedWarningSnapshot, CodexRenderedWarningPageReaderError>,
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
    ) -> CodexRenderedWarningPageReaderError {
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
