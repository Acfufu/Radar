import Foundation
import Testing
import WebKit
@testable import ClaudeRadar

@Suite("CodexRenderedWarningPageReaderTests")
struct CodexRenderedWarningPageReaderTests {
    private let capturedAt = Date(timeIntervalSince1970: 1_785_033_000)

    @MainActor
    @Test("production configuration is nonpersistent and extraction is fixed and bounded")
    func productionBoundary() {
        let configuration = CodexRenderedWarningPageReader.makeConfiguration()
        #expect(!configuration.websiteDataStore.isPersistent)
        #expect(CodexRenderedWarningPageReader.fixedURL.absoluteString == "https://codexradar.com/")

        let script = CodexRenderedWarningPageReader.extractionScript
        #expect(script.contains("[data-radar-degradation]"))
        #expect(script.contains("[data-radar-degradation-grid]"))
        #expect(script.contains("[data-radar-degradation-live]"))
        #expect(script.contains(":scope > article"))
        #expect(script.contains("JSON.stringify"))
        #expect(!script.contains("outerHTML"))
        #expect(!script.contains("document.body"))
        #expect(!script.lowercased().contains("drop12"))
        #expect(!script.contains("fetch("))
        #expect(!script.contains("XMLHttpRequest"))
        #expect(!script.contains("webkit.messageHandlers"))
    }

    @MainActor
    @Test("fixed script extracts the exact observed rendered card DOM through WebKit")
    func observedRenderedDOMExtraction() async throws {
        let html = """
        <!doctype html>
        <html>
          <body>
            <section data-radar-degradation aria-label="降智预警">
              <div data-radar-degradation-grid>
                <article class="degradation-card" data-severity="warning"
                         title="Sol xhigh · IQ 91.0">
                  <h3>Sol xhigh</h3>
                  <div class="degradation-card-score"><strong>91.0</strong> IQ</div>
                  <div class="degradation-deltas">
                    <span>24h ↓9.4</span>
                    <span>48h ↓9.4</span>
                  </div>
                </article>
              </div>
              <time data-radar-degradation-live>7/26 22:49</time>
            </section>
          </body>
        </html>
        """
        let data = try await extractedData(from: html)
        let snapshot = try CodexRenderedWarningDOMParser().parse(
            data,
            capturedAt: capturedAt
        )

        #expect(snapshot.cards.count == 1)
        let card = try #require(snapshot.cards.first)
        #expect(card.displayName == "Sol xhigh")
        #expect(card.family == "sol")
        #expect(card.effort == "xhigh")
        #expect(card.iq == 91.0)
        #expect(card.drop24h == 9.4)
        #expect(card.drop48h == 9.4)
        #expect(snapshot.sourceTimeLabel == "7/26 22:49")
    }

    @MainActor
    @Test("fixed script extracts an explicit-empty rendered DOM through WebKit")
    func observedExplicitEmptyDOMExtraction() async throws {
        let html = """
        <!doctype html>
        <html>
          <body>
            <section data-radar-degradation aria-label="降智预警">
              <div data-radar-degradation-grid>
                <p data-radar-degradation-empty>暂无预警</p>
              </div>
              <time data-radar-degradation-live>7/26 22:49</time>
            </section>
          </body>
        </html>
        """
        let data = try await extractedData(from: html)
        let snapshot = try CodexRenderedWarningDOMParser().parse(
            data,
            capturedAt: capturedAt
        )

        #expect(snapshot.cards.isEmpty)
        #expect(snapshot.sourceTimeLabel == "7/26 22:49")
    }

    @Test("navigation policy admits only initial and same-origin main-frame other navigation")
    func navigationPolicy() {
        let allowed = [
            action("https://codexradar.com/", type: .other),
            action("https://codexradar.com/?redirected=1", type: .other),
            action("https://codexradar.com:443/path", type: .other),
        ]
        for value in allowed {
            #expect(CodexRenderedWarningNavigationPolicy.decide(value) == .allow)
        }

        let denied = [
            action("http://codexradar.com/", type: .other),
            action("https://www.codexradar.com/", type: .other),
            action("https://codexradar.com:444/", type: .other),
            action("https://example.com/", type: .other),
            action("https://codexradar.com/", type: .linkActivated),
            action("https://codexradar.com/", type: .formSubmitted),
            action("https://codexradar.com/", type: .backForward),
            action("https://codexradar.com/", type: .reload),
            action("https://codexradar.com/", type: .other, targetFrameExists: false),
            action("https://codexradar.com/", type: .other, isMainFrame: false),
            action("https://codexradar.com/", type: .other, shouldDownload: true),
        ]
        for value in denied {
            #expect(CodexRenderedWarningNavigationPolicy.decide(value) == .cancel)
        }
    }

