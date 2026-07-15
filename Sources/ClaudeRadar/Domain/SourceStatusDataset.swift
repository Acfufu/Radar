import Foundation

struct SourceStatusDataset: Hashable, Codable, Sendable {
    let sourceID: RadarSourceID
    let sourceUpdatedAt: Date?
    let fetchedAt: Date
    let quotaEstimates: [SourceQuotaEstimate]
}

struct SourceQuotaEstimate: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let windowLabel: String
    let usedPercent: Decimal?
    let estimatedValueUSD: Decimal?
    let resetDescription: String?
}
