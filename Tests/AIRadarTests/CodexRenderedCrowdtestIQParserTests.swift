import CryptoKit
import Foundation
import Testing
@testable import AIRadar

/// v0.4.0 crowdtest IQ parser + contract tests (spec §6 v1.2, ADR-0004):
/// the probe-derived canonical fixture, synthetic adversarial payloads, the
/// sanitization boundary, five-family mapping, and trend-label parsing.
@Suite("CodexRenderedCrowdtestIQParserTests")
struct CodexRenderedCrowdtestIQParserTests {
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func canonicalFixtureData() throws -> Data {
        try Data(contentsOf: root.appending(path: "Tests/AIRadarTests/Fixtures/CodexRenderedCrowdtestIQ/crowdtest-iq.json"))
    }

    private func dto(
        revision: String = CodexRenderedCrowdtestIQDOMParser.parserRevision,
        origin: String = "https://deng.codexradar.com",
        pageState: String = "ready",
        harnesses: String
    ) -> Data {
        Data("""
        {"revision":"\(revision)","finalOrigin":"\(origin)","pageState":"\(pageState)","harnesses":\(harnesses)}
        """.utf8)
    }

    @Test("canonical fixture matches its recorded SHA-256 and parses all five families")
    func canonicalFixtureParses() throws {
        let data = try canonicalFixtureData()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let recorded = try String(contentsOf: root.appending(
            path: "Tests/AIRadarTests/Fixtures/CodexRenderedCrowdtestIQ/SHA256SUMS"
        ), encoding: .utf8).split(separator: " ").first.map(String.init)
        #expect(recorded == digest)

        let capturedAt = Date(timeIntervalSince1970: 1_752_566_500)
        let snapshot = try CodexRenderedCrowdtestIQDOMParser().parse(data, capturedAt: capturedAt)

        #expect(snapshot.sourceID == .codexRadar)
        #expect(snapshot.parserRevision == "deng-rendered-crowdtest-iq-v1")
        #expect(snapshot.finalOrigin == "https://deng.codexradar.com")
        #expect(snapshot.capturedAt == capturedAt)
        // Five-station mapping (ADR-0004): only mapped families survive —
        // one card per model, so a family may appear multiple times
        // (2026-09-20 probe: codex×7, zcode×2, dsh×3, claude-code×2, grok×1).
        #expect(snapshot.harnesses.map(\.harness) == [
            "codex", "codex", "codex", "codex", "codex", "zcode", "zcode",
            "codex", "codex", "dsh", "dsh", "dsh", "claude-code", "claude-code", "grok",
        ])
        let codex = try #require(snapshot.harnesses.first)
        // 2026-09-20 probe: gpt-6-astra/ultra cell with IQ 108 and 70 total cells
        // across the five families (per-card model counts preserved).
        #expect(codex.cells.first?.model == "gpt-6-astra")
        #expect(codex.cells.first?.effort == "ultra")
        #expect(codex.cells.first?.iqScore == 108)
        #expect(codex.cells.first?.totalTasks == 112)
        let totalCells = snapshot.harnesses.reduce(0) { $0 + $1.cells.count }
        // 70 total upstream cells minus the 15 on unmapped families.
        #expect(totalCells == 55)
        #expect(snapshot.semanticFingerprint.count == 64)
    }

    @Test("adversarial payloads reject: origin, revision, blocked, truncated, login wall")
    func adversarialPayloads() throws {
        let parser = CodexRenderedCrowdtestIQDOMParser()
        let cells = """
        [{"harness":"codex","cells":[{"model":"m","effort":"high","iqScore":80,"iqP":1,"iqN":1,"countP":1,"countN":1,"coveredTasks":1,"totalTasks":2,"coverageInsufficient":false,"methodTitle":""}],"circles":[]}]
        """
        #expect(throws: CodexRenderedCrowdtestIQDOMParserError.invalidFinalOrigin.self) {
            try parser.parse(dto(origin: "https://evil.example", harnesses: cells), capturedAt: .now)
        }
        #expect(throws: CodexRenderedCrowdtestIQDOMParserError.revisionMismatch.self) {
            try parser.parse(dto(revision: "deng-rendered-crowdtest-iq-v0", harnesses: cells), capturedAt: .now)
        }
        #expect(throws: CodexRenderedCrowdtestIQDOMParserError.blockedPage.self) {
            try parser.parse(dto(pageState: "challenge", harnesses: cells), capturedAt: .now)
        }
        #expect(throws: CodexRenderedCrowdtestIQDOMParserError.bridgePayloadTooLarge.self) {
            try parser.parse(Data(count: CodexRenderedCrowdtestIQDOMParser.maximumBridgePayloadBytes + 1), capturedAt: .now)
        }
        #expect(throws: CodexRenderedCrowdtestIQDOMParserError.invalidPayload.self) {
            try parser.parse(Data("{not json".utf8), capturedAt: .now)
        }
        // The login wall renders as a ready page with zero cells: pending.
        #expect(throws: CodexRenderedCrowdtestIQDOMParserError.contentPending.self) {
            try parser.parse(dto(harnesses: "[]"), capturedAt: .now)
        }
        // Unmapped families only → nothing adoptable → pending.
        let unmapped = """
        [{"harness":"kimi-code","cells":[{"model":"k","effort":"max","iqScore":90,"iqP":1,"iqN":1,"countP":1,"countN":1,"coveredTasks":1,"totalTasks":2,"coverageInsufficient":false,"methodTitle":""}],"circles":[]}]
        """
        #expect(throws: CodexRenderedCrowdtestIQDOMParserError.contentPending.self) {
            try parser.parse(dto(harnesses: unmapped), capturedAt: .now)
        }
    }

    @Test("unmapped families are dropped; mapped families keep cells and trend labels parse")
    func mappingAndTrendLabels() throws {
        let harnesses = """
        [
          {"harness":"antigravity","cells":[{"model":"g","effort":"high","iqScore":93,"iqP":1,"iqN":1,"countP":1,"countN":1,"coveredTasks":1,"totalTasks":2,"coverageInsufficient":false,"methodTitle":""}],"circles":[]},
          {"harness":"grok","cells":[{"model":"grok-4.6","effort":"xhigh","iqScore":108,"iqP":9,"iqN":11,"countP":9,"countN":11,"coveredTasks":10,"totalTasks":112,"coverageInsufficient":false,"methodTitle":"IQ：每格最近 3 次"}],"circles":["09/19 07:00 · 106.6 IQ","bad-label"]},
          {"harness":"claude-code","cells":[{"model":"claude-sonnet-5","effort":"max","iqScore":0,"iqP":0,"iqN":1,"countP":0,"countN":1,"coveredTasks":1,"totalTasks":112,"coverageInsufficient":true,"methodTitle":""}],"circles":[]}
        ]
        """
        let snapshot = try CodexRenderedCrowdtestIQDOMParser().parse(dto(harnesses: harnesses), capturedAt: .now)
        #expect(snapshot.harnesses.map(\.harness) == ["grok", "claude-code"])

        let grok = try #require(snapshot.harnesses.first)
        #expect(grok.model == "grok-4.6")
        #expect(grok.cells.first?.methodTitle == "IQ：每格最近 3 次")

        // "09/19 07:00 · 106.6 IQ" → month 9, day 19, hour 7, score 106.6.
        let trend = grok.trend[0]
        #expect(trend.month == 9)
        #expect(trend.day == 19)
        #expect(trend.hour == 7)
        #expect(trend.score == 106.6)
        // A malformed label is kept verbatim with nil components.
        #expect(grok.trend[1].month == nil)
    }

    @Test("fingerprint is insensitive to capture time and sensitive to content")
    func fingerprintBehavior() throws {
        let data = try canonicalFixtureData()
        let a = try CodexRenderedCrowdtestIQDOMParser().parse(data, capturedAt: Date(timeIntervalSince1970: 100))
        let b = try CodexRenderedCrowdtestIQDOMParser().parse(data, capturedAt: Date(timeIntervalSince1970: 200))
        #expect(a.semanticFingerprint == b.semanticFingerprint)
        let fa = try ContentFingerprint.crowdtestIQ(a)
        let fb = try ContentFingerprint.crowdtestIQ(b)
        #expect(fa == fb)

        var mutated = b
        let changed = CodexRenderedCrowdtestIQHarness(
            harness: "grok",
            model: "grok-4.6",
            cells: [CodexRenderedCrowdtestIQCell(
                model: "grok-4.6", effort: "xhigh", iqScore: 109, iqP: 9, iqN: 11,
                countP: 9, countN: 11, coveredTasks: 10, totalTasks: 112,
                coverageInsufficient: false, methodTitle: ""
            )],
            trend: []
        )
        mutated = CodexRenderedCrowdtestIQSnapshot(
            sourceID: b.sourceID,
            parserRevision: b.parserRevision,
            finalOrigin: b.finalOrigin,
            capturedAt: b.capturedAt,
            harnesses: b.harnesses + [changed],
            semanticFingerprint: b.semanticFingerprint
        )
        let fm = try ContentFingerprint.crowdtestIQ(mutated)
        #expect(fm != fb)
    }

    @Test("sanitization boundary: no markup, credential, or endpoint material in fixtures or parser")
    func sanitizationBoundary() throws {
        let fixture = try String(decoding: canonicalFixtureData(), as: UTF8.self)
        for forbidden in ["<html", "<script", "</script", "cookie", "authorization", "api_key", "api-key", "bearer ", "endpoint", "/api/"] {
            let fixtureLower = fixture.lowercased()
        #expect(!fixtureLower.contains(forbidden), "fixture must not contain \(forbidden)")
        }
        let reader = try String(
            contentsOf: root.appending(path: "Sources/AIRadar/Sources/CodexRadar/CodexRenderedCrowdtestIQPageReader.swift"),
            encoding: .utf8
        )
        // The extraction script reads rendered attributes only — no fetch,
        // no XHR, no interception (ADR-0004 exclusions).
        #expect(!reader.contains("fetch("))
        #expect(!reader.contains("XMLHttpRequest"))
        #expect(reader.contains("WKWebsiteDataStore") == false) // lifecycle owns the store
        let lifecycle = try String(
            contentsOf: root.appending(path: "Sources/AIRadar/Sources/CodexRadar/CodexRenderedPageLifecycle.swift"),
            encoding: .utf8
        )
        #expect(lifecycle.contains("nonPersistent()"))
    }
}
