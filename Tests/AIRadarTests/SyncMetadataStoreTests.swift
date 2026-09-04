import CryptoKit
import Foundation
import Testing
@testable import AIRadar

@Suite("SyncMetadataStoreTests", .serialized)
struct SyncMetadataStoreTests {
    @Test("source deletion preserves exact sibling metadata and persists it")
    func sourceDeletionPreservesExactSibling() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = RadarSourceID(rawValue: "codex-radar")
        let sibling = RadarSourceID(rawValue: "codex-radar-preview")
        let store = SyncMetadataStore(root: root)

        try await store.update(sourceID: target, datasetType: .benchmark) { $0.etag = "target" }
        try await store.update(sourceID: sibling, datasetType: .benchmark) { $0.etag = "sibling" }

        try await store.delete(sourceID: target)
        let restarted = SyncMetadataStore(root: root)

        #expect(try await restarted.metadata(sourceID: target, datasetType: .benchmark) == .empty)
        #expect(try await restarted.metadata(sourceID: sibling, datasetType: .benchmark).etag == "sibling")
    }

    @Test("deleting the final source removes the metadata file")
    func finalSourceDeletionRemovesFile() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SyncMetadataStore(root: root)
        let file = root.appending(path: "SyncMetadata.json")
        try await store.update(sourceID: .codexRadar, datasetType: .renderedWarnings) { $0.etag = "only" }
        #expect(FileManager.default.fileExists(atPath: file.path))

        try await store.delete(sourceID: .codexRadar)

        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("corrupt metadata fails closed without changing bytes or hash")
    func corruptMetadataFailsClosed() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "SyncMetadata.json")
        let corrupt = Data("{corrupt-metadata".utf8)
        try corrupt.write(to: file, options: .atomic)
        let beforeHash = sha256(corrupt)
        let store = SyncMetadataStore(root: root)

        await #expect(throws: SegmentError.self) {
            try await store.delete(sourceID: .codexRadar)
        }

        let after = try Data(contentsOf: file)
        #expect(after == corrupt)
        #expect(sha256(after) == beforeHash)
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SyncMetadataStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
