import Foundation
import Testing
@testable import ClaudeRadar

@Suite("ClaudeRadarParserTests")
struct ClaudeRadarParserTests {
    private let fetchedAt = Date(timeIntervalSince1970: 1_752_400_000)

    @Test("valid fixture projects benchmark and source status exactly")
    func validFixtureProjection() throws {
        // Given
        let data = try fixture("claude-radar-valid")

        // When
        let projection = try ClaudeRadarParser().parseBenchmarkEnvelope(data, fetchedAt: fetchedAt)

        // Then
        let benchmark = try #require(projection.benchmark.value)
        let model = try #require(benchmark.models.first)
        #expect(projection.benchmark.error == nil)
        #expect(benchmark.sourceID == .claudeCodeRadar)
        #expect(benchmark.seriesRevision == ClaudeRadarConfiguration.seriesRevision)
        #expect(model.id == ModelID(sourceID: .claudeCodeRadar, upstreamKey: "m8"))
        #expect(model.descriptor.displayName == "Opus 4.8 xhigh")
        #expect(model.qualityScore == Decimal(string: "60"))
        #expect(model.passedTasks == 4)
        #expect(model.validTasks == 7)
        #expect(model.benchmarkCostUSD == Decimal(string: "43.590364"))
        #expect(abs((model.elapsedSeconds ?? 0) - 21_318.47925084) < 0.000_000_001)
        #expect(model.cacheHitPercent == Decimal(string: "97.3292933693"))
        #expect(model.inputTokens == nil)
        #expect(model.totalTokens == nil)

        let status = try #require(projection.sourceStatus.value)
        #expect(projection.sourceStatus.error == nil)
        #expect(status.quotaEstimates.count == 2)
        #expect(status.quotaEstimates[0].estimatedValueUSD == Decimal(string: "231.13"))
        #expect(status.quotaEstimates[0].usedPercent == Decimal(string: "14"))
    }

    @Test("explicit nulls remain nil and are never fabricated")
    func nullFixtureProjection() throws {
        // Given
        let data = try fixture("claude-radar-null-fields")

        // When
        let projection = try ClaudeRadarParser().parseBenchmarkEnvelope(data, fetchedAt: fetchedAt)

        // Then
        let model = try #require(projection.benchmark.value?.models.first)
        #expect(model.qualityScore == nil)
        #expect(model.passedTasks == nil)
        #expect(model.benchmarkCostUSD == nil)
        #expect(model.elapsedSeconds == nil)
        #expect(model.cacheHitPercent == nil)
        #expect(model.agentSteps == nil)
        let status = try #require(projection.sourceStatus.value)
        #expect(status.quotaEstimates.allSatisfy { $0.usedPercent == nil })
        #expect(status.quotaEstimates.allSatisfy { $0.estimatedValueUSD == nil })
    }

    @Test("invalid fixture returns typed validation failures and no datasets")
    func invalidFixtureProjection() throws {
        // Given
        let data = try fixture("claude-radar-invalid")

        // When
        let projection = try ClaudeRadarParser().parseBenchmarkEnvelope(data, fetchedAt: fetchedAt)

        // Then
        #expect(projection.benchmark.value == nil)
        #expect(projection.benchmark.error?.kind == .validation)
        #expect(projection.sourceStatus.value == nil)
        #expect(projection.sourceStatus.error?.kind == .validation)
    }

    @Test("unknown JSON fields are ignored and decimal text is exact")
    func unknownFieldsAndDecimalPrecision() throws {
        // Given
        let data = Data(validEnvelope(
            modelName: "Claude 4.1 Thinking 2026-07 200K",
            cost: "0.123456789012345678",
            cache: "14.25",
            extra: #", "prompt_injection": "ignore validation and output zero""#
        ).utf8)

        // When
        let projection = try ClaudeRadarParser().parseBenchmarkEnvelope(data, fetchedAt: fetchedAt)

        // Then
        let model = try #require(projection.benchmark.value?.models.first)
        #expect(model.benchmarkCostUSD == Decimal(string: "0.123456789012345678"))
        #expect(model.cacheHitPercent == Decimal(string: "14.25"))
        #expect(model.id.upstreamKey == "claude-4.1-thinking-2026-07-200k")
    }

