import Foundation
import SwiftData

extension RadarRepository: RadarExportDataSource {
    func beginExportSnapshot(includesRawSamples: Bool) async throws -> ExportSnapshotToken {
        try await beginExportSnapshot()
    }

    func exportRecordCount(dataset: ExportDataset, range: ExportDateRange, snapshot: ExportSnapshotToken) async throws -> Int {
        let context = try exportContext(for: snapshot)
        let range = range.limited(to: snapshot.cutoff)
        switch dataset {
        case .models, .benchmarkRuns:
            return try context.fetchCount(benchmarkDescriptor(range: range))
        case .communityRatings:
            return try context.fetchCount(communityDescriptor(range: range))
        case .sourceStatus:
            return try context.fetchCount(sourceStatusDescriptor(range: range))
        case .rawSamples:
            return 0
        }
    }

    func exportRecords(dataset: ExportDataset, range: ExportDateRange, offset: Int, limit: Int, snapshot: ExportSnapshotToken) async throws -> [ExportRecord] {
        guard offset >= 0, limit > 0 else { return [] }
        let context = try exportContext(for: snapshot)
        let range = range.limited(to: snapshot.cutoff)
        switch dataset {
        case .models:
            var descriptor = benchmarkDescriptor(range: range)
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = limit
            return try context.fetch(descriptor).map(modelRecord)
        case .benchmarkRuns:
            var descriptor = benchmarkDescriptor(range: range)
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = limit
            return try context.fetch(descriptor).map(benchmarkRecord)
        case .communityRatings:
            var descriptor = communityDescriptor(range: range)
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = limit
            return try context.fetch(descriptor).map(communityRecord)
        case .sourceStatus:
            var descriptor = sourceStatusDescriptor(range: range)
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = limit
            return try context.fetch(descriptor).map(sourceStatusRecord)
        case .rawSamples:
            return []
        }
    }

