import Foundation
import Testing
import WebKit
@testable import AIRadar

@Suite("CodexRenderedIQHistoryPageReaderTests")
struct CodexRenderedIQHistoryPageReaderTests {
    private let capturedAt = Date(timeIntervalSince1970: 1_785_033_000)

    @MainActor
    @Test("production boundary is anonymous exact-origin DOM-only WebKit")
    func productionBoundary() {
        let configuration = CodexRenderedIQHistoryPageReader.makeConfiguration()
        #expect(!configuration.websiteDataStore.isPersistent)
        #expect(CodexRenderedIQHistoryPageReader.fixedURL.absoluteString == "https://deng.codexradar.com/")

        let script = CodexRenderedIQHistoryPageReader.extractionScript
        #expect(script.contains(".iq-range button[data-iq-hours=\"24\"]"))
        #expect(script.contains("#iq-body.iq"))
        #expect(!script.contains("#iqbody, .iq"))
        #expect(script.contains(".iqcard.total-iq"))
        #expect(script.contains(".iqcard[data-model]"))
        #expect(script.contains(".iq-trend-hit[data-trend-label]"))
        #expect(script.contains("aria-label"))
        #expect(!script.contains("svg.iq-trend-svg"))
        #expect(script.contains("getBoundingClientRect"))
        #expect(!script.contains("sourceOrder === 0"))
        #expect(script.contains("JSON.stringify"))
        #expect(!script.contains("outerHTML"))
        #expect(!script.contains("document.body"))
        #expect(!script.contains("fetch("))
        #expect(!script.contains("XMLHttpRequest"))
        #expect(!script.contains("PerformanceObserver"))
        #expect(!script.contains("webkit.messageHandlers"))
    }

