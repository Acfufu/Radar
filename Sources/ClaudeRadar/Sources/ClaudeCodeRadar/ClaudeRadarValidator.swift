import Foundation

enum ClaudeRadarValidator {
    static let maximumModelCount = 500
    static let maximumTaskCount = 10_000_000
    static let maximumCostUSD = Decimal(1_000_000)
    static let maximumElapsedHours = Decimal(100_000)
    static let maximumQualityScore = Decimal(10_000)
    static let maximumQuotaValueUSD = Decimal(1_000_000)
    static let maximumVoteCount = 1_000_000_000
    static let communityScaleMinimum = Decimal(1)
    static let communityScaleMaximum = Decimal(10)

    static func validateBenchmark(_ model: ModelBenchmark) throws {
        guard !model.descriptor.displayName.isEmpty, !model.id.upstreamKey.isEmpty else {
            throw validation("Benchmark model identity is empty")
        }
        try validateNonnegative(model.qualityScore, maximum: maximumQualityScore, field: "quality score")
        try validateCount(model.passedTasks, field: "passed tasks")
        try validateCount(model.validTasks, field: "valid tasks")
        try validateCount(model.invalidTasks, field: "invalid tasks")
        try validateCount64(model.inputTokens, field: "input tokens")
        try validateCount64(model.outputTokens, field: "output tokens")
        try validateCount64(model.cacheReadTokens, field: "cache read tokens")
        try validateCount64(model.cacheCreationTokens, field: "cache creation tokens")
        try validateCount64(model.totalTokens, field: "total tokens")
        try validateCount(model.agentSteps, field: "agent steps")
        if let passed = model.passedTasks, let valid = model.validTasks, passed > valid {
            throw validation("Passed tasks exceed valid tasks")
        }
        try validateNonnegative(model.benchmarkCostUSD, maximum: maximumCostUSD, field: "benchmark cost")
        if let elapsed = model.elapsedSeconds, elapsed < 0 || elapsed > NSDecimalNumber(decimal: maximumElapsedHours).doubleValue * 3_600 {
            throw validation("Elapsed time is outside the source contract")
        }
        try validatePercent(model.cacheHitPercent, field: "cache hit percentage")
    }

    static func validateStatus(_ estimate: SourceQuotaEstimate) throws {
        guard !estimate.id.isEmpty, !estimate.windowLabel.isEmpty else {
            throw validation("Source quota identity is empty")
        }
        try validatePercent(estimate.usedPercent, field: "used percentage")
        try validateNonnegative(estimate.estimatedValueUSD, maximum: maximumQuotaValueUSD, field: "quota value")
    }

    static func validateCommunity(_ rating: CommunityRating) throws {
        guard !rating.id.upstreamKey.isEmpty, !rating.model.displayName.isEmpty else {
            throw validation("Community model identity is empty")
        }
        if let average = rating.average, average < communityScaleMinimum || average > communityScaleMaximum {
            throw validation("Community average is outside the observed 1...10 scale")
        }
        if let count = rating.voteCount, count < 0 || count > maximumVoteCount {
            throw validation("Community vote count is outside the source contract")
        }
    }

    static func validateCommunity(_ ratings: [CommunityRating]) throws {
        var ids = Set<ModelID>()
        for rating in ratings where !ids.insert(rating.id).inserted {
            throw validation("Duplicate community model identity")
        }
    }

    static func validation(_ message: String) -> SegmentError {
        SegmentError(kind: .validation, message: message)
    }

    private static func validateCount(_ value: Int?, field: String) throws {
        if let value, value < 0 || value > maximumTaskCount {
            throw validation("\(field) is outside the source contract")
        }
    }

    private static func validateCount64(_ value: Int64?, field: String) throws {
        if let value, value < 0 || value > Int64(maximumTaskCount) * 1_000_000 {
            throw validation("\(field) is outside the source contract")
        }
    }

    private static func validatePercent(_ value: Decimal?, field: String) throws {
        if let value, value < 0 || value > 100 {
            throw validation("\(field) is outside 0...100")
        }
    }

    private static func validateNonnegative(_ value: Decimal?, maximum: Decimal, field: String) throws {
        if let value, value < 0 || value > maximum {
            throw validation("\(field) is outside the source contract")
        }
    }
}
