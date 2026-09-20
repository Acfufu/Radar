import Foundation
import WebKit

@MainActor
protocol CodexRenderedCrowdtestIQReading: Sendable {
    func read() async throws -> CodexRenderedCrowdtestIQSnapshot
    func cancel()
}

enum CodexRenderedCrowdtestIQPageReaderError: Error, Equatable, Sendable {
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
    case validation(CodexRenderedCrowdtestIQDOMParserError)
}

typealias CodexRenderedCrowdtestIQNavigationDecision = CodexRenderedPageNavigationDecision
typealias CodexRenderedCrowdtestIQNavigationType = CodexRenderedPageNavigationType
typealias CodexRenderedCrowdtestIQNavigationPolicyInput = CodexRenderedPageNavigationPolicyInput
typealias CodexRenderedCrowdtestIQResponsePolicyInput = CodexRenderedPageResponsePolicyInput

/// Exact-origin hard guard for `deng.codexradar.com` (ADR-0004): shared
/// lifecycle policy pinned to the deng origin.
enum CodexRenderedCrowdtestIQNavigationPolicy {
    private static let exactOrigin = CodexRenderedCrowdtestIQDOMParser.exactOrigin

    static func decide(
        _ input: CodexRenderedCrowdtestIQNavigationPolicyInput
    ) -> CodexRenderedCrowdtestIQNavigationDecision {
        CodexRenderedPageNavigationPolicy.decide(input, exactOrigin: exactOrigin)
    }

    static func decide(
        _ input: CodexRenderedCrowdtestIQResponsePolicyInput
    ) -> CodexRenderedCrowdtestIQNavigationDecision {
        CodexRenderedPageNavigationPolicy.decide(input, exactOrigin: exactOrigin)
    }

    static func isAllowedMainFrameURL(_ url: URL) -> Bool {
        CodexRenderedPageNavigationPolicy.isAllowedMainFrameURL(
            url,
            exactOrigin: exactOrigin
        )
    }
}

enum CodexRenderedCrowdtestIQReadDecision: Equatable, Sendable {
    case none
    case poll(after: Duration)
    case success(CodexRenderedCrowdtestIQSnapshot)
    case failure(CodexRenderedCrowdtestIQPageReaderError)
}

struct CodexRenderedCrowdtestIQStabilizer: Sendable {
    private let navigationTimeout: Duration
    private let totalTimeout: Duration
    private let pollInterval: Duration
    private let stabilizationInterval: Duration
    private let parser = CodexRenderedCrowdtestIQDOMParser()

    private var didFinishNavigation = false
    private var isComplete = false
    private var candidateFingerprint: String?
    private var candidateSince: Duration?

