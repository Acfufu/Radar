import Foundation
import SwiftData

enum RadarDatasetType: String, Codable, CaseIterable, Sendable {
    case benchmark
    case community
    case sourceStatus = "source-status"
    case renderedWarnings = "rendered-warnings"
    case renderedIQHistory = "rendered-iq-history"
}

enum RadarModelSchema {
    static var current: Schema {
        Schema([
            BenchmarkSnapshotEntity.self,
            CommunitySnapshotEntity.self,
            SourceStatusSnapshotEntity.self,
            CodexRenderedWarningSnapshotEntity.self,
            CodexRenderedIQHistorySnapshotEntity.self,
            CodexRadarStatusSnapshotEntity.self,
        ])
    }

    static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: current, configurations: configuration)
    }
}

@Model
final class BenchmarkSnapshotEntity {
    @Attribute(.unique) var dedupeKey: String
    var id: UUID
    var sourceID: String
    var contentFingerprint: String
    var sourceUpdatedAt: Date?
    var fetchedAt: Date
    var chronologyAt: Date = Date.distantPast
    var seriesRevision: String
    var encodedDataset: Data

    init(dataset: BenchmarkDataset, fingerprint: String, encodedDataset: Data) {
        dedupeKey = Self.key(sourceID: dataset.sourceID, fingerprint: fingerprint)
        id = UUID()
        sourceID = dataset.sourceID.rawValue
        contentFingerprint = fingerprint
        sourceUpdatedAt = dataset.sourceUpdatedAt
        fetchedAt = dataset.fetchedAt
        chronologyAt = dataset.sourceUpdatedAt ?? dataset.fetchedAt
        seriesRevision = dataset.seriesRevision
        self.encodedDataset = encodedDataset
    }

    init(sourceID: RadarSourceID, fingerprint: String, fetchedAt: Date, seriesRevision: String, encodedDataset: Data) {
        dedupeKey = Self.key(sourceID: sourceID, fingerprint: fingerprint)
        id = UUID()
        self.sourceID = sourceID.rawValue
        contentFingerprint = fingerprint
        sourceUpdatedAt = nil
        self.fetchedAt = fetchedAt
        chronologyAt = fetchedAt
        self.seriesRevision = seriesRevision
        self.encodedDataset = encodedDataset
    }

    private static func key(sourceID: RadarSourceID, fingerprint: String) -> String {
        "\(sourceID.rawValue)|\(RadarDatasetType.benchmark.rawValue)|\(fingerprint)"
    }
}

@Model
final class CommunitySnapshotEntity {
    @Attribute(.unique) var dedupeKey: String
    var id: UUID
    var sourceID: String
    var contentFingerprint: String
    var sourceUpdatedAt: Date?
    var fetchedAt: Date
    var chronologyAt: Date = Date.distantPast
    var seriesRevision: String
    var encodedDataset: Data

    init(dataset: CommunityDataset, seriesRevision: String, fingerprint: String, encodedDataset: Data) {
        dedupeKey = "\(dataset.sourceID.rawValue)|\(RadarDatasetType.community.rawValue)|\(fingerprint)"
        id = UUID()
        sourceID = dataset.sourceID.rawValue
        contentFingerprint = fingerprint
        sourceUpdatedAt = dataset.sourceUpdatedAt
        fetchedAt = dataset.fetchedAt
        chronologyAt = dataset.sourceUpdatedAt ?? dataset.fetchedAt
        self.seriesRevision = seriesRevision
        self.encodedDataset = encodedDataset
    }
}

@Model
final class SourceStatusSnapshotEntity {
    @Attribute(.unique) var dedupeKey: String
    var id: UUID
    var sourceID: String
    var contentFingerprint: String
    var sourceUpdatedAt: Date?
    var fetchedAt: Date
    var chronologyAt: Date = Date.distantPast
    var seriesRevision: String
    var encodedDataset: Data

    init(dataset: SourceStatusDataset, seriesRevision: String, fingerprint: String, encodedDataset: Data) {
        dedupeKey = "\(dataset.sourceID.rawValue)|\(RadarDatasetType.sourceStatus.rawValue)|\(fingerprint)"
        id = UUID()
        sourceID = dataset.sourceID.rawValue
        contentFingerprint = fingerprint
        sourceUpdatedAt = dataset.sourceUpdatedAt
        fetchedAt = dataset.fetchedAt
        chronologyAt = dataset.sourceUpdatedAt ?? dataset.fetchedAt
        self.seriesRevision = seriesRevision
        self.encodedDataset = encodedDataset
    }
}

