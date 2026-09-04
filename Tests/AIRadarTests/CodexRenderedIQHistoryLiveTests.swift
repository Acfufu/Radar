import Foundation
import Testing
@testable import AIRadar

@Suite(
    "CodexRenderedIQHistoryLiveTests",
    .enabled(
        if: ProcessInfo.processInfo.environment["RADAR_LIVE_CODEX_IQ_HISTORY"] == "1"
    )
)
struct CodexRenderedIQHistoryLiveTests {
    @MainActor
    @Test("anonymous nonpersistent page yields bounded normalized 24h evidence")
    func anonymous24hRead() async throws {
        let evidencePath = try #require(
            ProcessInfo.processInfo.environment["RADAR_LIVE_EVIDENCE_PATH"]
        )
        let reader = CodexRenderedIQHistoryPageReader()
        defer { reader.cancel() }

        let snapshot: CodexRenderedIQHistorySnapshot
        do {
            snapshot = try await reader.read()
        } catch let error as CodexRenderedIQHistoryPageReaderError {
            try writeEvidence(
                LiveFailureEvidence(
                    schemaVersion: 1,
                    status: "blocked",
                    errorType: "CodexRenderedIQHistoryPageReaderError",
                    errorCode: String(describing: error),
                    attemptedAt: Date(),
                    nonpersistent: !CodexRenderedIQHistoryPageReader
                        .makeConfiguration()
                        .websiteDataStore
                        .isPersistent
                ),
                to: evidencePath
            )
            throw error
        }
        let aggregate = snapshot.series.filter { $0.seriesKey == "aggregate" }
        let models = snapshot.series.filter { $0.seriesKey.hasPrefix("model:") }
        let recomputed = try CodexRenderedIQHistorySemanticFingerprint.make(
            sourceID: snapshot.sourceID,
            series: snapshot.series,
            finalOrigin: snapshot.finalOrigin,
            parserRevision: snapshot.parserRevision
        )

        #expect(snapshot.sourceID == .codexRadar)
        #expect(snapshot.finalOrigin == "https://deng.codexradar.com")
        #expect(
            snapshot.parserRevision
                == CodexRenderedIQHistoryDOMParser.parserRevision
        )
        #expect(aggregate.count == 1)
        #expect((1...7).contains(models.count))
        #expect(aggregate.count + models.count == snapshot.series.count)
        #expect(snapshot.series.allSatisfy { $0.points.count == 24 })
        #expect(recomputed == snapshot.semanticFingerprint)

        let summary = LiveEvidence(
            schemaVersion: 1,
            status: "passed",
            sourceID: snapshot.sourceID.rawValue,
            finalOrigin: snapshot.finalOrigin,
            parserRevision: snapshot.parserRevision,
            capturedAt: snapshot.capturedAt,
            seriesCount: snapshot.series.count,
            aggregateCount: aggregate.count,
            modelCount: models.count,
            pointCounts: snapshot.series.map { $0.points.count },
            semanticFingerprint: snapshot.semanticFingerprint,
            fingerprintVerified: recomputed == snapshot.semanticFingerprint,
            nonpersistent: !CodexRenderedIQHistoryPageReader
                .makeConfiguration()
                .websiteDataStore
                .isPersistent
        )
        try writeEvidence(summary, to: evidencePath)
    }

    private func writeEvidence<Value: Encodable>(
        _ value: Value,
        to path: String
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        #expect(data.count <= 4_096)
        guard data.count <= 4_096 else { return }

        let url = URL(filePath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}

private struct LiveEvidence: Encodable {
    let schemaVersion: Int
    let status: String
    let sourceID: String
    let finalOrigin: String
    let parserRevision: String
    let capturedAt: Date
    let seriesCount: Int
    let aggregateCount: Int
    let modelCount: Int
    let pointCounts: [Int]
    let semanticFingerprint: String
    let fingerprintVerified: Bool
    let nonpersistent: Bool
}

private struct LiveFailureEvidence: Encodable {
    let schemaVersion: Int
    let status: String
    let errorType: String
    let errorCode: String
    let attemptedAt: Date
    let nonpersistent: Bool
}
