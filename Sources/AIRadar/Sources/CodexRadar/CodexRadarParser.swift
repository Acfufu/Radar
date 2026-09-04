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
            sourceStatus: statusProjection(dto, fetchedAt: fetchedAt),
            stationStatus: stationStatusProjection(dto, fetchedAt: fetchedAt)
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
                models: models,
                dataSource: dto.modelIQ.dataSource.map { source in
                    BenchmarkDataSourceInfo(
                        type: source.type,
                        url: source.url,
                        selection: source.selection,
                        checkedAt: source.checkedAt,
                        validCells: source.validCells
                    )
                }
            ))
        } catch let error as SegmentError {
            return .failure(error)
        } catch {
            return .failure(ClaudeRadarValidator.validation("Codex Radar benchmark projection failed validation"))
        }
    }

    private func statusProjection(
        _ dto: CodexRadarDTO,
        fetchedAt: Date
    ) -> SegmentProjection<SourceStatusDataset> {
        guard let quota = dto.modelIQ.quotaRadar else {
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
                quotaEstimates: estimates,
                trend: quota.trend.map { points in
                    points.map { point in
                        QuotaTrendPoint(
                            date: point.date,
                            fiveH5x: point.fiveH5x?.value,
                            fiveH20x: point.fiveH20x?.value,
                            fiveHPlus: point.fiveHPlus?.value,
                            rate: point.rate?.value,
                            offset: point.offset?.value
                        )
                    }
                },
                check: dto.modelIQ.quotaCheck.map { check in
                    QuotaCheckInfo(
                        planType: check.planType,
                        creditsAvailable: check.creditsAvailable,
                        limitReached: check.limitReached,
                        allowed: check.allowed
                    )
                },
                calibration: dto.modelIQ.quotaCalibration.map { calibration in
                    QuotaCalibrationInfo(
                        date: calibration.date,
                        status: calibration.status,
                        primaryWindow: calibration.primaryWindow,
                        globalConcurrency: calibration.globalConcurrency,
                        checkedAt: calibration.checkedAt
                    )
                }
            ))
        } catch let error as SegmentError {
            return .failure(error)
        } catch {
            return .failure(ClaudeRadarValidator.validation("Codex Radar quota projection failed validation"))
        }
    }

    private func stationStatusProjection(
        _ dto: CodexRadarDTO,
        fetchedAt: Date
    ) -> SegmentProjection<CodexStationStatusDataset>? {
        // Spec §5.1: optional station-status surface; failure here never
        // blocks the benchmark/source-status main chain.
        guard dto.window != nil || dto.prediction != nil || dto.tiboPresence != nil
            || dto.status != nil || dto.timezone != nil else {
            return nil
        }
        do {
            let dataset = try decodeStationStatus(dto, fetchedAt: fetchedAt)
            return .success(dataset)
        } catch {
            return .failure(SegmentError(kind: .decoding, message: "Codex Radar station status could not be decoded"))
        }
    }

    private func decodeStationStatus(
        _ dto: CodexRadarDTO,
        fetchedAt: Date
    ) throws -> CodexStationStatusDataset {
        CodexStationStatusDataset(
            sourceID: .codexRadar,
            fetchedAt: fetchedAt,
            monitoredAt: dto.monitoredAt,
            timezone: dto.timezone,
            windowOpen: dto.windowOpen,
            status: dto.status,
            recommendedAction: dto.recommendedAction,
            window: dto.window.map { window in
                .init(
                    isOpen: window.isOpen,
                    status: window.status,
                    action: window.action,
                    message: window.message,
                    title: window.title,
                    scope: window.scope,
                    openedAt: window.openedAt,
                    closedAt: window.closedAt,
                    sourceURL: window.sourceURL
                )
            },
            prediction: dto.prediction.map { prediction in
                .init(
                    level: prediction.level,
                    probability24h: prediction.probability24h,
                    probability48h: prediction.probability48h,
                    summary: prediction.summary,
                    summaryEN: prediction.summaryEN,
                    updatedAt: prediction.updatedAt
                )
            },
            tiboPresence: dto.tiboPresence.map { presence in
                // D13: upstream observations stored verbatim; never inferred.
                .init(
                    timezone: presence.timezone,
                    locationLabelZH: presence.locationLabelZH,
                    locationLabelEN: presence.locationLabelEN,
                    probability: presence.probability,
                    confidence: presence.confidence,
                    evidenceSummaryZH: presence.evidenceSummaryZH,
                    evidenceSummaryEN: presence.evidenceSummaryEN,
                    sourceURLs: presence.sourceURLs,
                    shouldDisplay: presence.shouldDisplay,
                    safetyNoteZH: presence.safetyNoteZH,
                    safetyNoteEN: presence.safetyNoteEN,
                    observedAt: presence.observedAt,
                    updatedAt: presence.updatedAt
                )
            }
        )
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
            cacheHitPercent: cacheHitPercent,
            wallTimeHuman: candidate.run.wallTimeHuman,
            averageCostUSD: candidate.run.averageCostUSD?.value,
            averageTaskSeconds: candidate.run.averageTaskSeconds,
            averageTaskTimeHuman: candidate.run.averageTaskTimeHuman,
            costUSDBasis: candidate.run.costUSDBasis
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
