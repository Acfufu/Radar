import Foundation
import WebKit

enum CodexRenderedPageNavigationDecision: Equatable, Sendable {
    case allow
    case cancel
}

enum CodexRenderedPageNavigationType: Equatable, Sendable {
    case linkActivated
    case formSubmitted
    case backForward
    case reload
    case formResubmitted
    case other
}

struct CodexRenderedPageNavigationPolicyInput: Equatable, Sendable {
    let url: URL
    let type: CodexRenderedPageNavigationType
    let targetFrameExists: Bool
    let isMainFrame: Bool
    let shouldDownload: Bool
}

struct CodexRenderedPageResponsePolicyInput: Equatable, Sendable {
    let url: URL
    let isMainFrame: Bool
    let canShowMIMEType: Bool
}

enum CodexRenderedPageNavigationPolicy {
    static func decide(
        _ input: CodexRenderedPageNavigationPolicyInput,
        exactOrigin: String
    ) -> CodexRenderedPageNavigationDecision {
        guard input.targetFrameExists,
              input.isMainFrame,
              !input.shouldDownload,
              input.type == .other,
              isAllowedMainFrameURL(input.url, exactOrigin: exactOrigin) else {
            return .cancel
        }
        return .allow
    }

    static func decide(
        _ input: CodexRenderedPageResponsePolicyInput,
        exactOrigin: String
    ) -> CodexRenderedPageNavigationDecision {
        guard input.isMainFrame,
              input.canShowMIMEType,
              isAllowedMainFrameURL(input.url, exactOrigin: exactOrigin) else {
            return .cancel
        }
        return .allow
    }

    static func isAllowedMainFrameURL(_ url: URL, exactOrigin: String) -> Bool {
        guard let expected = URL(string: exactOrigin) else { return false }
        return url.scheme?.lowercased() == expected.scheme?.lowercased()
            && url.host?.lowercased() == expected.host?.lowercased()
            && normalizedPort(url) == normalizedPort(expected)
    }

    private static func normalizedPort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : nil)
    }
}

enum CodexRenderedPageLifecycleFailure: Equatable, Sendable {
    case navigationDenied
    case responseDenied
    case downloadDenied
    case navigationFailed
    case javaScriptFailed
    case invalidBridgeValue
    case bridgePayloadTooLarge
    case navigationTimeout
    case totalTimeout
}