    init(
        navigationTimeout: Duration = .seconds(20),
        totalTimeout: Duration = .seconds(60),
        pollInterval: Duration = .milliseconds(500),
        stabilizationInterval: Duration = .seconds(2)
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

    mutating func didFinish(at instant: Duration) -> CodexRenderedCrowdtestIQReadDecision {
        guard !isComplete else { return .none }
        didFinishNavigation = true
        return .poll(after: .zero)
    }

    mutating func receive(
        _ data: Data,
        capturedAt: Date,
        at instant: Duration
    ) -> CodexRenderedCrowdtestIQReadDecision {
        guard didFinishNavigation, !isComplete else { return .none }

        let snapshot: CodexRenderedCrowdtestIQSnapshot
        do {
            snapshot = try parser.parse(data, capturedAt: capturedAt)
        } catch let error as CodexRenderedCrowdtestIQDOMParserError {
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
    ) -> CodexRenderedCrowdtestIQReadDecision {
        guard !isComplete, !didFinishNavigation, instant >= navigationTimeout else {
            return .none
        }
        isComplete = true
        return .failure(.navigationTimeout)
    }

    mutating func totalDeadlineReached(
        at instant: Duration
    ) -> CodexRenderedCrowdtestIQReadDecision {
        guard !isComplete, instant >= totalTimeout else { return .none }
        isComplete = true
        return .failure(.totalTimeout)
    }

    mutating func cancel() -> CodexRenderedCrowdtestIQReadDecision {
        guard !isComplete else { return .none }
        isComplete = true
        return .failure(.cancelled)
    }
}

@MainActor
final class CodexRenderedCrowdtestIQPageReader: NSObject, CodexRenderedCrowdtestIQReading {
    static let fixedURL = URL(string: "https://deng.codexradar.com/")!
    static let extractionScript = #"""
    (() => {
      "use strict";
      const revision = "deng-rendered-crowdtest-iq-v1";
      const clean = (value) => typeof value === "string"
        ? value.replace(/\s+/g, " ").trim()
        : "";
      const blocked = document.documentElement.querySelector(
        "#challenge-form, [class*='cf-challenge'], [aria-label*='consent' i], [data-radar-challenge], [data-radar-consent]"
      );
      const blockedText = blocked ? clean(blocked.getAttribute("aria-label")) : "";
      const cards = Array.from(document.querySelectorAll(".iqcard"));
      const harnesses = [];
      for (const card of cards) {
        const cells = Array.from(card.querySelectorAll("[data-iq-score]"));
        // The station dashboard card carries no IQ cells; skip it.
        if (cells.length === 0) continue;
        const harness = clean(
          card.getAttribute("data-harness")
          || (card.querySelector("[data-harness]") ? card.querySelector("[data-harness]").getAttribute("data-harness") : "")
        ).toLowerCase();
        if (!harness) continue;
        const parsedCells = cells.map((button) => ({
          model: clean(button.getAttribute("data-model")),
          effort: clean(button.getAttribute("data-effort")),
          iqScore: Number(button.getAttribute("data-iq-score")),
          iqP: Number(button.getAttribute("data-iq-p")),
          iqN: Number(button.getAttribute("data-iq-n")),
          countP: Number(button.getAttribute("data-count-p")),
          countN: Number(button.getAttribute("data-count-n")),
          coveredTasks: Number(button.getAttribute("data-covered-tasks")),
          totalTasks: Number(button.getAttribute("data-total-tasks")),
          coverageInsufficient: button.getAttribute("data-coverage-insufficient") === "true",
          methodTitle: clean(button.getAttribute("title") || "")
        }));
        const circles = Array.from(card.querySelectorAll("circle[data-trend-label]"))
          .map((circle) => clean(circle.getAttribute("data-trend-label")))
          .filter((label) => label.length > 0);
        harnesses.push({ harness, cells: parsedCells, circles });
      }
      const pageState = blocked ? (/consent/i.test(blockedText) ? "consent" : "challenge") : "ready";
      const dto = { revision, finalOrigin: location.origin, pageState, harnesses };
      const json = JSON.stringify(dto);
      return new TextEncoder().encode(json).byteLength <= 4194304 ? json : "__CODEX_RADAR_OVERSIZE__";
    })();
    """#

    private let navigationTimeout: Duration
    private let totalTimeout: Duration
    private let pollInterval: Duration
    private let stabilizationInterval: Duration

    private var continuation: CheckedContinuation<CodexRenderedCrowdtestIQSnapshot, any Error>?
    private var stabilizer = CodexRenderedCrowdtestIQStabilizer()
    private var lifecycle: CodexRenderedPageLifecycle?
    private var generation = 0

    override convenience init() {
        self.init(
            navigationTimeout: .seconds(20),
            totalTimeout: .seconds(60),
            pollInterval: .milliseconds(500),
            stabilizationInterval: .seconds(2)
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

    func read() async throws -> CodexRenderedCrowdtestIQSnapshot {
        guard continuation == nil else {
            throw CodexRenderedCrowdtestIQPageReaderError.readAlreadyInProgress
        }
        guard !Task.isCancelled else {
            throw CodexRenderedCrowdtestIQPageReaderError.cancelled
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(
                        throwing: CodexRenderedCrowdtestIQPageReaderError.cancelled
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
        continuation?.resume(throwing: CodexRenderedCrowdtestIQPageReaderError.cancelled)
    }

    private func begin(
        _ continuation: CheckedContinuation<CodexRenderedCrowdtestIQSnapshot, any Error>
    ) {
        generation &+= 1
        let currentGeneration = generation
        self.continuation = continuation
        stabilizer = CodexRenderedCrowdtestIQStabilizer(
            navigationTimeout: navigationTimeout,
            totalTimeout: totalTimeout,
            pollInterval: pollInterval,
            stabilizationInterval: stabilizationInterval
        )
        let lifecycle = CodexRenderedPageLifecycle(
            fixedURL: Self.fixedURL,
            exactOrigin: CodexRenderedCrowdtestIQDOMParser.exactOrigin,
            extractionScript: Self.extractionScript,
            maximumBridgePayloadBytes: CodexRenderedCrowdtestIQDOMParser.maximumBridgePayloadBytes,
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

    private func handle(_ decision: CodexRenderedCrowdtestIQReadDecision, generation: Int) {
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
        _ result: Result<CodexRenderedCrowdtestIQSnapshot, CodexRenderedCrowdtestIQPageReaderError>,
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
    ) -> CodexRenderedCrowdtestIQPageReaderError {
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