@Model
final class CodexRenderedWarningSnapshotEntity {
    @Attribute(.unique) var dedupeKey: String
    var id: UUID
    var sourceID: String
    var contentFingerprint: String
    var sourceTimeLabel: String
    var finalOrigin: String
    var capturedAt: Date
    var chronologyAt: Date
    var parserRevision: String
    var encodedSnapshot: Data

    init(
        snapshot: CodexRenderedWarningSnapshot,
        fingerprint: String,
        encodedSnapshot: Data
    ) {
        dedupeKey = "\(snapshot.sourceID.rawValue)|\(RadarDatasetType.renderedWarnings.rawValue)|\(fingerprint)"
        id = UUID()
        sourceID = snapshot.sourceID.rawValue
        contentFingerprint = fingerprint
        sourceTimeLabel = snapshot.sourceTimeLabel
        finalOrigin = snapshot.finalOrigin
        capturedAt = snapshot.capturedAt
        chronologyAt = snapshot.capturedAt
        parserRevision = snapshot.parserRevision
        self.encodedSnapshot = encodedSnapshot
    }

    convenience init(snapshot: CodexRenderedWarningSnapshot) throws {
        let encodedSnapshot = try JSONEncoder.radar.encode(snapshot)
        let persistedSnapshot = try JSONDecoder.radar.decode(
            CodexRenderedWarningSnapshot.self,
            from: encodedSnapshot
        )
        let fingerprint = try ContentFingerprint.renderedWarning(persistedSnapshot)
        self.init(
            snapshot: persistedSnapshot,
            fingerprint: fingerprint,
            encodedSnapshot: encodedSnapshot
        )
    }
}

@Model
final class CodexRenderedIQHistorySnapshotEntity {
    @Attribute(.unique) var dedupeKey: String
    var id: UUID
    var sourceID: String
    var contentFingerprint: String
    var finalOrigin: String
    var capturedAt: Date
    var chronologyAt: Date
    var parserRevision: String
    var encodedSnapshot: Data

    init(
        snapshot: CodexRenderedIQHistorySnapshot,
        fingerprint: String,
        encodedSnapshot: Data
    ) {
        dedupeKey = "\(snapshot.sourceID.rawValue)|\(RadarDatasetType.renderedIQHistory.rawValue)|\(fingerprint)"
        id = UUID()
        sourceID = snapshot.sourceID.rawValue
        contentFingerprint = fingerprint
        finalOrigin = snapshot.finalOrigin
        capturedAt = snapshot.capturedAt
        chronologyAt = snapshot.capturedAt
        parserRevision = snapshot.parserRevision
        self.encodedSnapshot = encodedSnapshot
    }

    convenience init(snapshot: CodexRenderedIQHistorySnapshot) throws {
        let encodedSnapshot = try JSONEncoder.radar.encode(snapshot)
        let persistedSnapshot = try JSONDecoder.radar.decode(
            CodexRenderedIQHistorySnapshot.self,
            from: encodedSnapshot
        )
        self.init(
            snapshot: persistedSnapshot,
            fingerprint: try ContentFingerprint.renderedIQHistory(persistedSnapshot),
            encodedSnapshot: encodedSnapshot
        )
    }
}

/// Codex station status snapshot (spec §5.1): window/prediction/Tibo state
/// from current.json schema 2.0. Persisted on the source-status main chain
/// (no new RadarDatasetType case); additive store schema change.
@Model
final class CodexRadarStatusSnapshotEntity {
    @Attribute(.unique) var dedupeKey: String
    var id: UUID
    var sourceID: String
    var contentFingerprint: String
    var fetchedAt: Date
    var encodedDataset: Data

    init(dataset: CodexStationStatusDataset, fingerprint: String, encodedDataset: Data) {
        dedupeKey = "\(dataset.sourceID.rawValue)|codex-station-status|\(fingerprint)"
        id = UUID()
        sourceID = dataset.sourceID.rawValue
        contentFingerprint = fingerprint
        self.fetchedAt = dataset.fetchedAt
        self.encodedDataset = encodedDataset
    }
}
