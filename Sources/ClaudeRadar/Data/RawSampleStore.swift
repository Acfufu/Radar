import CryptoKit
import Darwin
import Foundation

enum RawSampleOutcome: String, Codable, Sendable {
    case success
    case validationFailed = "validation-failed"
    case httpFailed = "http-failed"
    case decodingFailed = "decoding-failed"
}

struct RawSample: Equatable, Sendable {
    let fileURL: URL
    let capturedAt: Date
    let outcome: RawSampleOutcome
}

struct RawSamplePayload: Equatable, Sendable {
    let id: String
    let capturedAt: Date
    let outcome: RawSampleOutcome
    let data: Data
}

protocol RawSamplePayloadSource: Sendable {
    func exportPayloads(sourceID: RadarSourceID) async throws -> [RawSamplePayload]
}

enum RawSampleStoreError: Error {
    case unsafeSourceID
    case unsafePath
}

actor RawSampleStore {
    private let dataRoot: URL
    private let rawRoot: URL
    private let fileManager: FileManager

    init(dataRoot: URL, fileManager: FileManager = .default) {
        let trustedParent = dataRoot.deletingLastPathComponent().resolvingSymlinksInPath()
        self.dataRoot = trustedParent.appending(path: dataRoot.lastPathComponent, directoryHint: .isDirectory)
        rawRoot = self.dataRoot.appending(path: "RawSamples", directoryHint: .isDirectory)
        self.fileManager = fileManager
    }

    func save(_ data: Data, sourceID: RadarSourceID, outcome: RawSampleOutcome, at date: Date) throws {
        let directory = try sourceDirectory(sourceID)
        try ensureDirectory(directory)
        let hash = SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
        let timestamp = String(format: "%.3f", date.timeIntervalSince1970)
        let destination = directory.appending(path: "\(timestamp)_\(outcome.rawValue)_\(hash).json")
        if try node(at: destination) == .symbolicLink { throw RawSampleStoreError.unsafePath }
        try data.write(to: destination, options: [.atomic])
        try prune(sourceID: sourceID, now: date)
    }

    func flush() {}

    func samples(sourceID: RadarSourceID) throws -> [RawSample] {
        try physicalEntries(sourceID: sourceID)
            .compactMap(\.sample)
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    func exportPayloads(sourceID: RadarSourceID) throws -> [RawSamplePayload] {
        try physicalEntries(sourceID: sourceID)
            .compactMap(\.payload)
            .sorted { left, right in
                if left.capturedAt != right.capturedAt { return left.capturedAt < right.capturedAt }
                return left.id < right.id
            }
    }

    func prune(sourceID: RadarSourceID, now: Date) throws {
        let entries = try physicalEntries(sourceID: sourceID)
        let all = entries.compactMap(\.sample).sorted { $0.capturedAt > $1.capturedAt }
        let successes = all.filter { $0.outcome == .success }
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        let failures = all.filter { $0.outcome != .success && $0.capturedAt >= cutoff }
        let retained = Set((successes.prefix(3) + failures.prefix(20)).map(\.fileURL))
        for entry in entries where !retained.contains(entry.url) {
            try fileManager.removeItem(at: entry.url)
        }
    }

    func deleteAll() throws {
        guard try validateDirectory(dataRoot, missingIsAllowed: true) else { return }
        guard try validateDirectory(rawRoot, missingIsAllowed: true) else { return }
        try fileManager.removeItem(at: rawRoot)
    }

    private func sourceDirectory(_ sourceID: RadarSourceID) throws -> URL {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        guard !sourceID.rawValue.isEmpty,
              sourceID.rawValue.unicodeScalars.allSatisfy(allowed.contains),
              sourceID.rawValue != ".",
              sourceID.rawValue != ".." else {
            throw RawSampleStoreError.unsafeSourceID
        }
        let directory = rawRoot.appending(path: sourceID.rawValue, directoryHint: .isDirectory).standardizedFileURL
        let rootPath = rawRoot.standardizedFileURL.path + "/"
        guard directory.path.hasPrefix(rootPath) else { throw RawSampleStoreError.unsafePath }
        return directory
    }

    private func ensureDirectory(_ directory: URL) throws {
        try createDirectoryIfNeeded(dataRoot)
        try createDirectoryIfNeeded(rawRoot)
        try createDirectoryIfNeeded(directory)
    }

    private func createDirectoryIfNeeded(_ url: URL) throws {
        switch try node(at: url) {
        case .missing:
            try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
            guard try node(at: url) == .directory else { throw RawSampleStoreError.unsafePath }
        case .directory:
            break
        case .regularFile, .symbolicLink, .other:
            throw RawSampleStoreError.unsafePath
        }
    }

    private func physicalEntries(sourceID: RadarSourceID) throws -> [PhysicalEntry] {
        guard try validateDirectory(dataRoot, missingIsAllowed: true) else { return [] }
        guard try validateDirectory(rawRoot, missingIsAllowed: true) else { return [] }
        let directory = try sourceDirectory(sourceID)
        guard try validateDirectory(directory, missingIsAllowed: true) else { return [] }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map { url in
                let payload = try node(at: url) == .regularFile ? parsePayload(url) : nil
                return PhysicalEntry(url: url, payload: payload)
            }
    }

    private func validateDirectory(_ url: URL, missingIsAllowed: Bool) throws -> Bool {
        switch try node(at: url) {
        case .directory:
            return true
        case .missing where missingIsAllowed:
            return false
        case .missing, .regularFile, .symbolicLink, .other:
            throw RawSampleStoreError.unsafePath
        }
    }

    private func parsePayload(_ url: URL) -> RawSamplePayload? {
        guard url.pathExtension == "json" else { return nil }
        let stem = url.deletingPathExtension().lastPathComponent
        let parts = stem.split(separator: "_", maxSplits: 2).map(String.init)
        guard parts.count == 3,
              let timestamp = Double(parts[0]),
              let outcome = RawSampleOutcome(rawValue: parts[1]),
              let data = readRegularFileWithoutFollowingLinks(url) else { return nil }
        let actualHash = SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
        guard parts[2] == actualHash else { return nil }
        return RawSamplePayload(
            id: url.lastPathComponent,
            capturedAt: Date(timeIntervalSince1970: timestamp),
            outcome: outcome,
            data: data
        )
    }

    private func readRegularFileWithoutFollowingLinks(_ url: URL) -> Data? {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG else {
            try? handle.close()
            return nil
        }
        return try? handle.readToEnd()
    }

    private func node(at url: URL) throws -> FileNode {
        var information = stat()
        guard Darwin.lstat(url.path, &information) == 0 else {
            if errno == ENOENT { return .missing }
            throw RawSampleStoreError.unsafePath
        }
        return switch information.st_mode & S_IFMT {
        case S_IFDIR: .directory
        case S_IFREG: .regularFile
        case S_IFLNK: .symbolicLink
        default: .other
        }
    }
}

extension RawSampleStore: RawSamplePayloadSource {}

private struct PhysicalEntry {
    let url: URL
    let payload: RawSamplePayload?
    var sample: RawSample? {
        payload.map { RawSample(fileURL: url, capturedAt: $0.capturedAt, outcome: $0.outcome) }
    }
}

private enum FileNode {
    case missing
    case directory
    case regularFile
    case symbolicLink
    case other
}
