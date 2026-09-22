import Foundation
import Testing
@testable import AIRadar

/// Data-age annotation tests (spec §4.2 v1.3 note): level mapping, wording
/// branches, and the tolerant upstream timestamp parse. Threshold reuses
/// `SyncPolicy().staleInterval` — no new constants.
@Suite("DataAgeBadgeTests")
struct DataAgeBadgeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let staleAfter = SyncPolicy().staleInterval

    private func content(
        updatedAt: Date?,
        channelFresh: Bool = true
    ) -> DataAgeBadge.Content {
        .init(label: "额度数据", updatedAt: updatedAt, channelFresh: channelFresh, staleAfter: staleAfter, now: now)
    }

    @Test("nil timestamp maps to muted and renders nothing")
    func nilTimestampIsMuted() {
        let content = content(updatedAt: nil)
        #expect(content.level == .muted)
        #expect(content.updatedAt == nil)
    }

    @Test("field age inside the stale interval is fresh regardless of channel")
    func freshFieldMapsToFresh() {
        let recent = now.addingTimeInterval(-60)
        #expect(content(updatedAt: recent, channelFresh: true).level == .fresh)
        #expect(content(updatedAt: recent, channelFresh: false).level == .fresh)
    }

    @Test("stale field with a fresh channel calls out the upstream stall")
    func staleFieldWithFreshChannel() {
        let old = now.addingTimeInterval(-43 * 24 * 60 * 60)
        let content = content(updatedAt: old, channelFresh: true)
        #expect(content.level == .stale)
        let wording = content.wording(updatedAt: old, relative: "43天前")
        #expect(wording.contains("额度数据"))
        #expect(wording.contains("上游"))
        #expect(wording.contains("未更新"))
        #expect(wording.contains("同步正常"))
        #expect(wording.contains("43天前"))
    }

    @Test("stale field with a stale channel reports the combined lag")
    func staleFieldWithStaleChannel() {
        let old = now.addingTimeInterval(-8 * 24 * 60 * 60)
        let content = content(updatedAt: old, channelFresh: false)
        #expect(content.level == .stale)
        let wording = content.wording(updatedAt: old, relative: "8天前")
        #expect(wording.contains("最后更新"))
        #expect(wording.contains("本地同步同样滞后"))
        #expect(!wording.contains("同步正常"))
    }

    @Test("upstream timestamps parse with and without fractional seconds")
    func tolerantTimestampParse() {
        let fractional = RadarFormat.parseUpstreamTimestamp("2026-09-14T13:05:52.704532+08:00")
        #expect(fractional != nil)
        let plain = RadarFormat.parseUpstreamTimestamp("2026-09-21T10:20:55+08:00")
        #expect(plain != nil)
        #expect(RadarFormat.parseUpstreamTimestamp(nil) == nil)
        #expect(RadarFormat.parseUpstreamTimestamp("not-a-date") == nil)
    }
}
