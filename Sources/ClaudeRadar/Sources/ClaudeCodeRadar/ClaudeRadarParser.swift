import Foundation

struct ClaudeRadarParser: RadarPayloadParser, Sendable {
    func parseBenchmarkEnvelope(_ data: Data, fetchedAt: Date) throws -> RadarEnvelopeProjection {
        let dto: ClaudeRadarDTO
        do {
            dto = try JSONDecoder().decode(ClaudeRadarDTO.self, from: data)
        } catch {
            throw SegmentError(kind: .decoding, message: "Claude Radar envelope could not be decoded")
        }

        guard dto.ok else {
            let failure = SegmentProjection<BenchmarkDataset>.failure(
                ClaudeRadarValidator.validation("Claude Radar response was not successful")
            )
            return RadarEnvelopeProjection(
                benchmark: failure,
                sourceStatus: .failure(ClaudeRadarValidator.validation("Claude Radar response was not successful"))
            )
        }

        return RadarEnvelopeProjection(
            benchmark: benchmarkProjection(dto, fetchedAt: fetchedAt),
            sourceStatus: statusProjection(dto.quota, decoded: dto.statusDecoded, fetchedAt: fetchedAt)
        )
    }

    func parseCommunityEnvelope(_ data: Data, fetchedAt: Date) throws -> SegmentProjection<CommunityDataset> {
        let dto: RadarCommunityDTO
        do {
            dto = try JSONDecoder().decode(RadarCommunityDTO.self, from: data)
        } catch {
            throw SegmentError(kind: .decoding, message: "Claude Radar community response could not be decoded")
        }
        guard dto.ok else {
            return .failure(ClaudeRadarValidator.validation("Claude Radar community response was not successful"))
        }

        do {
            let ratings = try dto.models.map { item in
                let name = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
                let id = ModelID(sourceID: .claudeCodeRadar, upstreamKey: item.id.trimmingCharacters(in: .whitespacesAndNewlines))
                let descriptor = ModelDescriptor(id: id, upstreamName: item.label, displayName: name)
                let rating = CommunityRating(
                    id: id,
                    model: descriptor,
                    average: item.average?.value,
                    voteCount: item.count,
                    scaleMinimum: ClaudeRadarValidator.communityScaleMinimum,
                    scaleMaximum: ClaudeRadarValidator.communityScaleMaximum
                )
                try ClaudeRadarValidator.validateCommunity(rating)
                return rating
            }
            guard !ratings.isEmpty else {
                throw ClaudeRadarValidator.validation("Community model set is empty")
            }
            try ClaudeRadarValidator.validateCommunity(ratings)
            return .success(CommunityDataset(
                sourceID: .claudeCodeRadar,
                sourceUpdatedAt: parseDate(dto.updatedAt),
                fetchedAt: fetchedAt,
                ratings: ratings
            ))
        } catch let error as SegmentError {
            return .failure(error)
        } catch {
            return .failure(ClaudeRadarValidator.validation("Community projection failed validation"))
        }
    }

    private func benchmarkProjection(_ dto: ClaudeRadarDTO, fetchedAt: Date) -> SegmentProjection<BenchmarkDataset> {
        guard dto.benchmarkDecoded, let iq = dto.iq else {
            return .failure(SegmentError(kind: .decoding, message: "Claude Radar benchmark segment could not be decoded"))
        }
        do {
            guard !iq.models.isEmpty, iq.models.count <= ClaudeRadarValidator.maximumModelCount else {
                throw ClaudeRadarValidator.validation("Benchmark model set is empty or too large")
            }
            let models = try iq.models.map { try projectModel($0, labels: dto.labels) }
            return .success(BenchmarkDataset(
                sourceID: .claudeCodeRadar,
                sourceUpdatedAt: parseDate(iq.updatedAt ?? dto.updatedAt),
                fetchedAt: fetchedAt,
                benchmarkName: nil,
                benchmarkVersion: nil,
                seriesRevision: ClaudeRadarConfiguration.seriesRevision,
                models: models
            ))
        } catch let error as SegmentError {
            return .failure(error)
        } catch {
            return .failure(ClaudeRadarValidator.validation("Benchmark projection failed validation"))
        }
    }

