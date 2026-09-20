import Foundation
import Testing
@testable import AIRadar

/// v0.4.0 crowdtest IQ card mapping tests (spec §4.1 v1.2 / §6 v1.2):
/// harness→station mapping, nil-data empty state, unmapped-family exclusion,
/// and per-card freshness level.
@Suite("CrowdtestIQCardTests")
struct CrowdtestIQCardTests {
    private func snapshot(harnesses: [CodexRenderedCrowdtestIQHarness], stale: Bool = false, error: String? = nil) -> SegmentState<CodexRenderedCrowdtestIQSnapshot> {
        let snapshot = CodexRenderedCrowdtestIQSnapshot(
            sourceID: .codexRadar,
            parserRevision: CodexRenderedCrowdtestIQDOMParser.parserRevision,
            finalOrigin: "https://deng.codexradar.com",
            capturedAt: Date(timeIntervalSince1970: 100),
            harnesses: harnesses,
            semanticFingerprint: "fingerprint"
        )
        return SegmentState(
            value: snapshot,
            lastSuccessfulAt: Date(timeIntervalSince1970: 90),
            lastAttemptedAt: Date(timeIntervalSince1970: 100),
            error: error.map { SegmentError(kind: .validation, message: $0) },
            isStale: stale
        )
    }

    private func harness(_ key: String, iq: Double?) -> CodexRenderedCrowdtestIQHarness {
        .init(
            harness: key,
            model: "m",
            cells: [.init(
                model: "m", effort: "high", iqScore: iq, iqP: 1, iqN: 1,
                countP: 1, countN: 1, coveredTasks: 2, totalTasks: 112,
                coverageInsufficient: iq == nil, methodTitle: ""
            )],
            trend: []
        )
    }

    @Test("mapping selects the station's family and keeps rows and trend")
    func mapping() throws {
        let state = snapshot(harnesses: [harness("codex", iq: 108), harness("zcode", iq: 97)])
        let codex = try #require(CrowdtestIQCardMapper.model(harness: "codex", state: state))
        #expect(codex.rows.count == 1)
        #expect(codex.rows[0].iq == 108)
        #expect(codex.isEmpty == false)
        #expect(codex.level == .fresh)
        #expect(CrowdtestIQCardMapper.model(harness: "grok", state: state) == nil)
    }

    @Test("nil snapshot and unmapped families render the empty state")
    func nilData() {
        #expect(CrowdtestIQCardMapper.model(harness: "codex", state: nil) == nil)
        let empty = CrowdtestIQCardMapper.model(harness: "dsh", state: snapshot(harnesses: []))
        #expect(empty == nil)
    }

    @Test("level follows the segment state: fresh, stale, error")
    func levels() throws {
        let fresh = try #require(CrowdtestIQCardMapper.model(harness: "codex", state: snapshot(harnesses: [harness("codex", iq: 80)])))
        #expect(fresh.level == .fresh)
        let stale = try #require(CrowdtestIQCardMapper.model(
            harness: "codex",
            state: snapshot(harnesses: [harness("codex", iq: 80)], stale: true)
        ))
        #expect(stale.level == .stale)
        let errored = try #require(CrowdtestIQCardMapper.model(
            harness: "codex",
            state: snapshot(harnesses: [harness("codex", iq: 80)], error: "challenge")
        ))
        #expect(errored.level == .error)
        // Coverage-insufficient rows still map, flagged for display.
        let insufficient = try #require(CrowdtestIQCardMapper.model(harness: "claude-code", state: snapshot(harnesses: [harness("claude-code", iq: nil)])))
        #expect(insufficient.rows[0].coverageInsufficient)
    }
}
