import Foundation
import SwiftData

enum RadarDatasetType: String, Codable, CaseIterable, Sendable {
    case benchmark
    case community
    case sourceStatus = "source-status"
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
