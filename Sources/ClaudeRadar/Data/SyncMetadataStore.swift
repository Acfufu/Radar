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
        try persist(records)
    }

    func delete(sourceID: RadarSourceID) throws {
        try loadIfNeeded()
        if let loadFailure {
            throw SegmentError(kind: loadFailure.kind, message: loadFailure.message)
        }

        let remaining = records.filter { recordKey, _ in
            guard let component = sourceComponent(in: recordKey) else { return true }
            return component != sourceID.rawValue
        }
        if remaining.isEmpty {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } else {
            try persist(remaining)
        }
        records = remaining
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

    private func persist(_ records: [String: SyncMetadata]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(records).write(to: fileURL, options: [.atomic])
        loadFailure = nil
    }

    private func key(_ sourceID: RadarSourceID, _ datasetType: RadarDatasetType) -> String {
        "\(sourceID.rawValue)|\(datasetType.rawValue)"
    }

    private func sourceComponent(in recordKey: String) -> Substring? {
        guard let separator = recordKey.firstIndex(of: "|") else { return nil }
        return recordKey[..<separator]
    }
}
