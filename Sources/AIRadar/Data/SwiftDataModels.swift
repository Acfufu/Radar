import Foundation
import SwiftData

enum RadarDatasetType: String, Codable, CaseIterable, Sendable {
    case benchmark
    case community
    case sourceStatus = "source-status"
    case renderedWarnings = "rendered-warnings"
    case renderedIQHistory = "rendered-iq-history"
    case intelligenceEfficiency = "intelligence-efficiency"
    case fastRadarHistory = "fast-radar-history"
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
            IntelligenceEfficiencySnapshotEntity.self,
            FastRadarRunEntity.self,
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

/// Upstream intelligence-efficiency snapshot (spec §5.2) from the public
/// `/data/intelligence-efficiency.json` sidecar endpoint; additive SwiftData
/// schema change. Each payload carries the full upstream history, so only
/// the latest snapshot per source is retained (bounded local store).
@Model
final class IntelligenceEfficiencySnapshotEntity {
    @Attribute(.unique) var dedupeKey: String
    var id: UUID
    var sourceID: String
    var contentFingerprint: String
    var fetchedAt: Date
    var sourceUpdatedAtText: String?
    var encodedDataset: Data

    init(dataset: IntelligenceEfficiencyDataset, fingerprint: String, encodedDataset: Data) {
        dedupeKey = "\(dataset.sourceID.rawValue)|\(RadarDatasetType.intelligenceEfficiency.rawValue)|\(fingerprint)"
        id = UUID()
        sourceID = dataset.sourceID.rawValue
        contentFingerprint = fingerprint
        self.fetchedAt = dataset.fetchedAt
        sourceUpdatedAtText = dataset.sourceUpdatedAt
        self.encodedDataset = encodedDataset
    }
}

/// One upstream fast-radar run (spec §5.3). Rows are replaced as a whole set
/// per sync: when a payload with a new dataset fingerprint arrives, all
/// previous rows for the source are dropped — runs never accumulate across
/// syncs and the store stays bounded. Denormalized header columns
/// (schemaVersion/type/timezone/updatedAt) reconstruct the dataset state.
@Model
final class FastRadarRunEntity {
    @Attribute(.unique) var dedupeKey: String
    var id: UUID
    var sourceID: String
    var datasetFingerprint: String
    var fetchedAt: Date
    var schemaVersion: Int?
    var payloadType: String?
    var timezone: String?
    var updatedAtText: String?
    var runID: String
    var measuredAtText: String?
    var measuredAtDate: Date?
    var completedAtText: String?
    var cliVersion: String?
    var encodedRun: Data

    init(
        dataset: FastRadarHistoryDataset,
        fingerprint: String,
        run: FastRadarHistoryDataset.FastRadarRun,
        encodedRun: Data
    ) {
        dedupeKey = "\(dataset.sourceID.rawValue)|\(RadarDatasetType.fastRadarHistory.rawValue)|\(fingerprint)|\(run.runID ?? "")"
        id = UUID()
        sourceID = dataset.sourceID.rawValue
        datasetFingerprint = fingerprint
        self.fetchedAt = dataset.fetchedAt
        schemaVersion = dataset.schemaVersion
        payloadType = dataset.type
        timezone = dataset.timezone
        updatedAtText = dataset.updatedAt
        runID = run.runID ?? ""
        measuredAtText = run.measuredAt
        measuredAtDate = FastRadarHistoryDataset.parseISO8601(run.measuredAt)
        completedAtText = run.completedAt
        cliVersion = run.cliVersion
        self.encodedRun = encodedRun
    }
}
