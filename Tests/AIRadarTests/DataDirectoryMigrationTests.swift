import Foundation
import Testing

@testable import AIRadar

/// Data-directory copy-on-first-launch migration tests (spec D5).
/// All paths are injected temporary roots; real home-directory literal
/// paths are intentionally absent from this suite.
@Suite("DataDirectoryMigrationTests")
struct DataDirectoryMigrationTests {
    private let fileManager = FileManager.default

    private func makeRoot(_ name: String) -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "AIRadar-Migration-\(name)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeLegacy(withUnreadableEntry: Bool = false) throws -> URL {
        let legacy = makeRoot("legacy")
        try Data("store".utf8).write(to: legacy.appending(path: "Radar.store"))
        try fileManager.createDirectory(at: legacy.appending(path: "RawSamples"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacy.appending(path: "SyncMetadata.json"))
        if withUnreadableEntry {
            let blocked = legacy.appending(path: "unreadable.blob")
            try Data("x".utf8).write(to: blocked)
            try fileManager.setAttributes(
                [.posixPermissions: 0o000], ofItemAtPath: blocked.path
            )
        }
        return legacy
    }

    private func snapshot(_ root: URL) throws -> [String: Data] {
        var snapshot: [String: Data] = [:]
        for entry in try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            var isDirectory: ObjCBool = false
            _ = fileManager.fileExists(atPath: entry.path, isDirectory: &isDirectory)
            snapshot[entry.lastPathComponent] = isDirectory.boolValue
                ? Data("dir".utf8)
                : (try? Data(contentsOf: entry)) ?? Data("unreadable".utf8)
        }
        return snapshot
    }

    @Test("legacy directory present copies content and preserves the legacy directory")
    func copiesAndPreservesLegacy() throws {
        let parent = makeRoot("parent")
        let legacy = parent.appending(path: "ClaudeRadar", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("store".utf8).write(to: legacy.appending(path: "Radar.store"))
        let before = try snapshot(legacy)

        let current = parent.appending(path: "AIRadar", directoryHint: .isDirectory)
        let outcome = DataDirectoryMigration.runIfSupported(legacyRoot: legacy, currentRoot: current)

        #expect(outcome == .migrated)
        #expect(fileManager.fileExists(atPath: current.appending(path: "Radar.store").path))
        #expect(fileManager.fileExists(atPath: current.appending(path: DataDirectoryMigration.markerFileName).path))
        #expect(try snapshot(legacy) == before)
    }

    @Test("missing legacy directory falls back to a fresh current directory")
    func missingLegacyFallsBack() throws {
        let parent = makeRoot("parent")
        let current = parent.appending(path: "AIRadar", directoryHint: .isDirectory)

        let outcome = DataDirectoryMigration.runIfSupported(
            legacyRoot: parent.appending(path: "ClaudeRadar", directoryHint: .isDirectory),
            currentRoot: current
        )

        #expect(outcome == .legacyMissing)
        #expect(!fileManager.fileExists(atPath: current.path))
    }

    @Test("existing current directory is never recopied")
    func existingCurrentIsNotRecopied() throws {
        let parent = makeRoot("parent")
        let legacy = parent.appending(path: "ClaudeRadar", directoryHint: .isDirectory)
        let current = parent.appending(path: "AIRadar", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: legacy.appending(path: "Radar.store"))
        try fileManager.createDirectory(at: current, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: current.appending(path: "Radar.store"))

        let outcome = DataDirectoryMigration.runIfSupported(legacyRoot: legacy, currentRoot: current)

        #expect(outcome == .notNeeded)
        #expect(try Data(contentsOf: current.appending(path: "Radar.store")) == Data("new".utf8))
    }

    @Test("interrupted copy cleans the half-built directory so migration can retry")
    func interruptedCopyCleansStagingAndTarget() throws {
        let parent = makeRoot("parent")
        let legacy = try makeLegacy(withUnreadableEntry: true)
        let current = parent.appending(path: "AIRadar", directoryHint: .isDirectory)
        defer {
            for entry in (try? fileManager.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)) ?? [] {
                try? fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: entry.path)
            }
        }

        let outcome = DataDirectoryMigration.runIfSupported(legacyRoot: legacy, currentRoot: current)

        #expect(outcome == .copyFailed)
        #expect(!fileManager.fileExists(atPath: current.path))
        let siblings = try fileManager.contentsOfDirectory(atPath: parent.path)
        #expect(!siblings.contains { $0.hasPrefix(".AIRadar-migration-staging-") })
    }

    @Test("marker write failure is non-blocking and never triggers a second copy")
    func markerFailureDoesNotReCopy() throws {
        let parent = makeRoot("parent")
        let legacy = try makeLegacy()
        let current = parent.appending(path: "AIRadar", directoryHint: .isDirectory)

        let outcome = DataDirectoryMigration.runIfSupported(legacyRoot: legacy, currentRoot: current)
        #expect(outcome == .migrated)
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: current.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: current.path) }
        try? fileManager.removeItem(at: current.appending(path: DataDirectoryMigration.markerFileName))

        let rerun = DataDirectoryMigration.runIfSupported(legacyRoot: legacy, currentRoot: current)
        #expect(rerun == .notNeeded)
        #expect(fileManager.fileExists(atPath: current.appending(path: "Radar.store").path))
    }
}
