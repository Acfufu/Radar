import Foundation

struct SyncErrorMetadata: Codable, Equatable, Sendable {
    let kind: SegmentError.Kind
    let message: String

    init(_ error: SegmentError) {
        kind = error.kind
        message = error.message
    }
}

struct SyncMetadata: Codable, Equatable, Sendable {
    var lastAttemptedAt: Date?
    var lastSuccessfulAt: Date?
    var lastError: SyncErrorMetadata?
    var etag: String?
    var lastModified: String?
    var retryAfter: Date?
    var backoffUntil: Date?
    var consecutiveFailures: Int?

    static let empty = Self()
}

actor SyncMetadataStore {
    private let fileURL: URL
    private var loaded = false
    private var records: [String: SyncMetadata] = [:]
    private var loadFailure: SyncErrorMetadata?

    init(root: URL) {
        fileURL = root.appending(path: "SyncMetadata.json")
    }

    func metadata(sourceID: RadarSourceID, datasetType: RadarDatasetType) throws -> SyncMetadata {
        try loadIfNeeded()
        return records[key(sourceID, datasetType)] ?? .empty
    }

    func corruptionError() throws -> SyncErrorMetadata? {
        try loadIfNeeded()
        return loadFailure
    }

    func update(
        sourceID: RadarSourceID,
        datasetType: RadarDatasetType,
        _ transform: (inout SyncMetadata) -> Void
    ) throws {
        try loadIfNeeded()
        let recordKey = key(sourceID, datasetType)
        var metadata = records[recordKey] ?? .empty
        transform(&metadata)
        records[recordKey] = metadata
        try persist()
    }

    func deleteAll() throws {
        records = [:]
        loaded = true
        loadFailure = nil
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        defer { loaded = true }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            records = try JSONDecoder().decode([String: SyncMetadata].self, from: Data(contentsOf: fileURL))
        } catch {
            records = [:]
            loadFailure = SyncErrorMetadata(SegmentError(
                kind: .decoding,
                message: "Stored synchronization metadata could not be decoded"
            ))
        }
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(records).write(to: fileURL, options: [.atomic])
        loadFailure = nil
    }

    private func key(_ sourceID: RadarSourceID, _ datasetType: RadarDatasetType) -> String {
        "\(sourceID.rawValue)|\(datasetType.rawValue)"
    }
}
