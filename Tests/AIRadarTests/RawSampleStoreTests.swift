import CryptoKit
import Foundation
import Testing
@testable import AIRadar

@Suite("RawSampleStoreTests", .serialized)
struct RawSampleStoreTests {
    @Test("retention keeps three successes and twenty failures within the inclusive thirty-day boundary")
    func retentionBoundaries() async throws {
        // Given
        let fixture = try rawFixture()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for offset in 0..<5 {
            try await fixture.store.save(Data("success-\(offset)".utf8), sourceID: .claudeCodeRadar, outcome: .success, at: now.addingTimeInterval(Double(-offset)))
        }
        for offset in 0..<22 {
            try await fixture.store.save(Data("failure-\(offset)".utf8), sourceID: .claudeCodeRadar, outcome: .validationFailed, at: now.addingTimeInterval(Double(-offset)))
        }
        try await fixture.store.save(Data("boundary".utf8), sourceID: .claudeCodeRadar, outcome: .validationFailed, at: now.addingTimeInterval(-30 * 86_400))
        try await fixture.store.save(Data("expired".utf8), sourceID: .claudeCodeRadar, outcome: .validationFailed, at: now.addingTimeInterval(-30 * 86_400 - 0.001))

        // When
        try await fixture.store.prune(sourceID: .claudeCodeRadar, now: now)
        let samples = try await fixture.store.samples(sourceID: .claudeCodeRadar)

        // Then
        #expect(samples.filter { $0.outcome == .success }.count == 3)
        #expect(samples.filter { $0.outcome != .success }.count == 20)
        #expect(samples.allSatisfy { $0.outcome == .success || $0.capturedAt >= now.addingTimeInterval(-30 * 86_400) })
    }

    @Test("failure exactly thirty days old is retained and a one-millisecond older failure expires")
    func thirtyDayBoundary() async throws {
        // Given
        let fixture = try rawFixture()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let boundary = now.addingTimeInterval(-30 * 86_400)
        try await fixture.store.save(Data("boundary".utf8), sourceID: .claudeCodeRadar, outcome: .validationFailed, at: boundary)
        try await fixture.store.save(Data("expired".utf8), sourceID: .claudeCodeRadar, outcome: .validationFailed, at: boundary.addingTimeInterval(-0.001))

        // When
        try await fixture.store.prune(sourceID: .claudeCodeRadar, now: now)
        let samples = try await fixture.store.samples(sourceID: .claudeCodeRadar)

        // Then
        #expect(samples.count == 1)
        #expect(samples.first?.capturedAt == boundary)
    }

    @Test("concurrent saves remain bounded and raw bodies never enter SwiftData")
    func concurrentCleanup() async throws {
        // Given
        let fixture = try rawFixture()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        // When
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<80 {
                group.addTask {
                    try await fixture.store.save(Data("body-\(index)".utf8), sourceID: .claudeCodeRadar, outcome: index.isMultiple(of: 5) ? .success : .httpFailed, at: now.addingTimeInterval(Double(index)))
                }
            }
            try await group.waitForAll()
        }
        let samples = try await fixture.store.samples(sourceID: .claudeCodeRadar)