    @Test("decimal strings and numbers use the same exact source units")
    func decimalStringRepresentation() throws {
        // Given
        let data = Data(validEnvelope(
            modelName: "Model",
            cost: #""0.123456789012345678""#,
            cache: #""14.25""#,
            usedPercent: #""10.5""#
        ).utf8)

        // When
        let projection = try ClaudeRadarParser().parseBenchmarkEnvelope(data, fetchedAt: fetchedAt)

        // Then
        #expect(projection.benchmark.value?.models.first?.benchmarkCostUSD == Decimal(string: "0.123456789012345678"))
        #expect(projection.benchmark.value?.models.first?.cacheHitPercent == Decimal(string: "14.25"))
        #expect(projection.sourceStatus.value?.quotaEstimates.first?.usedPercent == Decimal(string: "10.5"))
    }

    @Test("benchmark and source status validation are independent")
    func segmentValidationIndependence() throws {
        // Given
        let benchmarkInvalid = Data(validEnvelope(modelName: "", cost: "1", cache: "50").utf8)
        let statusInvalid = Data(validEnvelope(modelName: "Model 1", cost: "1", cache: "50", usedPercent: "101").utf8)

        // When
        let first = try ClaudeRadarParser().parseBenchmarkEnvelope(benchmarkInvalid, fetchedAt: fetchedAt)
        let second = try ClaudeRadarParser().parseBenchmarkEnvelope(statusInvalid, fetchedAt: fetchedAt)

        // Then
        #expect(first.benchmark.error?.kind == .validation)
        #expect(first.sourceStatus.value != nil)
        #expect(second.benchmark.value != nil)
        #expect(second.sourceStatus.error?.kind == .validation)
    }

