import Foundation

enum DerivedMetricFormula: String, CaseIterable, Codable, Sendable {
    case costPerPassedTask
    case tokensPerPassedTask
    case secondsPerPassedTask
    case qualityPerDollar

    var name: String {
        switch self {
        case .costPerPassedTask: "每通过任务成本"
        case .tokensPerPassedTask: "每通过任务 Token"
        case .secondsPerPassedTask: "每通过任务秒数"
        case .qualityPerDollar: "每美元质量"
        }
    }

    var formulaText: String {
        switch self {
        case .costPerPassedTask: "benchmarkCostUSD / passedTasks"
        case .tokensPerPassedTask: "totalTokens / passedTasks"
        case .secondsPerPassedTask: "elapsedSeconds / passedTasks"
        case .qualityPerDollar: "qualityScore / benchmarkCostUSD"
        }
    }

    var requiredFields: [String] {
        switch self {
        case .costPerPassedTask: ["benchmarkCostUSD", "passedTasks"]
        case .tokensPerPassedTask: ["totalTokens", "passedTasks"]
        case .secondsPerPassedTask: ["elapsedSeconds", "passedTasks"]
        case .qualityPerDollar: ["qualityScore", "benchmarkCostUSD"]
        }
    }

    var unit: String {
        switch self {
        case .costPerPassedTask: "USD / passed task"
        case .tokensPerPassedTask: "tokens / passed task"
        case .secondsPerPassedTask: "seconds / passed task"
        case .qualityPerDollar: "quality / USD"
        }
    }
}

enum DerivedMetricUnavailableReason: Equatable, Codable, Sendable {
    case missingRequiredFields(fields: [String])
    case zeroDenominator(field: String)

    var explanation: String {
        switch self {
        case .missingRequiredFields(let fields): "缺少必需字段：\(fields.joined(separator: ", "))"
        case .zeroDenominator(let field): "无法计算：分母 \(field) 为 0"
        }
    }
}

enum DerivedMetricValue: Equatable, Codable, Sendable {
    case decimal(Decimal)
    case unavailable(DerivedMetricUnavailableReason)
}

struct DerivedMetricResult: Equatable, Codable, Sendable, Identifiable {
    let formula: DerivedMetricFormula
    let value: DerivedMetricValue
    var id: DerivedMetricFormula { formula }
}

enum DerivedMetrics {
    static func evaluate(model: ModelBenchmark) -> [DerivedMetricResult] {
        DerivedMetricFormula.allCases.map { formula in
            .init(formula: formula, value: evaluate(formula, model: model))
        }
    }

    private static func evaluate(_ formula: DerivedMetricFormula, model: ModelBenchmark) -> DerivedMetricValue {
        switch formula {
        case .costPerPassedTask:
            guard let cost = model.benchmarkCostUSD, let passed = model.passedTasks else {
                return missing(formula, model: model)
            }
            guard passed > 0 else { return .unavailable(.zeroDenominator(field: "passedTasks")) }
            return .decimal(cost / Decimal(passed))
        case .tokensPerPassedTask:
            guard let tokens = model.totalTokens, let passed = model.passedTasks else {
                return missing(formula, model: model)
            }
            guard passed > 0 else { return .unavailable(.zeroDenominator(field: "passedTasks")) }
            return .decimal(Decimal(tokens) / Decimal(passed))
        case .secondsPerPassedTask:
            guard let seconds = model.elapsedSeconds,
                  let decimalSeconds = Decimal(string: String(seconds), locale: Locale(identifier: "en_US_POSIX")),
                  let passed = model.passedTasks else {
                return missing(formula, model: model)
            }
            guard passed > 0 else { return .unavailable(.zeroDenominator(field: "passedTasks")) }
            return .decimal(decimalSeconds / Decimal(passed))
        case .qualityPerDollar:
            guard let quality = model.qualityScore, let cost = model.benchmarkCostUSD else {
                return missing(formula, model: model)
            }
            guard cost > 0 else { return .unavailable(.zeroDenominator(field: "benchmarkCostUSD")) }
            return .decimal(quality / cost)
        }
    }

    private static func missing(_ formula: DerivedMetricFormula, model: ModelBenchmark) -> DerivedMetricValue {
        let missingFields = formula.requiredFields.filter { field in
            switch field {
            case "benchmarkCostUSD": model.benchmarkCostUSD == nil
            case "passedTasks": model.passedTasks == nil
            case "totalTokens": model.totalTokens == nil
            case "elapsedSeconds": model.elapsedSeconds == nil
            case "qualityScore": model.qualityScore == nil
            default: false
            }
        }
        return .unavailable(.missingRequiredFields(fields: missingFields))
    }
}

struct IntelligenceEfficiencyPoint: Identifiable, Equatable, Sendable {
    let id: ModelID
    let modelName: String
    let quality: Double
    let averageCostUSD: Double
    let averageMinutes: Double
    let rawCombinedCost: Double
    let combinedCostIndex: Double
}

enum IntelligenceEfficiency {
    private static let combinedCostWeight = log(2.5) / log(1.35)

    static func points(models: [ModelBenchmark]) -> [IntelligenceEfficiencyPoint] {
        let rawPoints = models.compactMap { model -> IntelligenceEfficiencyPoint? in
            guard let quality = model.qualityScore,
                  let cost = model.benchmarkCostUSD,
                  let elapsedSeconds = model.elapsedSeconds,
                  let validTasks = model.validTasks,
                  cost > 0,
                  elapsedSeconds > 0,
                  validTasks > 0 else { return nil }
            let qualityValue = NSDecimalNumber(decimal: quality).doubleValue
            let averageCost = NSDecimalNumber(decimal: cost / Decimal(validTasks)).doubleValue
            let averageMinutes = elapsedSeconds / Double(validTasks) / 60
            let rawCombinedCost = averageCost
                * pow(averageMinutes / 10, combinedCostWeight)
                * 100
            guard qualityValue.isFinite,
                  qualityValue > 0,
                  averageCost.isFinite,
                  averageMinutes.isFinite,
                  rawCombinedCost.isFinite,
                  rawCombinedCost > 0 else { return nil }
            return .init(
                id: model.id,
                modelName: model.descriptor.displayName,
                quality: qualityValue,
                averageCostUSD: averageCost,
                averageMinutes: averageMinutes,
                rawCombinedCost: rawCombinedCost,
                combinedCostIndex: 0
            )
        }
        guard let maximum = rawPoints.map(\.rawCombinedCost).max(), maximum > 0 else { return [] }
        return rawPoints.map {
            .init(
                id: $0.id,
                modelName: $0.modelName,
                quality: $0.quality,
                averageCostUSD: $0.averageCostUSD,
                averageMinutes: $0.averageMinutes,
                rawCombinedCost: $0.rawCombinedCost,
                combinedCostIndex: $0.rawCombinedCost / maximum * 100
            )
        }
        .sorted {
            let order = $0.modelName.localizedStandardCompare($1.modelName)
            return order == .orderedSame ? $0.id.upstreamKey < $1.id.upstreamKey : order == .orderedAscending
        }
    }
}