@MainActor
final class CodexRenderedPageLifecycle: NSObject {
    static func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        return configuration
    }

    private let fixedURL: URL
    private let exactOrigin: String
    private let extractionScript: String
    private let maximumBridgePayloadBytes: Int
    private let navigationTimeout: Duration
    private let totalTimeout: Duration
    private let clock = ContinuousClock()
    private let onDidFinish: @MainActor (Duration) -> Void
    private let onPayload: @MainActor (Data, Duration) -> Void
    private let onFailure: @MainActor (CodexRenderedPageLifecycleFailure) -> Void

    private var webView: WKWebView?
    private var startedAt: ContinuousClock.Instant?
    private var generation = 0
    private var hasFinishedNavigation = false
    private var navigationDeadlineTask: Task<Void, Never>?
    private var totalDeadlineTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    init(
        fixedURL: URL,
        exactOrigin: String,
        extractionScript: String,
        maximumBridgePayloadBytes: Int,
        navigationTimeout: Duration,
        totalTimeout: Duration,
        pollInterval: Duration,
        stabilizationInterval: Duration,
        onDidFinish: @escaping @MainActor (Duration) -> Void,
        onPayload: @escaping @MainActor (Data, Duration) -> Void,
        onFailure: @escaping @MainActor (CodexRenderedPageLifecycleFailure) -> Void
    ) {
        precondition(pollInterval >= .milliseconds(250))
        precondition(stabilizationInterval >= .milliseconds(500))
        precondition(navigationTimeout > .zero)
        precondition(totalTimeout > .zero)
        self.fixedURL = fixedURL
        self.exactOrigin = exactOrigin
        self.extractionScript = extractionScript
        self.maximumBridgePayloadBytes = maximumBridgePayloadBytes
        self.navigationTimeout = navigationTimeout
        self.totalTimeout = totalTimeout
        self.onDidFinish = onDidFinish
        self.onPayload = onPayload
        self.onFailure = onFailure
        super.init()
    }

    func start() {
        stop()
        generation &+= 1
        let currentGeneration = generation
        startedAt = clock.now
        hasFinishedNavigation = false

        let webView = WKWebView(frame: .zero, configuration: Self.makeConfiguration())
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView

        navigationDeadlineTask = deadlineTask(
            after: navigationTimeout,
            generation: currentGeneration,
            failure: .navigationTimeout
        )
        totalDeadlineTask = deadlineTask(
            after: totalTimeout,
            generation: currentGeneration,
            failure: .totalTimeout
        )

        var request = URLRequest(url: fixedURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        webView.load(request)
    }

    func schedulePoll(after delay: Duration) {
        precondition(delay == .zero || delay >= .milliseconds(250))
        let expectedGeneration = generation
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            do {
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }
            } catch {
                return
            }
            guard let self,
                  generation == expectedGeneration,
                  let webView else {
                return
            }
            let value: Any?
            do {
                value = try await webView.evaluateJavaScript(extractionScript)
            } catch is CancellationError {
                return
            } catch {
                fail(.javaScriptFailed, generation: expectedGeneration)
                return
            }
            guard !Task.isCancelled, generation == expectedGeneration else { return }
            guard let payload = value as? String else {
                fail(.invalidBridgeValue, generation: expectedGeneration)
                return
            }
            guard payload != "__CODEX_RADAR_OVERSIZE__" else {
                fail(.bridgePayloadTooLarge, generation: expectedGeneration)
                return
            }
            let data = Data(payload.utf8)
            guard data.count <= maximumBridgePayloadBytes else {
                fail(.bridgePayloadTooLarge, generation: expectedGeneration)
                return
            }
            onPayload(data, elapsed)
        }
    }

    func stop() {
        generation &+= 1
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
    }

    deinit {
        navigationDeadlineTask?.cancel()
        totalDeadlineTask?.cancel()
        pollTask?.cancel()
        let webView = webView
        Task { @MainActor in
            webView?.stopLoading()
        }
    }

    private var elapsed: Duration {
        guard let startedAt else { return .zero }
        return startedAt.duration(to: clock.now)
    }

    private func deadlineTask(
        after duration: Duration,
        generation expectedGeneration: Int,
        failure: CodexRenderedPageLifecycleFailure
    ) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            self?.fail(failure, generation: expectedGeneration)
        }
    }

    private func fail(
        _ failure: CodexRenderedPageLifecycleFailure,
        generation expectedGeneration: Int? = nil,
        webView expectedWebView: WKWebView? = nil
    ) {
        guard expectedGeneration.map({ $0 == generation }) ?? true,
              expectedWebView.map({ $0 === webView }) ?? true,
              webView != nil else {
            return
        }
        stop()
        onFailure(failure)
    }
}

extension CodexRenderedPageLifecycle: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        let input = CodexRenderedPageNavigationPolicyInput(
            url: navigationAction.request.url ?? URL(filePath: "/"),
            type: CodexRenderedPageNavigationType(navigationAction.navigationType),
            targetFrameExists: navigationAction.targetFrame != nil,
            isMainFrame: navigationAction.targetFrame?.isMainFrame == true,
            shouldDownload: navigationAction.shouldPerformDownload
        )
        guard !hasFinishedNavigation,
              CodexRenderedPageNavigationPolicy.decide(
                input,
                exactOrigin: exactOrigin
              ) == .allow else {
            fail(
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
        let input = CodexRenderedPageResponsePolicyInput(
            url: navigationResponse.response.url ?? URL(filePath: "/"),
            isMainFrame: navigationResponse.isForMainFrame,
            canShowMIMEType: navigationResponse.canShowMIMEType
        )
        guard CodexRenderedPageNavigationPolicy.decide(
            input,
            exactOrigin: exactOrigin
        ) == .allow else {
            fail(.responseDenied, webView: webView)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView,
              !hasFinishedNavigation,
              let url = webView.url,
              CodexRenderedPageNavigationPolicy.isAllowedMainFrameURL(
                url,
                exactOrigin: exactOrigin
              ) else {
            fail(.navigationDenied, webView: webView)
            return
        }
        navigationDeadlineTask?.cancel()
        navigationDeadlineTask = nil
        hasFinishedNavigation = true
        onDidFinish(elapsed)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        fail(.navigationFailed, webView: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        fail(.navigationFailed, webView: webView)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        download.cancel()
        fail(.downloadDenied, webView: webView)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.cancel()
        fail(.downloadDenied, webView: webView)
    }
}

extension CodexRenderedPageLifecycle: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        fail(.navigationDenied, webView: webView)
        return nil
    }
}

private extension CodexRenderedPageNavigationType {
    init(_ type: WKNavigationType) {
        switch type {
        case .linkActivated: self = .linkActivated
        case .formSubmitted: self = .formSubmitted
        case .backForward: self = .backForward
        case .reload: self = .reload
        case .formResubmitted: self = .formResubmitted
        case .other: self = .other
        @unknown default: self = .linkActivated
        }
    }
}
