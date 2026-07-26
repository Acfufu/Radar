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

enum CodexRenderedWarningNavigationDecision: Equatable, Sendable {
    case allow
    case cancel
}

enum CodexRenderedWarningNavigationType: Equatable, Sendable {
    case linkActivated
    case formSubmitted
    case backForward
    case reload
    case formResubmitted
    case other
}

struct CodexRenderedWarningNavigationPolicyInput: Equatable, Sendable {
    let url: URL
    let type: CodexRenderedWarningNavigationType
    let targetFrameExists: Bool
    let isMainFrame: Bool
    let shouldDownload: Bool
}

struct CodexRenderedWarningResponsePolicyInput: Equatable, Sendable {
    let url: URL
    let isMainFrame: Bool
    let canShowMIMEType: Bool
}

enum CodexRenderedWarningNavigationPolicy {
    static func decide(
        _ input: CodexRenderedWarningNavigationPolicyInput
    ) -> CodexRenderedWarningNavigationDecision {
        guard input.targetFrameExists,
              input.isMainFrame,
              !input.shouldDownload,
              input.type == .other,
              isAllowedMainFrameURL(input.url) else {
            return .cancel
        }
        return .allow
    }

    static func decide(
        _ input: CodexRenderedWarningResponsePolicyInput
    ) -> CodexRenderedWarningNavigationDecision {
        guard input.isMainFrame,
              input.canShowMIMEType,
              isAllowedMainFrameURL(input.url) else {
            return .cancel
        }
        return .allow
    }

    static func isAllowedMainFrameURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "codexradar.com"
            && (url.port == nil || url.port == 443)
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
    private let clock = ContinuousClock()

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<CodexRenderedWarningSnapshot, any Error>?
    private var stabilizer = CodexRenderedWarningStabilizer()
    private var startedAt: ContinuousClock.Instant?
    private var generation = 0
    private var hasFinishedNavigation = false
    private var navigationDeadlineTask: Task<Void, Never>?
    private var totalDeadlineTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

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
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        return configuration
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
        navigationDeadlineTask?.cancel()
        totalDeadlineTask?.cancel()
        pollTask?.cancel()
        let webView = webView
        Task { @MainActor in
            webView?.stopLoading()
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
        startedAt = clock.now
        hasFinishedNavigation = false

        let webView = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView

        navigationDeadlineTask = deadlineTask(
            after: navigationTimeout,
            generation: currentGeneration
        ) { reader, elapsed in
            reader.stabilizer.navigationDeadlineReached(at: elapsed)
        }
        totalDeadlineTask = deadlineTask(
            after: totalTimeout,
            generation: currentGeneration
        ) { reader, elapsed in
            reader.stabilizer.totalDeadlineReached(at: elapsed)
        }

        var request = URLRequest(url: Self.fixedURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        webView.load(request)
    }

    private func deadlineTask(
        after duration: Duration,
        generation expectedGeneration: Int,
        decision: @escaping @MainActor (
            CodexRenderedWarningPageReader,
            Duration
        ) -> CodexRenderedWarningReadDecision
    ) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            guard let self, generation == expectedGeneration else { return }
            handle(decision(self, elapsed), generation: expectedGeneration)
        }
    }

    private var elapsed: Duration {
        guard let startedAt else { return .zero }
        return startedAt.duration(to: clock.now)
    }

    private func schedulePoll(after delay: Duration, generation expectedGeneration: Int) {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            do {
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }
            } catch {
                return
            }
            guard let self, self.generation == expectedGeneration, let webView else { return }
            let value: Any?
            do {
                value = try await webView.evaluateJavaScript(Self.extractionScript)
            } catch is CancellationError {
                return
            } catch {
                self.finish(.failure(.javaScriptFailed), generation: expectedGeneration)
                return
            }
            guard !Task.isCancelled, self.generation == expectedGeneration else { return }
            guard let payload = value as? String else {
                self.finish(.failure(.invalidBridgeValue), generation: expectedGeneration)
                return
            }
            if payload == "__CODEX_RADAR_OVERSIZE__" {
                self.finish(
                    .failure(.validation(.bridgePayloadTooLarge)),
                    generation: expectedGeneration
                )
                return
            }
            let data = Data(payload.utf8)
            self.handle(
                self.stabilizer.receive(data, capturedAt: Date(), at: self.elapsed),
                generation: expectedGeneration
            )
        }
    }

    private func handle(_ decision: CodexRenderedWarningReadDecision, generation: Int) {
        switch decision {
        case .none:
            break
        case let .poll(delay):
            schedulePoll(after: delay, generation: generation)
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
        navigationDeadlineTask?.cancel()
        totalDeadlineTask?.cancel()
        pollTask?.cancel()
        navigationDeadlineTask = nil
        totalDeadlineTask = nil
        pollTask = nil
        startedAt = nil

        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil

        switch result {
        case let .success(snapshot):
            continuation.resume(returning: snapshot)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }

    private func failNavigation(
        _ error: CodexRenderedWarningPageReaderError,
        webView: WKWebView
    ) {
        guard webView === self.webView else { return }
        finish(.failure(error), generation: generation)
    }
}

extension CodexRenderedWarningPageReader: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        let input = CodexRenderedWarningNavigationPolicyInput(
            url: navigationAction.request.url ?? URL(filePath: "/"),
            type: CodexRenderedWarningNavigationType(navigationAction.navigationType),
            targetFrameExists: navigationAction.targetFrame != nil,
            isMainFrame: navigationAction.targetFrame?.isMainFrame == true,
            shouldDownload: navigationAction.shouldPerformDownload
        )
        guard !hasFinishedNavigation,
              CodexRenderedWarningNavigationPolicy.decide(input) == .allow else {
            failNavigation(
                navigationAction.shouldPerformDownload ? .downloadDenied : .navigationDenied,
                webView: webView
            )
            return .cancel
        }
        return .allow
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        let input = CodexRenderedWarningResponsePolicyInput(
            url: navigationResponse.response.url ?? URL(filePath: "/"),
            isMainFrame: navigationResponse.isForMainFrame,
            canShowMIMEType: navigationResponse.canShowMIMEType
        )
        guard CodexRenderedWarningNavigationPolicy.decide(input) == .allow else {
            failNavigation(.responseDenied, webView: webView)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView,
              !hasFinishedNavigation,
              let url = webView.url,
              CodexRenderedWarningNavigationPolicy.isAllowedMainFrameURL(url) else {
            failNavigation(.navigationDenied, webView: webView)
            return
        }
        navigationDeadlineTask?.cancel()
        navigationDeadlineTask = nil
        hasFinishedNavigation = true
        handle(stabilizer.didFinish(at: elapsed), generation: generation)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        failNavigation(.navigationFailed, webView: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        failNavigation(.navigationFailed, webView: webView)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        download.cancel()
        failNavigation(.downloadDenied, webView: webView)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.cancel()
        failNavigation(.downloadDenied, webView: webView)
    }
}

extension CodexRenderedWarningPageReader: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        failNavigation(.navigationDenied, webView: webView)
        return nil
    }
}

private extension CodexRenderedWarningNavigationType {
    init(_ type: WKNavigationType) {
        switch type {
        case .linkActivated:
            self = .linkActivated
        case .formSubmitted:
            self = .formSubmitted
        case .backForward:
            self = .backForward
        case .reload:
            self = .reload
        case .formResubmitted:
            self = .formResubmitted
        case .other:
            self = .other
        @unknown default:
            self = .linkActivated
        }
    }
}