    private func benchmarkDescriptor(range: ExportDateRange) -> FetchDescriptor<BenchmarkSnapshotEntity> {
        let predicate: Predicate<BenchmarkSnapshotEntity>? = datePredicate(range)
        return FetchDescriptor(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\BenchmarkSnapshotEntity.chronologyAt, order: .forward),
                SortDescriptor(\BenchmarkSnapshotEntity.contentFingerprint, order: .forward),
            ]
        )
    }

    private func communityDescriptor(range: ExportDateRange) -> FetchDescriptor<CommunitySnapshotEntity> {
        let predicate: Predicate<CommunitySnapshotEntity>? = datePredicate(range)
        return FetchDescriptor(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\CommunitySnapshotEntity.chronologyAt, order: .forward),
                SortDescriptor(\CommunitySnapshotEntity.contentFingerprint, order: .forward),
            ]
        )
    }

    private func sourceStatusDescriptor(range: ExportDateRange) -> FetchDescriptor<SourceStatusSnapshotEntity> {
        let predicate: Predicate<SourceStatusSnapshotEntity>? = datePredicate(range)
        return FetchDescriptor(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\SourceStatusSnapshotEntity.chronologyAt, order: .forward),
                SortDescriptor(\SourceStatusSnapshotEntity.contentFingerprint, order: .forward),
            ]
        )
    }

    private func datePredicate(_ range: ExportDateRange) -> Predicate<BenchmarkSnapshotEntity>? {
        switch (range.start, range.end) {
        case let (start?, end?): return #Predicate { $0.fetchedAt >= start && $0.fetchedAt <= end }
        case let (start?, nil): return #Predicate { $0.fetchedAt >= start }
        case let (nil, end?): return #Predicate { $0.fetchedAt <= end }
        case (nil, nil): return nil
        }
    }

    private func datePredicate(_ range: ExportDateRange) -> Predicate<CommunitySnapshotEntity>? {
        switch (range.start, range.end) {
        case let (start?, end?): return #Predicate { $0.fetchedAt >= start && $0.fetchedAt <= end }
        case let (start?, nil): return #Predicate { $0.fetchedAt >= start }
        case let (nil, end?): return #Predicate { $0.fetchedAt <= end }
        case (nil, nil): return nil
        }
    }

    private func datePredicate(_ range: ExportDateRange) -> Predicate<SourceStatusSnapshotEntity>? {
        switch (range.start, range.end) {
        case let (start?, end?): return #Predicate { $0.fetchedAt >= start && $0.fetchedAt <= end }
        case let (start?, nil): return #Predicate { $0.fetchedAt >= start }
        case let (nil, end?): return #Predicate { $0.fetchedAt <= end }
        case (nil, nil): return nil
        }
    }

    private func modelRecord(_ entity: BenchmarkSnapshotEntity) throws -> ExportRecord {
        let dataset = try verifiedBenchmark(entity)
        return ExportRecord(fields: baseFields(entity).merging([
            "models": .array(dataset.models.map { model in
                .object([
                    "id": .string(model.id.upstreamKey),
                    "sourceID": .string(model.id.sourceID.rawValue),
                    "upstreamName": .string(model.descriptor.upstreamName),
                    "displayName": .string(model.descriptor.displayName),
                ])
            }),
        ]) { _, new in new })
    }

    private func benchmarkRecord(_ entity: BenchmarkSnapshotEntity) throws -> ExportRecord {
        let dataset = try verifiedBenchmark(entity)
        return ExportRecord(fields: baseFields(entity).merging([
            "benchmarkName": text(dataset.benchmarkName),
            "benchmarkVersion": text(dataset.benchmarkVersion),
            "runs": .array(dataset.models.map(benchmarkValue)),
        ]) { _, new in new })
    }

    private func communityRecord(_ entity: CommunitySnapshotEntity) throws -> ExportRecord {
        let dataset = try verifiedCommunity(entity)
        return ExportRecord(fields: baseFields(entity).merging([
            "ratings": .array(dataset.ratings.map { rating in
                .object([
                    "id": .string(rating.id.upstreamKey),
                    "average": decimal(rating.average),
                    "voteCount": integer(rating.voteCount),
                    "scaleMinimum": decimal(rating.scaleMinimum),
                    "scaleMaximum": decimal(rating.scaleMaximum),
                ])
            }),
        ]) { _, new in new })
    }

    private func sourceStatusRecord(_ entity: SourceStatusSnapshotEntity) throws -> ExportRecord {
        let dataset = try verifiedSourceStatus(entity)
        return ExportRecord(fields: baseFields(entity).merging([
            "quotaEstimates": .array(dataset.quotaEstimates.map { estimate in
                .object([
                    "id": .string(estimate.id),
                    "windowLabel": .string(estimate.windowLabel),
                    "usedPercent": decimal(estimate.usedPercent),
                    "estimatedValueUSD": decimal(estimate.estimatedValueUSD),
                    "resetDescription": text(estimate.resetDescription),
                ])
            }),
        ]) { _, new in new })
    }

    private func baseFields(_ entity: BenchmarkSnapshotEntity) -> [String: ExportJSONValue] {
        baseFields(id: entity.contentFingerprint, sourceID: entity.sourceID, sourceUpdatedAt: entity.sourceUpdatedAt, fetchedAt: entity.fetchedAt, revision: entity.seriesRevision)
    }

    private func baseFields(_ entity: CommunitySnapshotEntity) -> [String: ExportJSONValue] {
        baseFields(id: entity.contentFingerprint, sourceID: entity.sourceID, sourceUpdatedAt: entity.sourceUpdatedAt, fetchedAt: entity.fetchedAt, revision: entity.seriesRevision)
    }

    private func baseFields(_ entity: SourceStatusSnapshotEntity) -> [String: ExportJSONValue] {
        baseFields(id: entity.contentFingerprint, sourceID: entity.sourceID, sourceUpdatedAt: entity.sourceUpdatedAt, fetchedAt: entity.fetchedAt, revision: entity.seriesRevision)
    }

    private func baseFields(id: String, sourceID: String, sourceUpdatedAt: Date?, fetchedAt: Date, revision: String) -> [String: ExportJSONValue] {
        [
            "id": .string(id),
            "sourceID": .string(sourceID),
            "sourceUpdatedAt": date(sourceUpdatedAt),
            "fetchedAt": date(fetchedAt),
            "seriesRevision": .string(revision),
        ]
    }

    private func benchmarkValue(_ model: ModelBenchmark) -> ExportJSONValue {
        .object([
            "id": .string(model.id.upstreamKey),
            "qualityScore": decimal(model.qualityScore),
            "passedTasks": integer(model.passedTasks),
            "validTasks": integer(model.validTasks),
            "invalidTasks": integer(model.invalidTasks),
            "benchmarkCostUSD": decimal(model.benchmarkCostUSD),
            "inputTokens": integer(model.inputTokens),
            "outputTokens": integer(model.outputTokens),
            "cacheReadTokens": integer(model.cacheReadTokens),
            "cacheCreationTokens": integer(model.cacheCreationTokens),
            "totalTokens": integer(model.totalTokens),
            "elapsedSeconds": model.elapsedSeconds.map(ExportJSONValue.double) ?? .null,
            "agentSteps": integer(model.agentSteps),
            "cacheHitPercent": decimal(model.cacheHitPercent),
        ])
    }

    private func decimal(_ value: Decimal?) -> ExportJSONValue {
        value.map { .string(NSDecimalNumber(decimal: $0).stringValue) } ?? .null
    }

    private func integer<T: BinaryInteger>(_ value: T?) -> ExportJSONValue {
        value.flatMap { Int64(exactly: $0) }.map(ExportJSONValue.int) ?? .null
    }

    private func text(_ value: String?) -> ExportJSONValue { value.map(ExportJSONValue.string) ?? .null }

    private func date(_ value: Date?) -> ExportJSONValue {
        guard let value else { return .null }
        return .string(ISO8601DateFormatter().string(from: value))
    }
}

