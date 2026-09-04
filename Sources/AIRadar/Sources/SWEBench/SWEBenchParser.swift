import Foundation

struct SWEBenchParser: RadarPayloadParser, Sendable {
    private static let verifiedTaskCount = 500

    func parseBenchmarkEnvelope(_ data: Data, fetchedAt: Date) throws -> RadarEnvelopeProjection {
        let dto: SWEBenchLeaderboardsDTO
        do {
            dto = try JSONDecoder().decode(SWEBenchLeaderboardsDTO.self, from: data)
        } catch {
            throw SegmentError(kind: .decoding, message: "SWE-bench leaderboard could not be decoded")
        }

        let benchmark: SegmentProjection<BenchmarkDataset>
        do {
            benchmark = .success(try project(dto, fetchedAt: fetchedAt))
        } catch let error as SegmentError {
            benchmark = .failure(error)
        } catch {
            benchmark = .failure(ClaudeRadarValidator.validation("SWE-bench projection failed validation"))
        }
        return RadarEnvelopeProjection(
            benchmark: benchmark,
            sourceStatus: .failure(.init(
                kind: .disabled,
                message: "SWE-bench does not publish Radar quota or account status"
            ))
        )
    }

    func parseCommunityEnvelope(
        _ data: Data,
        fetchedAt: Date
    ) throws -> SegmentProjection<CommunityDataset> {
        .failure(.init(kind: .disabled, message: "SWE-bench does not publish Radar community ratings"))
    }

    private func project(_ dto: SWEBenchLeaderboardsDTO, fetchedAt: Date) throws -> BenchmarkDataset {
        let boards = dto.leaderboards.filter { $0.name == "bash-only" }
        guard boards.count == 1, let board = boards.first else {
            throw ClaudeRadarValidator.validation("SWE-bench bash-only leaderboard is missing or duplicated")
        }

        var unique: [String: SWEBenchLeaderboardsDTO.Result] = [:]
        for result in board.results {
            guard result.miniSWEAgentVersion?.hasPrefix("2.") == true, result.warning == nil else { continue }
            let folder = result.folder.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let version = result.miniSWEAgentVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !folder.isEmpty, !name.isEmpty, !version.isEmpty else {
                throw ClaudeRadarValidator.validation("SWE-bench result identity is empty")
            }
            if let existing = unique[folder] {
                guard existing.resolved.value == result.resolved.value,
                      existing.cost?.value == result.cost?.value,
                      existing.miniSWEAgentVersion == result.miniSWEAgentVersion else {
                    throw ClaudeRadarValidator.validation("SWE-bench contains conflicting duplicate result identities")
                }
                if name.localizedStandardCompare(existing.name) == .orderedAscending {
                    unique[folder] = result
                }
            } else {
                unique[folder] = result
            }
        }

        guard !unique.isEmpty, unique.count <= ClaudeRadarValidator.maximumModelCount else {
            throw ClaudeRadarValidator.validation("SWE-bench mini-SWE-agent v2 result set is empty or too large")
        }
        let models = try unique
            .map { try model(folder: $0.key, result: $0.value) }
            .sorted { $0.id.upstreamKey < $1.id.upstreamKey }
        return BenchmarkDataset(
            sourceID: .sweBenchVerified,
            sourceUpdatedAt: nil,
            fetchedAt: fetchedAt,
            benchmarkName: "SWE-bench Verified · mini-SWE-agent v2",
            benchmarkVersion: "mini-SWE-agent 2.x",
            seriesRevision: SWEBenchConfiguration.seriesRevision,
            models: models
        )
    }

    private func model(
        folder: String,
        result: SWEBenchLeaderboardsDTO.Result
    ) throws -> ModelBenchmark {
        let resolvedTasksDecimal = result.resolved.value * 5
        let resolvedTasks = NSDecimalNumber(decimal: resolvedTasksDecimal).intValue
        guard Decimal(resolvedTasks) == resolvedTasksDecimal else {
            throw ClaudeRadarValidator.validation("SWE-bench resolved percentage is not exact for 500 tasks")
        }
        let displayName = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = ModelID(sourceID: .sweBenchVerified, upstreamKey: folder)
        let model = ModelBenchmark(
            id: id,
            descriptor: .init(id: id, upstreamName: result.name, displayName: displayName),
            qualityScore: result.resolved.value,
            passedTasks: resolvedTasks,
            validTasks: Self.verifiedTaskCount,
            invalidTasks: Self.verifiedTaskCount - resolvedTasks,
            benchmarkCostUSD: result.cost?.value,
            inputTokens: nil,
            outputTokens: nil,
            cacheReadTokens: nil,
            cacheCreationTokens: nil,
            totalTokens: nil,
            elapsedSeconds: nil,
            agentSteps: nil,
            cacheHitPercent: nil
        )
        try ClaudeRadarValidator.validateBenchmark(model)
        return model
    }
}
