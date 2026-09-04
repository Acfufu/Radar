import Foundation

struct CommunityDataset: Hashable, Codable, Sendable {
    let sourceID: RadarSourceID
    let sourceUpdatedAt: Date?
    let fetchedAt: Date
    let ratings: [CommunityRating]
}

struct CommunityRating: Identifiable, Hashable, Codable, Sendable {
    let id: ModelID
    let model: ModelDescriptor
    let average: Decimal?
    let voteCount: Int?
    let scaleMinimum: Decimal?
    let scaleMaximum: Decimal?
}