        // Then
        #expect(samples.filter { $0.outcome == .success }.count == 3)
        #expect(samples.filter { $0.outcome != .success }.count == 20)
    }

    @Test("corrupt files are contained and unsafe source paths and symlink roots are rejected")
    func corruptionAndPathSafety() async throws {
        // Given
        let fixture = try rawFixture()
        try await fixture.store.save(Data("valid".utf8), sourceID: .claudeCodeRadar, outcome: .success, at: Date(timeIntervalSince1970: 10))
        let sourceRoot = fixture.root.appending(path: "RawSamples/claude-code-radar")
        try Data("corrupt".utf8).write(to: sourceRoot.appending(path: "10.000_success_deadbeefdead.json"))

        // When
        let samples = try await fixture.store.samples(sourceID: .claudeCodeRadar)

        // Then
        #expect(samples.count == 1)
        await #expect(throws: RawSampleStoreError.self) {
            try await fixture.store.save(Data(), sourceID: .init(rawValue: "../escape"), outcome: .success, at: .now)
        }
    }

    @Test("a symlinked raw root cannot redirect writes outside the injected data root")
    func symlinkSafety() async throws {
        // Given
        let fixture = try rawFixture()
        let outside = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.root.appending(path: "RawSamples"), withDestinationURL: outside)

        // When / Then
        await #expect(throws: RawSampleStoreError.self) {
            try await fixture.store.save(Data("blocked".utf8), sourceID: .claudeCodeRadar, outcome: .success, at: .now)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test("a symlinked injected data root rejects save read and cleanup without touching its target")
    func symlinkedDataRoot() async throws {
        // Given
        let parent = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let outside = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let linkedRoot = parent.appending(path: "linked-data-root")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: outside)
        let store = RawSampleStore(dataRoot: linkedRoot)

        // When / Then
        await #expect(throws: RawSampleStoreError.self) {
            try await store.save(Data("blocked".utf8), sourceID: .claudeCodeRadar, outcome: .success, at: .now)
        }
        await #expect(throws: RawSampleStoreError.self) {
            _ = try await store.samples(sourceID: .claudeCodeRadar)
        }
        await #expect(throws: RawSampleStoreError.self) {
            try await store.deleteAll()
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test("a symlinked sample entry is neither followed nor surfaced")
    func symlinkedSampleEntry() async throws {
        // Given
        let fixture = try rawFixture()
        let body = Data("outside-body".utf8)
        let outside = fixture.root.appending(path: "outside.json")
        try body.write(to: outside)
        try await fixture.store.save(Data("valid".utf8), sourceID: .claudeCodeRadar, outcome: .success, at: Date(timeIntervalSince1970: 10))
        let hash = SHA256.hash(data: body).prefix(6).map { String(format: "%02x", $0) }.joined()
        let link = fixture.root.appending(path: "RawSamples/claude-code-radar/11.000_success_\(hash).json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        // When
        let samples = try await fixture.store.samples(sourceID: .claudeCodeRadar)
        try await fixture.store.prune(sourceID: .claudeCodeRadar, now: Date(timeIntervalSince1970: 11))

        // Then
        #expect(samples.count == 1)
        #expect(!FileManager.default.fileExists(atPath: link.path))
        #expect(try Data(contentsOf: outside) == body)
    }

    @Test("automatic cleanup removes invalid physical entries and remains bounded")
    func invalidPhysicalGrowth() async throws {
        // Given
        let fixture = try rawFixture()
        try await fixture.store.save(Data("seed".utf8), sourceID: .claudeCodeRadar, outcome: .success, at: Date(timeIntervalSince1970: 10))
        let directory = fixture.root.appending(path: "RawSamples/claude-code-radar")
        for index in 0..<100 {
            let name = index.isMultiple(of: 2)
                ? "\(index).000_success_deadbeefdead.json"
                : "garbage-\(index).bin"
            try Data("invalid-\(index)".utf8).write(to: directory.appending(path: name))
        }

        // When
        try await fixture.store.save(Data("new-valid".utf8), sourceID: .claudeCodeRadar, outcome: .httpFailed, at: Date(timeIntervalSince1970: 20))
        let physicalEntries = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        // Then
        #expect(physicalEntries.count <= 23)
        #expect(physicalEntries.allSatisfy { $0.hasSuffix(".json") && !$0.contains("deadbeefdead") })
    }

    @Test("delete removes only the injected raw root and permits reinitialization")
    func deleteAndReinitialize() async throws {
        // Given
        let fixture = try rawFixture()
        let sentinel = fixture.root.appending(path: "sentinel")
        try Data("keep".utf8).write(to: sentinel)
        try await fixture.store.save(Data("raw".utf8), sourceID: .claudeCodeRadar, outcome: .success, at: .now)

        // When
        try await fixture.store.deleteAll()
        let restarted = RawSampleStore(dataRoot: fixture.root)

        // Then
        #expect(FileManager.default.fileExists(atPath: sentinel.path))
        #expect(try await restarted.samples(sourceID: .claudeCodeRadar).isEmpty)
    }

    @Test("export payload validates bytes and filename hash through one no-follow file descriptor")
    func exportPayloadRaceSafety() async throws {
        // Given
        let fixture = try rawFixture()
        let validBody = Data("valid-export-body".utf8)
        try await fixture.store.save(validBody, sourceID: .claudeCodeRadar, outcome: .success, at: Date(timeIntervalSince1970: 10))
        let directory = fixture.root.appending(path: "RawSamples/claude-code-radar")
        let validURL = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let replacedURL = directory.appending(path: validURL.lastPathComponent)
        try FileManager.default.removeItem(at: replacedURL)
        try Data("different-body".utf8).write(to: replacedURL)
        let outside = fixture.root.appending(path: "outside.json")
        try Data("outside".utf8).write(to: outside)
        let outsideHash = SHA256.hash(data: Data("outside".utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        let symlink = directory.appending(path: "11.000_success_\(outsideHash).json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
        let agreedBody = Data("agreed-body".utf8)
        try await fixture.store.save(agreedBody, sourceID: .claudeCodeRadar, outcome: .httpFailed, at: Date(timeIntervalSince1970: 12))

        // When
        let payloads = try await fixture.store.exportPayloads(sourceID: .claudeCodeRadar)

        // Then
        #expect(payloads.count == 1)
        let payload = try #require(payloads.first)
        #expect(payload.data == agreedBody)
        let expectedHash = SHA256.hash(data: payload.data).prefix(6).map { String(format: "%02x", $0) }.joined()
        #expect(payload.id.hasSuffix("_\(expectedHash).json"))
        #expect(try Data(contentsOf: outside) == Data("outside".utf8))
    }

    private func rawFixture() throws -> RawFixture {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return RawFixture(root: root, store: RawSampleStore(dataRoot: root))
    }
}

private struct RawFixture: Sendable {
    let root: URL
    let store: RawSampleStore
}