    @Test("main-frame response rejects off-host, downloads, and non-displayable content")
    func responsePolicy() {
        #expect(CodexRenderedWarningNavigationPolicy.decide(
            .init(url: URL(string: "https://codexradar.com/")!, isMainFrame: true, canShowMIMEType: true)
        ) == .allow)
        for value in [
            CodexRenderedWarningResponsePolicyInput(
                url: URL(string: "https://example.com/")!,
                isMainFrame: true,
                canShowMIMEType: true
            ),
            .init(
                url: URL(string: "https://codexradar.com/")!,
                isMainFrame: true,
                canShowMIMEType: false
            ),
        ] {
            #expect(CodexRenderedWarningNavigationPolicy.decide(value) == .cancel)
        }
    }

    @Test("valid cards stabilize only after two identical fingerprints at least 500ms apart")
    func identicalTwice() throws {
        var harness = DeterministicWebKitHarness()
        #expect(harness.didFinish(at: .zero) == .poll(after: .zero))
        #expect(try harness.sample("four-cards", at: .milliseconds(10)) == .poll(after: .milliseconds(250)))
        #expect(try harness.sample("four-cards", at: .milliseconds(260)) == .poll(after: .milliseconds(250)))

        let decision = try harness.sample("four-cards", at: .milliseconds(510))
        let snapshot = try #require(decision.snapshot)
        #expect(snapshot.cards.count == 4)
        #expect(snapshot.sourceTimeLabel == "数据更新于 2 分钟前")
    }

    @Test("explicit empty is stabilized as success")
    func explicitEmpty() throws {
        var harness = DeterministicWebKitHarness()
        _ = harness.didFinish(at: .zero)
        #expect(try harness.sample("explicit-empty", at: .zero) == .poll(after: .milliseconds(250)))
        let snapshot = try #require(
            try harness.sample("explicit-empty", at: .milliseconds(500)).snapshot
        )
        #expect(snapshot.cards.isEmpty)
    }

    @Test("one mutation resets the stabilization window")
    func mutationThenStable() throws {
        var harness = DeterministicWebKitHarness()
        _ = harness.didFinish(at: .zero)
        _ = try harness.sample("four-cards", at: .zero)
        #expect(try harness.sample("localized-time", at: .milliseconds(500)) == .poll(after: .milliseconds(250)))
        let snapshot = try #require(
            try harness.sample("localized-time", at: .milliseconds(1_000)).snapshot
        )
        #expect(snapshot.cards.count == 1)
    }

    @Test("continuous mutation reaches total timeout without publishing")
    func continuousMutationTimeout() throws {
        var harness = DeterministicWebKitHarness(totalTimeout: .seconds(2))
        _ = harness.didFinish(at: .zero)
        _ = try harness.sample("four-cards", at: .zero)
        _ = try harness.sample("localized-time", at: .milliseconds(500))
        _ = try harness.sample("four-cards", at: .milliseconds(1_000))
        _ = try harness.sample("localized-time", at: .milliseconds(1_500))
        #expect(harness.totalDeadline(at: .seconds(2)) == .failure(.totalTimeout))
        #expect(harness.publishedSnapshots == 0)
    }

    @Test("navigation and total deadlines are independently typed without wall-clock waits")
    func deadlines() {
        var navigationHarness = DeterministicWebKitHarness()
        #expect(navigationHarness.navigationDeadline(at: .seconds(15)) == .failure(.navigationTimeout))

        var totalHarness = DeterministicWebKitHarness()
        _ = totalHarness.didFinish(at: .seconds(1))
        #expect(totalHarness.totalDeadline(at: .seconds(20)) == .failure(.totalTimeout))
    }

    @Test("cancellation, deinit-equivalent stop, and late callbacks complete zero times")
    func cancellationAndLateCompletion() throws {
        var harness = DeterministicWebKitHarness()
        _ = harness.didFinish(at: .zero)
        _ = try harness.sample("four-cards", at: .zero)
        #expect(harness.cancel() == .failure(.cancelled))
        #expect(try harness.sample("four-cards", at: .seconds(1)) == .none)
        #expect(harness.totalDeadline(at: .seconds(20)) == .none)
        #expect(harness.publishedSnapshots == 0)

        var deinitHarness = DeterministicWebKitHarness()
        #expect(deinitHarness.stopForDeinit() == .failure(.cancelled))
        #expect(deinitHarness.navigationDeadline(at: .seconds(15)) == .none)
    }

    @MainActor
    @Test("an already-cancelled production read exits before creating a page")
    func alreadyCancelledRead() async {
        let reader = CodexRenderedWarningPageReader()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await reader.read()
        }

        do {
            _ = try await task.value
            Issue.record("cancelled read unexpectedly returned a snapshot")
        } catch let error as CodexRenderedWarningPageReaderError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("unexpected cancellation error: \(error)")
        }
    }

    @Test("oversize, schema drift, and challenge payloads are typed failures")
    func validationFailures() throws {
        var oversize = DeterministicWebKitHarness()
        _ = oversize.didFinish(at: .zero)
        let tooLarge = Data(
            repeating: 0x20,
            count: CodexRenderedWarningDOMParser.maximumBridgePayloadBytes + 1
        )
        #expect(oversize.sample(tooLarge, at: .zero) == .failure(
            .validation(.bridgePayloadTooLarge)
        ))

        for (fixture, error) in [
            ("missing-root", CodexRenderedWarningDOMParserError.missingRoot),
            ("challenge", .blockedPage),
        ] {
            var harness = DeterministicWebKitHarness()
            _ = harness.didFinish(at: .zero)
            #expect(try harness.sample(fixture, at: .zero) == .failure(.validation(error)))
            #expect(harness.publishedSnapshots == 0)
        }
    }

    private func action(
        _ url: String,
        type: CodexRenderedWarningNavigationType,
        targetFrameExists: Bool = true,
        isMainFrame: Bool = true,
        shouldDownload: Bool = false
    ) -> CodexRenderedWarningNavigationPolicyInput {
        .init(
            url: URL(string: url)!,
            type: type,
            targetFrameExists: targetFrameExists,
            isMainFrame: isMainFrame,
            shouldDownload: shouldDownload
        )
    }

    private func fixture(_ name: String) -> Data {
        let root = URL(filePath: #filePath).deletingLastPathComponent()
        return try! Data(
            contentsOf: root.appending(path: "Fixtures/CodexRenderedWarning/\(name).json")
        )
    }

    @MainActor
    private func extractedData(from html: String) async throws -> Data {
        let webView = WKWebView(
            frame: .zero,
            configuration: CodexRenderedWarningPageReader.makeConfiguration()
        )
        let observer = WebKitPageLoadObserver()
        webView.navigationDelegate = observer
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
        }

        try await observer.load(
            html,
            baseURL: CodexRenderedWarningPageReader.fixedURL,
            in: webView
        )
        let value = try await webView.evaluateJavaScript(
            CodexRenderedWarningPageReader.extractionScript
        )
        let json = try #require(value as? String)
        return Data(json.utf8)
    }

    private struct DeterministicWebKitHarness {
        private var stabilizer: CodexRenderedWarningStabilizer
        private(set) var publishedSnapshots = 0

        init(totalTimeout: Duration = .seconds(20)) {
            stabilizer = CodexRenderedWarningStabilizer(
                navigationTimeout: .seconds(15),
                totalTimeout: totalTimeout,
                pollInterval: .milliseconds(250),
                stabilizationInterval: .milliseconds(500)
            )
        }

        mutating func didFinish(at instant: Duration) -> CodexRenderedWarningReadDecision {
            stabilizer.didFinish(at: instant)
        }

        mutating func sample(
            _ name: String,
            at instant: Duration
        ) throws -> CodexRenderedWarningReadDecision {
            sample(fixture(name), at: instant)
        }

        mutating func sample(
            _ data: Data,
            at instant: Duration
        ) -> CodexRenderedWarningReadDecision {
            let decision = stabilizer.receive(data, capturedAt: capturedAt, at: instant)
            if decision.snapshot != nil {
                publishedSnapshots += 1
            }
            return decision
        }

        mutating func navigationDeadline(at instant: Duration) -> CodexRenderedWarningReadDecision {
            stabilizer.navigationDeadlineReached(at: instant)
        }

        mutating func totalDeadline(at instant: Duration) -> CodexRenderedWarningReadDecision {
            stabilizer.totalDeadlineReached(at: instant)
        }

        mutating func cancel() -> CodexRenderedWarningReadDecision {
            stabilizer.cancel()
        }

        mutating func stopForDeinit() -> CodexRenderedWarningReadDecision {
            stabilizer.cancel()
        }

        private func fixture(_ name: String) -> Data {
            let root = URL(filePath: #filePath).deletingLastPathComponent()
            return try! Data(
                contentsOf: root.appending(path: "Fixtures/CodexRenderedWarning/\(name).json")
            )
        }

        private var capturedAt: Date {
            Date(timeIntervalSince1970: 1_785_033_000)
        }
    }
}

@MainActor
private final class WebKitPageLoadObserver: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, any Error>?

    func load(_ html: String, baseURL: URL, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private extension CodexRenderedWarningReadDecision {
    var snapshot: CodexRenderedWarningSnapshot? {
        guard case let .success(snapshot) = self else { return nil }
        return snapshot
    }
}
