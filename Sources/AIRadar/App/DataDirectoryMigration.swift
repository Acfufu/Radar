import Foundation

/// One-shot, copy-based migration of the pre-rename data directory.
///
/// Spec D5: copy, never move; the legacy directory stays untouched so the
/// migration is rollback-safe. The marker file is advisory only — the retry
/// guard is "legacy exists AND current does not", so a failed marker write
/// never triggers a second copy once the copied directory is in place.
enum DataDirectoryMigration {
    enum Outcome: Equatable, Sendable {
        case migrated
        case markerFailed
        case notNeeded
        case legacyMissing
        case copyFailed
    }

    static let markerFileName = ".migrated"

    static func runIfSupported(
        legacyRoot: URL,
        currentRoot: URL,
        fileManager: FileManager = .default
    ) -> Outcome {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: legacyRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return .legacyMissing }
        guard !fileManager.fileExists(atPath: currentRoot.path) else { return .notNeeded }

        let stagingRoot = currentRoot.deletingLastPathComponent().appending(
            path: ".AIRadar-migration-staging-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        do {
            try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            let entries = try fileManager.contentsOfDirectory(
                at: legacyRoot, includingPropertiesForKeys: nil
            )
            for entry in entries {
                try fileManager.copyItem(
                    at: entry,
                    to: stagingRoot.appending(path: entry.lastPathComponent)
                )
            }
            try fileManager.moveItem(at: stagingRoot, to: currentRoot)
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            return .copyFailed
        }

        let marker = currentRoot.appending(path: markerFileName)
        guard fileManager.createFile(atPath: marker.path, contents: Data()) else {
            return .markerFailed
        }
        return .migrated
    }
}