    private func projectModel(_ dto: ClaudeRadarDTO.Model, labels: [String]) throws -> ModelBenchmark {
        try validateAlignment(dto, labelCount: labels.count)
        let name = dto.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let upstreamKey = dto.key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let id = upstreamKey.isEmpty
            ? ModelID.fallback(sourceID: .claudeCodeRadar, upstreamName: name)
            : ModelID(sourceID: .claudeCodeRadar, upstreamKey: upstreamKey)
        let descriptor = ModelDescriptor(id: id, upstreamName: dto.name, displayName: name)
        let index: Int?
        if let latestLabel = dto.latestLabel {
            guard let matchedIndex = labels.firstIndex(of: latestLabel)
                ?? seriesLabel(for: dto.latestAt).flatMap({ label in
                    labels.firstIndex { $0.caseInsensitiveCompare(label) == .orderedSame }
                }) else {
                throw ClaudeRadarValidator.validation("Benchmark latest label does not identify a source series point")
            }
            index = matchedIndex
        } else {
            index = labels.indices.last
        }
        let elapsedHours = element(dto.time, at: index)
        let model = ModelBenchmark(
            id: id,
            descriptor: descriptor,
            qualityScore: dto.score?.value,
            passedTasks: element(dto.passed, at: index),
            validTasks: element(dto.valid, at: index),
            invalidTasks: element(dto.invalid, at: index),
            benchmarkCostUSD: element(dto.cost, at: index)?.value,
            inputTokens: nil,
            outputTokens: nil,
            cacheReadTokens: nil,
            cacheCreationTokens: nil,
            totalTokens: nil,
            elapsedSeconds: elapsedHours.map { NSDecimalNumber(decimal: $0.value).doubleValue * 3_600 },
            agentSteps: nil,
            cacheHitPercent: element(dto.cache, at: index)?.value
        )
        try ClaudeRadarValidator.validateBenchmark(model)
        return model
    }

    private func seriesLabel(for timestamp: String?) -> String? {
        guard let timestamp, let date = parseDate(timestamp) else { return nil }
        let timeZone: TimeZone
        if timestamp.hasSuffix("Z") {
            timeZone = TimeZone(secondsFromGMT: 0)!
        } else {
            let offset = timestamp.suffix(6)
            guard offset.count == 6,
                  let sign = offset.first,
                  sign == "+" || sign == "-",
                  let hours = Int(offset.dropFirst().prefix(2)),
                  let minutes = Int(offset.suffix(2)),
                  let zone = TimeZone(secondsFromGMT: (sign == "-" ? -1 : 1) * (hours * 3_600 + minutes * 60)) else {
                return nil
            }
            timeZone = zone
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.month, .day, .hour], from: date)
        guard let month = components.month, let day = components.day, let hour = components.hour else { return nil }
        return "\(month).\(day)\(hour < 12 ? "am" : "pm")"
    }

    private func statusProjection(
        _ quota: ClaudeRadarDTO.Quota?,
        decoded: Bool,
        fetchedAt: Date
    ) -> SegmentProjection<SourceStatusDataset> {
        guard decoded else {
            return .failure(SegmentError(kind: .decoding, message: "Claude Radar source status segment could not be decoded"))
        }
        guard let quota else {
            return .failure(SegmentError(kind: .decoding, message: "Claude Radar source status segment is missing or null"))
        }
        do {
            var metrics: [String: ClaudeRadarDTO.Metric] = [:]
            for metric in quota.metrics {
                guard metrics.updateValue(metric, forKey: metric.key) == nil else {
                    throw ClaudeRadarValidator.validation("Duplicate source quota metric identity")
                }
            }
            var usage: [String: ClaudeRadarDTO.Usage] = [:]
            for item in quota.usage {
                guard usage.updateValue(item, forKey: item.key) == nil else {
                    throw ClaudeRadarValidator.validation("Duplicate source quota usage identity")
                }
            }
            let orderedKeys = quota.metrics.map(\.key) + quota.usage.map(\.key).filter { metrics[$0] == nil }
            let estimates = try orderedKeys.map { key in
                let metric = metrics[key]
                let use = usage[key]
                let estimate = SourceQuotaEstimate(
                    id: key,
                    windowLabel: metric?.label ?? key,
                    usedPercent: use?.usedPercent?.value,
                    estimatedValueUSD: metric?.value?.value,
                    resetDescription: use?.resetDescription
                )
                try ClaudeRadarValidator.validateStatus(estimate)
                return estimate
            }
            guard !estimates.isEmpty else {
                throw ClaudeRadarValidator.validation("Source quota estimate set is empty")
            }
            return .success(SourceStatusDataset(
                sourceID: .claudeCodeRadar,
                sourceUpdatedAt: parseDate(quota.updatedAt),
                fetchedAt: fetchedAt,
                quotaEstimates: estimates
            ))
        } catch let error as SegmentError {
            return .failure(error)
        } catch {
            return .failure(ClaudeRadarValidator.validation("Source status projection failed validation"))
        }
    }

    private func validateAlignment(_ model: ClaudeRadarDTO.Model, labelCount: Int) throws {
        let counts = [model.iq?.count, model.passed?.count, model.valid?.count, model.invalid?.count, model.cost?.count, model.time?.count, model.cache?.count]
        if counts.compactMap({ $0 }).contains(where: { $0 != labelCount }) {
            throw ClaudeRadarValidator.validation("Benchmark series are not aligned with labels")
        }
    }

    private func element<Value>(_ values: [Value?]?, at index: Int?) -> Value? {
        guard let values, let index, values.indices.contains(index) else { return nil }
        return values[index]
    }

    private func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }
}