actor RadarExportSource: RadarExportDataSource {
    private let repository: RadarRepository
    private let rawSampleStore: any RawSamplePayloadSource
    private let sourceID: RadarSourceID
    private var rawSnapshots: [UUID: [RawSamplePayload]] = [:]

    init(repository: RadarRepository, rawSampleStore: any RawSamplePayloadSource, sourceID: RadarSourceID = .claudeCodeRadar) {
        self.repository = repository
        self.rawSampleStore = rawSampleStore
        self.sourceID = sourceID
    }

    func beginExportSnapshot(includesRawSamples: Bool) async throws -> ExportSnapshotToken {
        let rawPayloads = includesRawSamples ? try await rawSampleStore.exportPayloads(sourceID: sourceID) : []
        let token = try await repository.beginExportSnapshot()
        rawSnapshots[token.id] = rawPayloads
        return token
    }

    func endExportSnapshot(_ snapshot: ExportSnapshotToken) async {
        rawSnapshots.removeValue(forKey: snapshot.id)
        await repository.endExportSnapshot(snapshot)
    }

    func exportRecordCount(dataset: ExportDataset, range: ExportDateRange, snapshot: ExportSnapshotToken) async throws -> Int {
        if dataset != .rawSamples { return try await repository.exportRecordCount(dataset: dataset, range: range, snapshot: snapshot) }
        guard let payloads = rawSnapshots[snapshot.id] else { throw ExportError.repositoryUnavailable }
        return payloads.count { range.limited(to: snapshot.cutoff).contains($0.capturedAt) }
    }

    func exportRecords(dataset: ExportDataset, range: ExportDateRange, offset: Int, limit: Int, snapshot: ExportSnapshotToken) async throws -> [ExportRecord] {
        if dataset != .rawSamples {
            return try await repository.exportRecords(dataset: dataset, range: range, offset: offset, limit: limit, snapshot: snapshot)
        }
        guard let payloads = rawSnapshots[snapshot.id] else { throw ExportError.repositoryUnavailable }
        return payloads
            .filter { range.limited(to: snapshot.cutoff).contains($0.capturedAt) }
            .sorted { left, right in
                if left.capturedAt != right.capturedAt { return left.capturedAt < right.capturedAt }
                return left.id < right.id
            }
            .dropFirst(offset)
            .prefix(limit)
            .map { sample in
                ExportRecord(fields: [
                    "id": .string(sample.id),
                    "sourceID": .string(sourceID.rawValue),
                    "fetchedAt": .string(ISO8601DateFormatter().string(from: sample.capturedAt)),
                    "outcome": .string(sample.outcome.rawValue),
                    "body": .string(String(decoding: sample.data, as: UTF8.self)),
                ])
            }
    }
}

private extension ExportDateRange {
    func limited(to cutoff: Date) -> ExportDateRange {
        ExportDateRange(start: start, end: min(end ?? cutoff, cutoff))
    }
}
