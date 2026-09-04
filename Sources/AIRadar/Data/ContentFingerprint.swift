import CryptoKit
import Foundation

enum ContentFingerprintError: Error {
    case invalidCanonicalObject
}

enum ContentFingerprint {
    static func benchmark(
        _ dataset: BenchmarkDataset,
        seriesRevision: String? = nil
    ) throws -> String {
        let normalized = BenchmarkDataset(
            sourceID: dataset.sourceID,
            sourceUpdatedAt: dataset.sourceUpdatedAt,
            fetchedAt: dataset.fetchedAt,
            benchmarkName: dataset.benchmarkName,
            benchmarkVersion: dataset.benchmarkVersion,
            seriesRevision: dataset.seriesRevision,
            models: dataset.models.sorted { modelKey($0.id) < modelKey($1.id) }
        )
        return try make(normalized, datasetType: .benchmark, seriesRevision: seriesRevision ?? dataset.seriesRevision)
    }

    static func community(
        _ dataset: CommunityDataset,
        seriesRevision: String = ClaudeRadarConfiguration.seriesRevision
    ) throws -> String {
        let normalized = CommunityDataset(
            sourceID: dataset.sourceID,
            sourceUpdatedAt: dataset.sourceUpdatedAt,
            fetchedAt: dataset.fetchedAt,
            ratings: dataset.ratings.sorted { modelKey($0.id) < modelKey($1.id) }
        )
        return try make(normalized, datasetType: .community, seriesRevision: seriesRevision)
    }

    static func sourceStatus(
        _ dataset: SourceStatusDataset,
        seriesRevision: String = ClaudeRadarConfiguration.seriesRevision
    ) throws -> String {
        let normalized = SourceStatusDataset(
            sourceID: dataset.sourceID,
            sourceUpdatedAt: dataset.sourceUpdatedAt,
            fetchedAt: dataset.fetchedAt,
            quotaEstimates: dataset.quotaEstimates.sorted { $0.id < $1.id }
        )
        return try make(normalized, datasetType: .sourceStatus, seriesRevision: seriesRevision)
    }

    static func renderedWarning(_ snapshot: CodexRenderedWarningSnapshot) throws -> String {
        try CodexRenderedWarningSemanticFingerprint.make(
            sourceTimeLabel: snapshot.sourceTimeLabel,
            cards: snapshot.cards,
            finalOrigin: snapshot.finalOrigin,
            parserRevision: snapshot.parserRevision
        )
    }

    static func renderedIQHistory(_ snapshot: CodexRenderedIQHistorySnapshot) throws -> String {
        try CodexRenderedIQHistorySemanticFingerprint.make(
            sourceID: snapshot.sourceID,
            series: snapshot.series,
            finalOrigin: snapshot.finalOrigin,
            parserRevision: snapshot.parserRevision
        )
    }

    private static func make<Value: Encodable>(
        _ value: Value,
        datasetType: RadarDatasetType,
        seriesRevision: String
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let encoded = try encoder.encode(value)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw ContentFingerprintError.invalidCanonicalObject
        }
        object.removeValue(forKey: "fetchedAt")
        object["datasetType"] = datasetType.rawValue
        object["seriesRevision"] = seriesRevision
        let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }

    private static func modelKey(_ id: ModelID) -> String {
        "\(id.sourceID.rawValue)|\(id.upstreamKey)"
    }
}