    @MainActor
    @Test("visible 24h selection hydrates and extracts five ordered series through WebKit")
    func hydrationAndSelection() async throws {
        let html = """
        <!doctype html><html><head>
          <style>.iqcard { width: 240px; } .iq-trend-svg { width: 180px; height: 40px; }</style>
        </head><body>
          <div class="iq-range">
            <button data-iq-hours="24" aria-pressed="false">24h</button>
            <button data-iq-hours="48" aria-pressed="true">48h</button>
          </div>
          <div class="iq"><div class="iqcard total-iq">unrelated root</div></div>
          <div id="iq-body" class="iq">
            <div class="iqcard"><div class="m">unrelated</div></div>
            <div class="iqcard total-iq" hidden>
              <div class="m">hidden total</div>
              <svg class="iq-trend-svg" aria-label="最近 24h IQ 趋势"></svg>
            </div>
            <div class="iqcard" data-model="wrong-window">
              <div class="m">wrong window</div>
              <svg class="iq-trend-svg" aria-label="最近 48h IQ 趋势"></svg>
            </div>
          </div>
          <script>
            document.querySelector('[data-iq-hours="24"]').addEventListener("click", () => {
              document.querySelector('[data-iq-hours="24"]').setAttribute("aria-pressed", "true");
              document.querySelector('[data-iq-hours="48"]').setAttribute("aria-pressed", "false");
              setTimeout(() => {
                const body = document.getElementById("iq-body");
                body.insertAdjacentHTML("beforeend", Array.from({length: 5}, (_, cardIndex) => {
                  const model = cardIndex ? ` data-model="gpt-5.6-${["sol","terra","luna","old"][cardIndex - 1]}"` : "";
                  const classes = cardIndex ? "iqcard model-iq-card" : "iqcard total-iq";
                  const name = cardIndex ? ["Sol","Terra","Luna","Old"][cardIndex - 1] : "GPT-5.6 全模型";
                  const trendLabel = cardIndex === 4 ? "Recent 24h IQ trend" : "最近 24h IQ 趋势";
                  const svgClass = cardIndex === 4 ? "" : ` class="iq-trend-svg"`;
                  const points = Array.from({length: 24}, (_, pointIndex) =>
                    `<circle class="iq-trend-hit" data-trend-label="07/27 ${String(pointIndex).padStart(2, "0")}:00 · ${100 + cardIndex + pointIndex / 10} IQ"></circle>`
                  ).join("");
                  return `<div class="${classes}"${model}><div class="m">${name}</div><svg${svgClass} aria-label="${trendLabel}">${points}</svg></div>`;
                }).join(""));
              }, 25);
            });
          </script>
        </body></html>
        """
        let webView = try await loaded(html)
        defer { cleanup(webView) }

        _ = try await extractedData(from: webView)
        try await Task.sleep(for: .milliseconds(300))
        let data = try await extractedData(from: webView)
        let snapshot = try CodexRenderedIQHistoryDOMParser().parse(data, capturedAt: capturedAt)

        #expect(snapshot.series.count == 5)
        #expect(snapshot.series.map(\.sourceOrder) == [0, 1, 2, 3, 4])
        #expect(snapshot.series.map(\.seriesKey) == [
            "aggregate", "model:gpt-5.6-sol", "model:gpt-5.6-terra",
            "model:gpt-5.6-luna", "model:gpt-5.6-old",
        ])
        #expect(snapshot.series.allSatisfy { $0.points.count == 24 })
    }

    @MainActor
    @Test("a visible total card whose accessible name says 48h fails closed")
    func wrongWindowAccessibleNameFailsClosed() async throws {
        let points = (0..<24).map {
            "<circle class=\"iq-trend-hit\" data-trend-label=\"07/27 \(String(format: "%02d", $0)):00 · \(100 + $0) IQ\"></circle>"
        }.joined()
        let html = """
        <!doctype html><html><head>
          <style>.iqcard { width: 240px; } .iq-trend-svg { width: 180px; height: 40px; }</style>
        </head><body>
          <div class="iq-range">
            <button data-iq-hours="24" aria-pressed="true">24h</button>
          </div>
          <div id="iqbody" class="iq">
            <div class="iqcard total-iq">
              <div class="m">GPT-5.6 全模型</div>
              <svg class="iq-trend-svg" aria-label="最近 48h IQ 趋势">\(points)</svg>
            </div>
            <div class="iqcard model-iq-card" data-model="gpt-5.6-sol">
              <div class="m">Sol</div>
              <svg class="iq-trend-svg" aria-label="Recent 24h IQ trend">\(points)</svg>
            </div>
          </div>
        </body></html>
        """
        let webView = try await loaded(html)
        defer { cleanup(webView) }
        let data = try await extractedData(from: webView)

        #expect(throws: CodexRenderedIQHistoryDOMParserError.self) {
            _ = try CodexRenderedIQHistoryDOMParser().parse(data, capturedAt: capturedAt)
        }
    }

    @Test("exact-origin main-frame policy denies off-host popup and download")
    func navigationPolicy() {
        #expect(CodexRenderedIQHistoryNavigationPolicy.decide(action(
            "https://deng.codexradar.com/?redirected=1"
        )) == .allow)
        for input in [
            action("https://codexradar.com/"),
            action("https://www.deng.codexradar.com/"),
            action("http://deng.codexradar.com/"),
            action("https://deng.codexradar.com/", targetFrameExists: false),
            action("https://deng.codexradar.com/", shouldDownload: true),
        ] {
            #expect(CodexRenderedIQHistoryNavigationPolicy.decide(input) == .cancel)
        }
        #expect(CodexRenderedIQHistoryNavigationPolicy.decide(
            CodexRenderedIQHistoryResponsePolicyInput(
                url: URL(string: "https://deng.codexradar.com/")!,
                isMainFrame: true,
                canShowMIMEType: true
            )
        ) == .allow)
        #expect(CodexRenderedIQHistoryNavigationPolicy.decide(
            CodexRenderedIQHistoryResponsePolicyInput(
                url: URL(string: "https://example.com/")!,
                isMainFrame: true,
                canShowMIMEType: true
            )
        ) == .cancel)
    }

    @Test("24-point snapshots stabilize after 500ms; mutation resets and deadlines are typed")
    func stabilizationAndDeadlines() throws {
        var stable = DeterministicHarness()
        #expect(stable.didFinish(at: .zero) == .poll(after: .zero))
        #expect(try stable.sample("valid-24h", at: .zero) == .poll(after: .milliseconds(250)))
        #expect(try stable.sample("valid-24h", at: .milliseconds(499)) == .poll(after: .milliseconds(250)))
        #expect(try stable.sample("valid-24h", at: .milliseconds(500)).snapshot?.series.count == 3)

        var mutation = DeterministicHarness(totalTimeout: .seconds(2))
        _ = mutation.didFinish(at: .zero)
        for index in 0..<8 {
            _ = try mutation.sample(
                index.isMultiple(of: 2) ? "valid-24h" : "prompt-like-text",
                at: .milliseconds(250 * index)
            )
        }
        #expect(mutation.totalDeadline(at: .seconds(2)) == .failure(.totalTimeout))
        #expect(mutation.publishedSnapshots == 0)

        var navigation = DeterministicHarness()
        #expect(navigation.navigationDeadline(at: .seconds(15)) == .failure(.navigationTimeout))
    }

    @Test("23 points, 48h selection, off-host and oversize are typed failures")
    func validationFailures() throws {
        for (fixture, expected) in [
            ("partial-23", CodexRenderedIQHistoryDOMParserError.invalidPointCount(seriesIndex: 0)),
            ("wrong-range", .invalidSelectedRange),
            ("off-host", .invalidFinalOrigin),
            ("challenge", .blockedPage),
        ] {
            var harness = DeterministicHarness()
            _ = harness.didFinish(at: .zero)
            #expect(try harness.sample(fixture, at: .zero) == .failure(.validation(expected)))
        }

        var oversize = DeterministicHarness()
        _ = oversize.didFinish(at: .zero)
        #expect(oversize.sample(
            Data(repeating: 0x20, count: CodexRenderedIQHistoryDOMParser.maximumBridgePayloadBytes + 1),
            at: .zero
        ) == .failure(.validation(.bridgePayloadTooLarge)))
    }

    @Test("cancel and late callbacks publish zero snapshots")
    func cancellation() throws {
        var harness = DeterministicHarness()
        _ = harness.didFinish(at: .zero)
        _ = try harness.sample("valid-24h", at: .zero)
        #expect(harness.cancel() == .failure(.cancelled))
        #expect(try harness.sample("valid-24h", at: .seconds(1)) == .none)
        #expect(harness.totalDeadline(at: .seconds(20)) == .none)
        #expect(harness.publishedSnapshots == 0)
    }

    @MainActor
    @Test("already-cancelled production read creates no page")
    func alreadyCancelledRead() async {
        let reader = CodexRenderedIQHistoryPageReader()
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await reader.read()
        }
        await #expect(throws: CodexRenderedIQHistoryPageReaderError.cancelled) {
            _ = try await task.value
        }
    }

    private func action(
        _ value: String,
        targetFrameExists: Bool = true,
        shouldDownload: Bool = false
    ) -> CodexRenderedIQHistoryNavigationPolicyInput {
        .init(
            url: URL(string: value)!,
            type: .other,
            targetFrameExists: targetFrameExists,
            isMainFrame: true,
            shouldDownload: shouldDownload
        )
    }

    private func fixture(_ name: String) -> Data {
        let root = URL(filePath: #filePath).deletingLastPathComponent()
        return try! Data(contentsOf: root.appending(path: "Fixtures/CodexRenderedIQHistory/\(name).json"))
    }

    @MainActor
    private func loaded(_ html: String) async throws -> WKWebView {
        let webView = WKWebView(
            frame: .zero,
            configuration: CodexRenderedIQHistoryPageReader.makeConfiguration()
        )
        let observer = IQHistoryPageLoadObserver()
        webView.navigationDelegate = observer
        try await observer.load(
            html,
            baseURL: CodexRenderedIQHistoryPageReader.fixedURL,
            in: webView
        )
        webView.navigationDelegate = nil
        return webView
    }

    @MainActor
    private func extractedData(from webView: WKWebView) async throws -> Data {
        let value = try await webView.evaluateJavaScript(
            CodexRenderedIQHistoryPageReader.extractionScript
        )
        return Data(try #require(value as? String).utf8)
    }

    @MainActor
    private func cleanup(_ webView: WKWebView) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    private struct DeterministicHarness {
        private var stabilizer = CodexRenderedIQHistoryStabilizer()
        private(set) var publishedSnapshots = 0

        init(totalTimeout: Duration = .seconds(20)) {
            stabilizer = CodexRenderedIQHistoryStabilizer(totalTimeout: totalTimeout)
        }

        mutating func didFinish(at instant: Duration) -> CodexRenderedIQHistoryReadDecision {
            stabilizer.didFinish(at: instant)
        }

        mutating func sample(_ name: String, at instant: Duration) throws -> CodexRenderedIQHistoryReadDecision {
            sample(fixture(name), at: instant)
        }

        mutating func sample(_ data: Data, at instant: Duration) -> CodexRenderedIQHistoryReadDecision {
            let decision = stabilizer.receive(data, capturedAt: capturedAt, at: instant)
            if decision.snapshot != nil { publishedSnapshots += 1 }
            return decision
        }

        mutating func navigationDeadline(at instant: Duration) -> CodexRenderedIQHistoryReadDecision {
            stabilizer.navigationDeadlineReached(at: instant)
        }

        mutating func totalDeadline(at instant: Duration) -> CodexRenderedIQHistoryReadDecision {
            stabilizer.totalDeadlineReached(at: instant)
        }

        mutating func cancel() -> CodexRenderedIQHistoryReadDecision {
            stabilizer.cancel()
        }

        private var capturedAt: Date { Date(timeIntervalSince1970: 1_785_033_000) }

        private func fixture(_ name: String) -> Data {
            let root = URL(filePath: #filePath).deletingLastPathComponent()
            return try! Data(contentsOf: root.appending(path: "Fixtures/CodexRenderedIQHistory/\(name).json"))
        }
    }
}

private extension CodexRenderedIQHistoryReadDecision {
    var snapshot: CodexRenderedIQHistorySnapshot? {
        guard case let .success(value) = self else { return nil }
        return value
    }
}

@MainActor
private final class IQHistoryPageLoadObserver: NSObject, WKNavigationDelegate {
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
}
