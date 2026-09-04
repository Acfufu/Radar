import Foundation
import SwiftData
@testable import AIRadar

struct RepositoryFixture {
    let root: URL
    let container: ModelContainer
    let repository: RadarRepository
}

struct HistoryDump: Codable {
    let benchmarkSnapshots: Int
    let duplicateInsertions: Int
    let lastKnownGood: String?
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
