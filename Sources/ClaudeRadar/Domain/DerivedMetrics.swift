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
