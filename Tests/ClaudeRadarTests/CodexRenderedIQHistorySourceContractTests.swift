import CryptoKit
import Foundation
import Testing

@Suite("CodexRenderedIQHistorySourceContractTests")
struct CodexRenderedIQHistorySourceContractTests {
    private let root = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private let fixtureNames = [
        "valid-24h", "partial-23", "duplicate-series", "duplicate-point", "wrong-range",
        "missing-aggregate", "off-host", "challenge", "prompt-like-text", "oversized",
    ]

    @Test("sanitized rendered-IQ fixture corpus is checksum-frozen")
    func fixtureChecksumsAndSanitization() throws {
        let checksums = try checksumManifest()
        #expect(Set(checksums.keys) == Set(fixtureNames.map { "\($0).json" }))

        for name in fixtureNames {
            let data = try fixture(name)
            #expect(data.count > 20)
            #expect(try JSONSerialization.jsonObject(with: data) is [String: Any])
            #expect(checksums["\(name).json"] == sha256(data))

            let lowered = String(decoding: data, as: UTF8.self).lowercased()
            for forbidden in [
                "<html", "<script", "</script", "cookie", "authorization", "api_key",
                "api-key", "bearer ", "@", "endpoint", "/api/",
            ] {
                #expect(!lowered.contains(forbidden))
            }
        }
    }

    @Test("valid 24h bridge locks exact distributed origin and ordered series")
    func validBridgeContract() throws {
        let root = try json("valid-24h")
        #expect(root["revision"] as? String == "codex-radar-rendered-iq-history-v1")
        #expect(root["finalOrigin"] as? String == "https://deng.codexradar.com")
        #expect(root["rootPresent"] as? Bool == true)
        #expect(root["selectedRange"] as? String == "24h")
        #expect(root["pageState"] as? String == "ready")

        let series = try #require(root["series"] as? [[String: Any]])
        #expect((2...8).contains(series.count))
        #expect(series.filter { $0["seriesKey"] as? String == "aggregate" }.count == 1)
        #expect(series.map { $0["sourceOrder"] as? Int } == Array(0..<series.count))

        for item in series {
            let key = try #require(item["seriesKey"] as? String)
            #expect(key == "aggregate" || key.hasPrefix("model:"))
            #expect(!(item["displayName"] as? String ?? "").isEmpty)
            let points = try #require(item["points"] as? [[String: Any]])
            #expect(points.count == 24)
            #expect(points.map { $0["sourceOrder"] as? Int } == Array(0..<24))
            for point in points {
                #expect(!(point["sourceTimeLabel"] as? String ?? "").isEmpty)
                #expect((0...150).contains(point["iq"] as? Double ?? -.infinity))
                #expect(point["n"] == nil)
                #expect(point["date"] == nil)
            }
        }
    }

    @Test("adversarial corpus freezes fail-closed bridge cases")
    func adversarialBridgeContract() throws {
        let partial = try series("partial-23")
        #expect(partial.first?["points"].flatMap { $0 as? [[String: Any]] }?.count == 23)

        let duplicateSeries = try series("duplicate-series")
        let keys = duplicateSeries.compactMap { $0["seriesKey"] as? String }
        #expect(Set(keys).count != keys.count)

        let duplicatePoints = try #require(try series("duplicate-point").first?["points"] as? [[String: Any]])
        let orders = duplicatePoints.compactMap { $0["sourceOrder"] as? Int }
        #expect(Set(orders).count != orders.count)

        #expect(try json("wrong-range")["selectedRange"] as? String == "48h")
        #expect(try series("missing-aggregate").contains { $0["seriesKey"] as? String == "aggregate" } == false)
        #expect(try json("off-host")["finalOrigin"] as? String != "https://deng.codexradar.com")
        #expect(try json("challenge")["pageState"] as? String == "challenge")
        #expect(try fixture("oversized").count > 64 * 1024)

        let prompt = try #require(try series("prompt-like-text").first {
            ($0["displayName"] as? String)?.contains("Ignore previous instructions") == true
        })
        #expect(prompt["seriesKey"] as? String == "model:gpt-5.6-sol")
    }

    @Test("SwiftPM keeps rendered-IQ fixtures out of release resources")
    func swiftPMReleaseExclusion() throws {
        let package = try String(contentsOf: root.appending(path: "Package.swift"), encoding: .utf8)
        #expect(package.contains("\"Fixtures/CodexRenderedIQHistory\""))
        #expect(!package.contains(".process(\"Fixtures/CodexRenderedIQHistory\")"))
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: root.appending(path: "Tests/ClaudeRadarTests/Fixtures/CodexRenderedIQHistory/\(name).json"))
    }

    private func json(_ name: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: fixture(name)) as? [String: Any])
    }

    private func series(_ name: String) throws -> [[String: Any]] {
        try #require(try json(name)["series"] as? [[String: Any]])
    }

    private func checksumManifest() throws -> [String: String] {
        let content = try String(
            contentsOf: root.appending(path: "Tests/ClaudeRadarTests/Fixtures/CodexRenderedIQHistory/SHA256SUMS"),
            encoding: .utf8
        )
        return try Dictionary(uniqueKeysWithValues: content.split(whereSeparator: \.isNewline).map { line in
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { throw CocoaError(.fileReadCorruptFile) }
            return (String(parts[1]), String(parts[0]))
        })
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
