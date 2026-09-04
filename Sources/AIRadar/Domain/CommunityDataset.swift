import Foundation

struct CommunityDataset: Hashable, Sendable {
    let sourceID: RadarSourceID
    let sourceUpdatedAt: Date?
    let fetchedAt: Date
    let ratings: [CommunityRating]
    /// Upstream daily rating snapshots (spec §5.4); additive optional field,
    /// absent in legacy payloads.
    let history: [CommunityHistoryDay]?
    /// The upstream `day` label identifying the current 24h bucket.
    let day: String?
    /// D12: read-only in-memory display data ("我的评分"). Custom Codable
    /// below never encodes this field, so it is absent from persistence,
    /// export, and content fingerprints — display-only by construction.
    var myScores: [String: Decimal]?

    init(
        sourceID: RadarSourceID,
        sourceUpdatedAt: Date?,
        fetchedAt: Date,
        ratings: [CommunityRating],
        history: [CommunityHistoryDay]? = nil,
        day: String? = nil,
        myScores: [String: Decimal]? = nil
    ) {
        self.sourceID = sourceID
        self.sourceUpdatedAt = sourceUpdatedAt
        self.fetchedAt = fetchedAt
        self.ratings = ratings
        self.history = history
        self.day = day
        self.myScores = myScores
    }
}

extension CommunityDataset: Codable {
    enum CodingKeys: String, CodingKey {
        case sourceID
        case sourceUpdatedAt
        case fetchedAt
        case ratings
        case history
        case day
        // myScores deliberately absent: never serialized (D12).
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try container.decode(RadarSourceID.self, forKey: .sourceID)
        sourceUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .sourceUpdatedAt)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        ratings = try container.decode([CommunityRating].self, forKey: .ratings)
        history = try container.decodeIfPresent([CommunityHistoryDay].self, forKey: .history)
        day = try container.decodeIfPresent(String.self, forKey: .day)
        myScores = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceID, forKey: .sourceID)
        try container.encodeIfPresent(sourceUpdatedAt, forKey: .sourceUpdatedAt)
        try container.encode(fetchedAt, forKey: .fetchedAt)
        try container.encode(ratings, forKey: .ratings)
        try container.encodeIfPresent(history, forKey: .history)
        try container.encodeIfPresent(day, forKey: .day)
    }
}

struct CommunityRating: Identifiable, Hashable, Codable, Sendable {
    let id: ModelID
    let model: ModelDescriptor
    let average: Decimal?
    let voteCount: Int?
    let scaleMinimum: Decimal?
    let scaleMaximum: Decimal?
    /// Upstream rating group (spec §5.4 open set: known groups render with
    /// their label, unknown values are preserved verbatim — never a closed
    /// enum). Absent in legacy payloads.
    let group: String?

    init(
        id: ModelID,
        model: ModelDescriptor,
        average: Decimal?,
        voteCount: Int?,
        scaleMinimum: Decimal?,
        scaleMaximum: Decimal?,
        group: String? = nil
    ) {
        self.id = id
        self.model = model
        self.average = average
        self.voteCount = voteCount
        self.scaleMinimum = scaleMinimum
        self.scaleMaximum = scaleMaximum
        self.group = group
    }

    /// Effort suffix cut from the upstream id (verbatim when it matches the
    /// known suffix set; models without an effort tier get nil so ids like
    /// "gpt-5.5" are never mislabeled).
    var effortSuffix: String? {
        let known: Set<String> = ["ultra", "max", "xhigh", "high", "medium", "low", "off"]
        let parts = id.upstreamKey.split(separator: "-")
        guard let last = parts.last, known.contains(String(last)) else { return nil }
        return String(last)
    }
}

/// One upstream daily rating snapshot (spec §5.4 `history[]`).
struct CommunityHistoryDay: Hashable, Codable, Sendable {
    let day: String?
    let updatedAt: String?
    let ratings: [CommunityHistoryRating]
}

struct CommunityHistoryRating: Hashable, Codable, Sendable {
    let id: String?
    let group: String?
    let average: Decimal?
    let count: Int?
}
