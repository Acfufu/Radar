import Foundation

enum ParetoPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case qualityCost
    case qualityTime
    case qualityTokens

    var id: Self { self }
    var name: String {
        switch self {
        case .qualityCost: "质量 ↑ / 成本 ↓"
        case .qualityTime: "质量 ↑ / 耗时 ↓"
        case .qualityTokens: "质量 ↑ / Token ↓"
        }
    }
    var explanation: String {
        "同一当前数据集与同一 seriesRevision；两维均不为空。至少两维不差且一维严格更好时构成支配。"
    }
    var horizontalLabel: String {
        switch self {
        case .qualityCost: "成本（USD，越低越好）"
        case .qualityTime: "耗时（秒，越低越好）"
        case .qualityTokens: "Token（越低越好）"
        }
    }
}

enum ParetoClassification: String, Codable, Sendable {
    case frontier
    case dominated
    case dataInsufficient

    var label: String {
        switch self {
        case .frontier: "前沿"
        case .dominated: "被支配"
        case .dataInsufficient: "数据不足"
        }
    }
}

struct ParetoResult: Identifiable, Equatable, Codable, Sendable {
    let modelID: ModelID
    let displayName: String
    let sourceID: RadarSourceID
    let seriesRevision: String
    let quality: Decimal?
    let consumption: Decimal?
    let classification: ParetoClassification
    var id: ModelID { modelID }
}

enum ParetoAnalysis {
    static func analyze(dataset: BenchmarkDataset, preset: ParetoPreset) -> [ParetoResult] {
        let eligible = dataset.models.filter {
            $0.id.sourceID == dataset.sourceID && $0.qualityScore != nil && consumption($0, preset: preset) != nil
        }
        return dataset.models.map { model in
            let value = consumption(model, preset: preset)
            let isEligible = model.id.sourceID == dataset.sourceID && model.qualityScore != nil && value != nil
            let isDominated = isEligible && eligible.contains { candidate in
                candidate.id != model.id && dominates(candidate, model, preset: preset)
            }
            let classification: ParetoClassification = if !isEligible {
                .dataInsufficient
            } else if isDominated {
                .dominated
            } else {
                .frontier
            }
            return .init(
                modelID: model.id,
                displayName: model.descriptor.displayName,
                sourceID: dataset.sourceID,
                seriesRevision: dataset.seriesRevision,
                quality: model.qualityScore,
                consumption: value,
                classification: classification
            )
        }.sorted {
            let order = $0.displayName.localizedStandardCompare($1.displayName)
            return order == .orderedSame ? $0.modelID.upstreamKey < $1.modelID.upstreamKey : order == .orderedAscending
        }
    }

    private static func dominates(_ candidate: ModelBenchmark, _ target: ModelBenchmark, preset: ParetoPreset) -> Bool {
        guard let candidateQuality = candidate.qualityScore,
              let targetQuality = target.qualityScore,
              let candidateConsumption = consumption(candidate, preset: preset),
              let targetConsumption = consumption(target, preset: preset) else { return false }
        return candidateQuality >= targetQuality
            && candidateConsumption <= targetConsumption
            && (candidateQuality > targetQuality || candidateConsumption < targetConsumption)
    }

    private static func consumption(_ model: ModelBenchmark, preset: ParetoPreset) -> Decimal? {
        switch preset {
        case .qualityCost: model.benchmarkCostUSD
        case .qualityTime:
            model.elapsedSeconds.flatMap { Decimal(string: String($0), locale: Locale(identifier: "en_US_POSIX")) }
        case .qualityTokens: model.totalTokens.map(Decimal.init)
        }
    }
}
