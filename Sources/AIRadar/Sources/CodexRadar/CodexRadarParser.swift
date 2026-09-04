import Foundation

struct CodexRadarParser: RadarPayloadParser, Sendable {
    func parseBenchmarkEnvelope(_ data: Data, fetchedAt: Date) throws -> RadarEnvelopeProjection {
        let dto: CodexRadarDTO
        do {
            dto = try JSONDecoder().decode(CodexRadarDTO.self, from: data)
        } catch {
            throw SegmentError(kind: .decoding, message: "Codex Radar public summary could not be decoded")
        }
        return RadarEnvelopeProjection(
            benchmark: benchmarkProjection(dto, fetchedAt: fetchedAt),
            sourceStatus: statusProjection(dto.modelIQ.quotaRadar, fetchedAt: fetchedAt)
        )
    }

    func parseCommunityEnvelope(_ data: Data, fetchedAt: Date) throws -> SegmentProjection<CommunityDataset> {
        let dto: RadarCommunityDTO
        do {
            dto = try JSONDecoder().decode(RadarCommunityDTO.self, from: data)
        } catch {
            throw SegmentError(kind: .decoding, message: "Codex Radar community response could not be decoded")
        }
        guard dto.ok else {
            return .failure(ClaudeRadarValidator.validation("Codex Radar community response was not successful"))
        }
        do {
            let ratings = try dto.models.map { item in
                let name = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
                let id = ModelID(
                    sourceID: .codexRadar,
                    upstreamKey: item.id.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                let rating = CommunityRating(
                    id: id,
                    model: ModelDescriptor(id: id, upstreamName: item.label, displayName: name),
                    average: item.average?.value,
                    voteCount: item.count,
                    scaleMinimum: ClaudeRadarValidator.communityScaleMinimum,
                    scaleMaximum: ClaudeRadarValidator.communityScaleMaximum
                )
                try ClaudeRadarValidator.validateCommunity(rating)
                return rating
            }
            guard !ratings.isEmpty else {
                throw ClaudeRadarValidator.validation("Codex Radar community model set is empty")
            }
            try ClaudeRadarValidator.validateCommunity(ratings)
            return .success(CommunityDataset(
                sourceID: .codexRadar,
                sourceUpdatedAt: parseDate(dto.updatedAt),
                fetchedAt: fetchedAt,
                ratings: ratings
            ))
        } catch let error as SegmentError {
            return .failure(error)
        } catch {
            return .failure(ClaudeRadarValidator.validation("Codex Radar community projection failed validation"))
        }
    }

    private func benchmarkProjection(_ dto: CodexRadarDTO, fetchedAt: Date) -> SegmentProjection<BenchmarkDataset> {
        do {
            let models = try candidates(dto.modelIQ).map(project).sorted { $0.id.upstreamKey < $1.id.upstreamKey }
            guard !models.isEmpty, models.count <= ClaudeRadarValidator.maximumModelCount else {
                throw ClaudeRadarValidator.validation("Codex Radar model set is empty or too large")
            }
            return .success(BenchmarkDataset(
                sourceID: .codexRadar,
                sourceUpdatedAt: parseDate(dto.monitoredAt ?? dto.modelIQ.quotaRadar?.updatedAt),
                fetchedAt: fetchedAt,
                benchmarkName: "Codex Radar IQ",
                benchmarkVersion: dto.schemaVersion,
                seriesRevision: CodexRadarConfiguration.seriesRevision,
                models: models
            ))
        } catch let error as SegmentError {
            return .failure(error)
        } catch {
            return .failure(ClaudeRadarValidator.validation("Codex Radar benchmark projection failed validation"))
        }
    }

    private func statusProjection(
        _ quota: CodexRadarDTO.QuotaRadar?,
        fetchedAt: Date
    ) -> SegmentProjection<SourceStatusDataset> {
        guard let quota else {
            return .failure(SegmentError(kind: .decoding, message: "Codex Radar quota summary is unavailable"))
        }
        do {
            let window = quota.basisWindowLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "7d"
            let estimates = try quota.rows.map { row in
                let tier = row.tier.trimmingCharacters(in: .whitespacesAndNewlines)
                let estimate = SourceQuotaEstimate(
                    id: "\(tier.lowercased().replacingOccurrences(of: " ", with: "-"))-\(window.lowercased())",
                    windowLabel: "\(tier) · \(window)",
                    usedPercent: nil,
                    estimatedValueUSD: window.caseInsensitiveCompare("5h") == .orderedSame
                        ? row.fiveHour?.value
                        : row.sevenDay?.value,
                    resetDescription: row.basis
                )
                try ClaudeRadarValidator.validateStatus(estimate)
                return estimate
            }
            guard !estimates.isEmpty else {
                throw ClaudeRadarValidator.validation("Codex Radar quota estimate set is empty")
            }
            return .success(SourceStatusDataset(
                sourceID: .codexRadar,
                sourceUpdatedAt: parseDate(quota.updatedAt),
                fetchedAt: fetchedAt,
                quotaEstimates: estimates
            ))
        } catch let error as SegmentError {
            return .failure(error)
        } catch {
            return .failure(ClaudeRadarValidator.validation("Codex Radar quota projection failed validation"))
        }
    }

    private func candidates(_ modelIQ: CodexRadarDTO.ModelIQ) throws -> [Candidate] {
        var candidates = modelIQ.comparisons.values.map {
            Candidate(label: $0.label, model: $0.model, effort: $0.reasoningEffort, run: $0.latest)
        }
        if let run = modelIQ.latest,
           let model = run.model,
           let effort = run.reasoningEffort {
            candidates.append(Candidate(label: nil, model: model, effort: effort, run: run))
        }
        var unique: [String: Candidate] = [:]
        for candidate in candidates {
            let id = try modelKey(model: candidate.model, effort: candidate.effort)
            if unique[id] == nil { unique[id] = candidate }
        }
        return Array(unique.values)
    }

    private func project(_ candidate: Candidate) throws -> ModelBenchmark {
        let key = try modelKey(model: candidate.model, effort: candidate.effort)
        let id = ModelID(sourceID: .codexRadar, upstreamKey: key)
        let displayName = candidate.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "\(candidate.model) \(candidate.effort)"
        if let cached = candidate.run.cachedInputTokens,
           let input = candidate.run.inputTokens,
           cached > input {
            throw ClaudeRadarValidator.validation("Codex Radar cached input tokens exceed input tokens")
        }
        let cacheHitPercent: Decimal? = if let cached = candidate.run.cachedInputTokens,
                                           let input = candidate.run.inputTokens,
                                           input > 0 {
            Decimal(cached) / Decimal(input) * 100
        } else {
            nil
        }
        let model = ModelBenchmark(
            id: id,
            descriptor: ModelDescriptor(id: id, upstreamName: displayName, displayName: displayName),
            qualityScore: candidate.run.score?.value,
            passedTasks: candidate.run.passed,
            validTasks: candidate.run.validTasks ?? candidate.run.tasks,
            invalidTasks: candidate.run.invalid,
            benchmarkCostUSD: candidate.run.costUSD?.value,
            inputTokens: candidate.run.inputTokens,
            outputTokens: candidate.run.outputTokens,
            cacheReadTokens: candidate.run.cachedInputTokens,
            cacheCreationTokens: nil,
            totalTokens: candidate.run.totalTokens,
            elapsedSeconds: candidate.run.wallSeconds,
            agentSteps: nil,
            cacheHitPercent: cacheHitPercent
        )
        try ClaudeRadarValidator.validateBenchmark(model)
        return model
    }

    private func modelKey(model: String, effort: String) throws -> String {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let effort = effort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !effort.isEmpty else {
            throw ClaudeRadarValidator.validation("Codex Radar model identity is empty")
        }
        return "\(model)-\(effort)"
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct Candidate: Sendable {
    let label: String?
    let model: String
    let effort: String
    let run: CodexRadarDTO.Run
}