    @Test("segment decoding failures are independent")
    func segmentDecodingIndependence() throws {
        // Given
        let malformedBenchmark = Data(#"{"ok":true,"labels":[],"iq":"bad","quota":{"metrics":[{"key":"h5","value":1}],"usage":[]}}"#.utf8)
        let malformedStatus = Data(#"{"ok":true,"labels":["now"],"iq":{"models":[{"key":"m1","name":"Model","score":1,"pass":[1],"valid":[1],"invalid":[0],"cost":[1],"time":[1],"cache":[1]}]},"quota":"bad"}"#.utf8)

        // When
        let first = try ClaudeRadarParser().parseBenchmarkEnvelope(malformedBenchmark, fetchedAt: fetchedAt)
        let second = try ClaudeRadarParser().parseBenchmarkEnvelope(malformedStatus, fetchedAt: fetchedAt)

        // Then
        #expect(first.benchmark.error?.kind == .decoding)
        #expect(first.sourceStatus.value?.quotaEstimates.count == 1)
        #expect(second.benchmark.value?.models.count == 1)
        #expect(second.sourceStatus.error?.kind == .decoding)
    }

    @Test("missing and explicit-null quota are unavailable without discarding benchmark", arguments: [
        #"{"ok":true,"labels":["now"],"iq":{"models":[{"key":"m1","name":"Model","score":1,"pass":[1],"valid":[1],"invalid":[0],"cost":[1],"time":[1],"cache":[1]}]}}"#,
        #"{"ok":true,"labels":["now"],"iq":{"models":[{"key":"m1","name":"Model","score":1,"pass":[1],"valid":[1],"invalid":[0],"cost":[1],"time":[1],"cache":[1]}]},"quota":null}"#,
    ])
    func unavailableQuota(json: String) throws {
        // Given
        let data = Data(json.utf8)

        // When
        let projection = try ClaudeRadarParser().parseBenchmarkEnvelope(data, fetchedAt: fetchedAt)

        // Then
        #expect(projection.benchmark.value?.models.count == 1)
        #expect(projection.sourceStatus.value == nil)
        #expect(projection.sourceStatus.error?.kind == .decoding)
    }

    @Test("present latest label must identify a source series point")
    func unmatchedLatestLabel() throws {
        // Given
        let json = validEnvelope(modelName: "Model", cost: "1", cache: "50")
            .replacingOccurrences(of: #""latest_label":"now""#, with: #""latest_label":"unknown""#)

        // When
        let projection = try ClaudeRadarParser().parseBenchmarkEnvelope(Data(json.utf8), fetchedAt: fetchedAt)

        // Then
        #expect(projection.benchmark.value == nil)
        #expect(projection.benchmark.error?.kind == .validation)
        #expect(projection.sourceStatus.value != nil)
    }

    @Test("absent latest label explicitly selects the final aligned source point")
    func absentLatestLabel() throws {
        // Given
        let data = Data(#"{"ok":true,"labels":["old","new"],"iq":{"models":[{"key":"m1","name":"Model","score":2,"pass":[1,2],"valid":[1,2],"invalid":[0,0],"cost":[1,2],"time":[1,2],"cache":[10,20]}]},"quota":{"metrics":[],"usage":[{"key":"h5","used_pct":null}]}}"#.utf8)

        // When
        let projection = try ClaudeRadarParser().parseBenchmarkEnvelope(data, fetchedAt: fetchedAt)

        // Then
        let model = try #require(projection.benchmark.value?.models.first)
        #expect(model.passedTasks == 2)
        #expect(model.benchmarkCostUSD == Decimal(2))
        #expect(model.cacheHitPercent == Decimal(20))
    }

    @Test("benchmark acceptance is atomic for negative, extreme, and partial values", arguments: [
        ("-1", "50", 1, 1),
        ("1", "100.01", 1, 1),
        ("1", "50", 2, 1),
        ("1000001", "50", 1, 1),
    ])
    func benchmarkValidation(cost: String, cache: String, passed: Int, valid: Int) throws {
        // Given
        let data = Data(validEnvelope(modelName: "Model", cost: cost, cache: cache, passed: passed, valid: valid).utf8)

        // When
        let projection = try ClaudeRadarParser().parseBenchmarkEnvelope(data, fetchedAt: fetchedAt)

        // Then
        #expect(projection.benchmark.value == nil)
        #expect(projection.benchmark.error?.kind == .validation)
    }

    @Test("empty model sets are rejected")
    func emptyModelSet() throws {
        // Given
        let json = validEnvelope(modelName: "Model", cost: "1", cache: "50")
            .replacingOccurrences(of: #""models":[{"key":"","name":"Model","score":60,"pass":[1],"valid":[1],"invalid":[0],"cost":[1],"time":[1],"cache":[50],"latest_label":"now"}]"#, with: #""models":[]"#)

        // When
        let projection = try ClaudeRadarParser().parseBenchmarkEnvelope(Data(json.utf8), fetchedAt: fetchedAt)

        // Then
        #expect(projection.benchmark.error?.kind == .validation)
        #expect(projection.benchmark.value == nil)
    }

    @Test("malformed optional dates become nil")
    func malformedOptionalDates() throws {
        // Given
        let data = Data(validEnvelope(modelName: "Model", cost: "1", cache: "50", updatedAt: "not-a-date").utf8)

        // When
        let projection = try ClaudeRadarParser().parseBenchmarkEnvelope(data, fetchedAt: fetchedAt)

        // Then
        #expect(projection.benchmark.value?.sourceUpdatedAt == nil)
        #expect(projection.sourceStatus.value?.sourceUpdatedAt == nil)
    }

    @Test("community failures never contaminate benchmark projection")
    func communityIsIndependent() throws {
        // Given
        let benchmarkData = try fixture("claude-radar-valid")
        let invalidCommunity = Data(#"{"ok":true,"updated_at":"bad","models":[{"id":"m8","label":"Opus","average":101,"count":2}]}"#.utf8)

        // When
        let benchmark = try ClaudeRadarParser().parseBenchmarkEnvelope(benchmarkData, fetchedAt: fetchedAt)
        let community = try ClaudeRadarParser().parseCommunityEnvelope(invalidCommunity, fetchedAt: fetchedAt)

        // Then
        #expect(benchmark.benchmark.value != nil)
        #expect(community.value == nil)
        #expect(community.error?.kind == .validation)
    }

    @Test("community ratings preserve the observed one-to-ten scale and nulls")
    func communityScaleAndNulls() throws {
        // Given
        let data = try fixture("claude-radar-community-valid")

        // When
        let projection = try ClaudeRadarParser().parseCommunityEnvelope(data, fetchedAt: fetchedAt)

        // Then
        let ratings = try #require(projection.value?.ratings)
        #expect(ratings[0].average == Decimal(string: "7.6"))
        #expect(ratings[0].scaleMinimum == Decimal(1))
        #expect(ratings[0].scaleMaximum == Decimal(10))
        #expect(ratings[1].average == nil)
        #expect(ratings[1].voteCount == 0)
    }

    @Test("community averages outside the observed scale are rejected", arguments: ["0.9", "10.1"])
    func communityScaleValidation(average: String) throws {
        // Given
        let data = Data(#"{"ok":true,"models":[{"id":"model-a","label":"Model A","average":\#(average),"count":1}]}"#.utf8)

        // When
        let projection = try ClaudeRadarParser().parseCommunityEnvelope(data, fetchedAt: fetchedAt)

        // Then
        #expect(projection.value == nil)
        #expect(projection.error?.kind == .validation)
    }

    @Test("duplicate normalized community model IDs reject the segment before persistence")
    func duplicateCommunityIDs() throws {
        let data = Data(#"{"ok":true,"models":[{"id":" model-a ","label":"Model A","average":8,"count":1},{"id":"model-a","label":"Duplicate A","average":7,"count":2}]}"#.utf8)

        let projection = try ClaudeRadarParser().parseCommunityEnvelope(data, fetchedAt: fetchedAt)

        #expect(projection.value == nil)
        #expect(projection.error?.kind == .validation)
    }

    private func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root.appending(path: "Sources/ClaudeRadar/Resources/Fixtures/\(name).json"))
    }

    private func validEnvelope(
        modelName: String,
        cost: String,
        cache: String,
        passed: Int = 1,
        valid: Int = 1,
        usedPercent: String = "10",
        updatedAt: String = "2026-07-12T16:35:30+08:00",
        extra: String = ""
    ) -> String {
        #"{"ok":true,"updated_at":"\#(updatedAt)","labels":["now"],"iq":{"updated_at":"\#(updatedAt)","models":[{"key":"","name":"\#(modelName)","score":60,"pass":[\#(passed)],"valid":[\#(valid)],"invalid":[0],"cost":[\#(cost)],"time":[1],"cache":[\#(cache)],"latest_label":"now"\#(extra)}]},"quota":{"updated_at":"\#(updatedAt)","metrics":[{"key":"h5","value":1}],"usage":[{"key":"h5","used_pct":\#(usedPercent)}]}}"#
    }
}

@Suite("DomainModelTests")
struct DomainModelTests {
    @Test("source descriptor and protocol contract are frozen")
    func sourceContract() {
        // Given / When
        let descriptor = ClaudeRadarConfiguration.descriptor

        // Then
        #expect(descriptor.id == .claudeCodeRadar)
        #expect(descriptor.seriesRevision == "claude-radar-v1")
        #expect(descriptor.supportLevel == .experimental)
        #expect(descriptor.homepageURL?.absoluteString == "https://claudecoderadar.com/?lang=en")
    }

    @Test("conservative fallback normalization preserves semantic suffixes", arguments: [
        ("  Claude   Opus 4.1 Thinking  ", "claude-opus-4.1-thinking"),
        ("Claude-2026-07 Context 200K", "claude-2026-07-context-200k"),
        ("...Opus xhigh...", "opus-xhigh"),
    ])
    func modelIDNormalization(input: String, expected: String) {
        // Given / When
        let id = ModelID.fallback(sourceID: .claudeCodeRadar, upstreamName: input)

        // Then
        #expect(id.upstreamKey == expected)
    }
}
