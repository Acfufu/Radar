import Foundation
import SwiftData

struct SnapshotInsertion: Equatable, Sendable {
    let inserted: Bool
    let contentFingerprint: String
}

actor RadarRepository {
    let container: ModelContainer
    private let metadataStore: SyncMetadataStore
    private let deletionLeaseCheckpoint: (@Sendable () async -> Void)?
    private let leaseWaiterDidSuspend: (@Sendable () -> Void)?
    private var activeExportSnapshot: ActiveExportSnapshot?
    private var deletionLeaseReservations: [UUID] = []
    private var exportLeaseWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]

    init(
        container: ModelContainer,
        metadataStore: SyncMetadataStore,
        deletionLeaseCheckpoint: (@Sendable () async -> Void)? = nil,
        leaseWaiterDidSuspend: (@Sendable () -> Void)? = nil
    ) {
        self.container = container
        self.metadataStore = metadataStore
        self.deletionLeaseCheckpoint = deletionLeaseCheckpoint
        self.leaseWaiterDidSuspend = leaseWaiterDidSuspend
        Self.repairChronology(in: container)
    }

    func insertBenchmark(_ dataset: BenchmarkDataset) async throws -> SnapshotInsertion {
        try await waitForExportLease()
        let fingerprint = try ContentFingerprint.benchmark(dataset)
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<BenchmarkSnapshotEntity>()).contains {
            $0.sourceID == dataset.sourceID.rawValue && $0.contentFingerprint == fingerprint
        }
        if !existing {
            let encoded = try JSONEncoder.radar.encode(dataset)
            context.insert(BenchmarkSnapshotEntity(dataset: dataset, fingerprint: fingerprint, encodedDataset: encoded))
            try context.save()
        }
        try await metadataStore.update(sourceID: dataset.sourceID, datasetType: .benchmark) {
            $0.lastAttemptedAt = dataset.fetchedAt
            $0.lastSuccessfulAt = dataset.fetchedAt
            $0.lastError = nil
            $0.retryAfter = nil
            $0.backoffUntil = nil
            $0.consecutiveFailures = 0
        }
        return SnapshotInsertion(inserted: !existing, contentFingerprint: fingerprint)
    }

    func insertCommunity(
        _ dataset: CommunityDataset,
        seriesRevision: String = ClaudeRadarConfiguration.seriesRevision
    ) async throws -> SnapshotInsertion {
        try await waitForExportLease()
        let fingerprint = try ContentFingerprint.community(dataset, seriesRevision: seriesRevision)
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<CommunitySnapshotEntity>()).contains {
            $0.sourceID == dataset.sourceID.rawValue && $0.contentFingerprint == fingerprint
        }
        if !existing {
            context.insert(CommunitySnapshotEntity(
                dataset: dataset,
                seriesRevision: seriesRevision,
                fingerprint: fingerprint,
                encodedDataset: try JSONEncoder.radar.encode(dataset)
            ))
            try context.save()
        }
        try await recordSuccess(sourceID: dataset.sourceID, datasetType: .community, at: dataset.fetchedAt)
        return SnapshotInsertion(inserted: !existing, contentFingerprint: fingerprint)
    }

    func insertSourceStatus(
        _ dataset: SourceStatusDataset,
        seriesRevision: String = ClaudeRadarConfiguration.seriesRevision
    ) async throws -> SnapshotInsertion {
        try await waitForExportLease()
        let fingerprint = try ContentFingerprint.sourceStatus(dataset, seriesRevision: seriesRevision)
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<SourceStatusSnapshotEntity>()).contains {
            $0.sourceID == dataset.sourceID.rawValue && $0.contentFingerprint == fingerprint
        }
        if !existing {
            context.insert(SourceStatusSnapshotEntity(
                dataset: dataset,
                seriesRevision: seriesRevision,
                fingerprint: fingerprint,
                encodedDataset: try JSONEncoder.radar.encode(dataset)
            ))
            try context.save()
        }
        try await recordSuccess(sourceID: dataset.sourceID, datasetType: .sourceStatus, at: dataset.fetchedAt)
        return SnapshotInsertion(inserted: !existing, contentFingerprint: fingerprint)
    }

    func insertStationStatus(_ dataset: CodexStationStatusDataset) async throws -> SnapshotInsertion {
        try await waitForExportLease()
        let fingerprint = try ContentFingerprint.stationStatus(dataset)
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<CodexRadarStatusSnapshotEntity>()).contains {
            $0.sourceID == dataset.sourceID.rawValue && $0.contentFingerprint == fingerprint
        }
        if !existing {
            context.insert(CodexRadarStatusSnapshotEntity(
                dataset: dataset,
                fingerprint: fingerprint,
                encodedDataset: try JSONEncoder.radar.encode(dataset)
            ))
            try context.save()
        }
        return SnapshotInsertion(inserted: !existing, contentFingerprint: fingerprint)
    }

    func latestStationStatus(sourceID: RadarSourceID) async throws -> CodexStationStatusDataset? {
        let context = ModelContext(container)
        let entities = try context.fetch(
            FetchDescriptor<CodexRadarStatusSnapshotEntity>(
                sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
            )
        )
        guard let entity = entities.first(where: { $0.sourceID == sourceID.rawValue }) else { return nil }
        return try JSONDecoder.radar.decode(CodexStationStatusDataset.self, from: entity.encodedDataset)
    }

    func insertRenderedWarning(_ snapshot: CodexRenderedWarningSnapshot) async throws -> SnapshotInsertion {
        try await waitForExportLease()
        let fingerprint = try ContentFingerprint.renderedWarning(snapshot)
        guard fingerprint == snapshot.semanticFingerprint else {
            throw RepositoryIntegrityError.mismatchedSnapshot
        }
        let encodedSnapshot = try JSONEncoder.radar.encode(snapshot)
        let persistedSnapshot = try JSONDecoder.radar.decode(
            CodexRenderedWarningSnapshot.self,
            from: encodedSnapshot
        )
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<CodexRenderedWarningSnapshotEntity>()).contains {
            $0.sourceID == snapshot.sourceID.rawValue && $0.contentFingerprint == fingerprint
        }
        if !existing {
            context.insert(CodexRenderedWarningSnapshotEntity(
                snapshot: persistedSnapshot,
                fingerprint: fingerprint,
                encodedSnapshot: encodedSnapshot
            ))
            context.processPendingChanges()
            try pruneRenderedWarnings(
                sourceID: snapshot.sourceID,
                parserRevision: snapshot.parserRevision,
                context: context
            )
            try context.save()
        }
        try await recordSuccess(
            sourceID: snapshot.sourceID,
            datasetType: .renderedWarnings,
            at: persistedSnapshot.capturedAt
        )
        return SnapshotInsertion(inserted: !existing, contentFingerprint: fingerprint)
    }

    func insertRenderedIQHistory(
        _ snapshot: CodexRenderedIQHistorySnapshot
    ) async throws -> SnapshotInsertion {
        try await waitForExportLease()
        let fingerprint = try ContentFingerprint.renderedIQHistory(snapshot)
        guard fingerprint == snapshot.semanticFingerprint else {
            throw RepositoryIntegrityError.mismatchedSnapshot
        }
        let encodedSnapshot = try JSONEncoder.radar.encode(snapshot)
        let persistedSnapshot = try JSONDecoder.radar.decode(
            CodexRenderedIQHistorySnapshot.self,
            from: encodedSnapshot
        )
        let context = ModelContext(container)
        let existing = try context.fetch(FetchDescriptor<CodexRenderedIQHistorySnapshotEntity>()).contains {
            $0.sourceID == snapshot.sourceID.rawValue && $0.contentFingerprint == fingerprint
        }
        if !existing {
            context.insert(CodexRenderedIQHistorySnapshotEntity(
                snapshot: persistedSnapshot,
                fingerprint: fingerprint,
                encodedSnapshot: encodedSnapshot
            ))
            context.processPendingChanges()
            try pruneRenderedIQHistory(
                sourceID: snapshot.sourceID,
                parserRevision: snapshot.parserRevision,
                context: context
            )
            try context.save()
        }
        try await recordSuccess(
            sourceID: snapshot.sourceID,
            datasetType: .renderedIQHistory,
            at: persistedSnapshot.capturedAt
        )
        return SnapshotInsertion(inserted: !existing, contentFingerprint: fingerprint)
    }

    func benchmarkState(sourceID: RadarSourceID) async throws -> SegmentState<BenchmarkDataset> {
        let context = ModelContext(container)
        let snapshots = try context.fetch(FetchDescriptor<BenchmarkSnapshotEntity>())
            .filter { $0.sourceID == sourceID.rawValue }
            .sorted { $0.fetchedAt > $1.fetchedAt }
        var decodingFailure: SegmentError?
        var value: BenchmarkDataset?
        for snapshot in snapshots {
            do {
                let candidate = try verifiedBenchmark(snapshot)
                guard candidate.sourceID == sourceID else { throw RepositoryIntegrityError.mismatchedSnapshot }
                value = candidate
                break
            } catch {
                decodingFailure = SegmentError(kind: .decoding, message: "A stored benchmark snapshot could not be decoded")
            }
        }
        let metadata = try await metadataStore.metadata(sourceID: sourceID, datasetType: .benchmark)
        let metadataFailure = try await metadataStore.corruptionError()
        return SegmentState(
            value: value,
            lastSuccessfulAt: metadata.lastSuccessfulAt ?? value?.fetchedAt,
            lastAttemptedAt: metadata.lastAttemptedAt,
            error: decodingFailure
                ?? metadataFailure.map { SegmentError(kind: $0.kind, message: $0.message) }
                ?? metadata.lastError.map { SegmentError(kind: $0.kind, message: $0.message) },
            isStale: false
        )
    }

    func communityState(sourceID: RadarSourceID) async throws -> SegmentState<CommunityDataset> {
        let context = ModelContext(container)
        let snapshots = try context.fetch(FetchDescriptor<CommunitySnapshotEntity>())
            .filter { $0.sourceID == sourceID.rawValue }
            .sorted { $0.fetchedAt > $1.fetchedAt }
        let result: (CommunityDataset?, SegmentError?) = decodeNewest(snapshots) { snapshot in
            let candidate = try verifiedCommunity(snapshot)
            guard candidate.sourceID == sourceID else { throw RepositoryIntegrityError.mismatchedSnapshot }
            return candidate
        }
        return try await state(
            value: result.0,
            successfulAt: result.0?.fetchedAt,
            decodingFailure: result.1,
            sourceID: sourceID,
            datasetType: .community
        )
    }

    func sourceStatusState(sourceID: RadarSourceID) async throws -> SegmentState<SourceStatusDataset> {
        let context = ModelContext(container)
        let snapshots = try context.fetch(FetchDescriptor<SourceStatusSnapshotEntity>())
            .filter { $0.sourceID == sourceID.rawValue }
            .sorted { $0.fetchedAt > $1.fetchedAt }
        let result: (SourceStatusDataset?, SegmentError?) = decodeNewest(snapshots) { snapshot in
            let candidate = try verifiedSourceStatus(snapshot)
            guard candidate.sourceID == sourceID else { throw RepositoryIntegrityError.mismatchedSnapshot }
            return candidate
        }
        return try await state(
            value: result.0,
            successfulAt: result.0?.fetchedAt,
            decodingFailure: result.1,
            sourceID: sourceID,
            datasetType: .sourceStatus
        )
    }

    func renderedWarningState(sourceID: RadarSourceID) async throws -> SegmentState<CodexRenderedWarningSnapshot> {
        let context = ModelContext(container)
        let snapshots = try context.fetch(FetchDescriptor<CodexRenderedWarningSnapshotEntity>())
            .filter { $0.sourceID == sourceID.rawValue }
            .sorted {
                if $0.chronologyAt != $1.chronologyAt { return $0.chronologyAt > $1.chronologyAt }
                return $0.contentFingerprint > $1.contentFingerprint
            }
        let result: (CodexRenderedWarningSnapshot?, SegmentError?) = decodeNewest(snapshots) { snapshot in
            let candidate = try verifiedRenderedWarning(snapshot)
            guard candidate.sourceID == sourceID else { throw RepositoryIntegrityError.mismatchedSnapshot }
            return candidate
        }
        return try await state(
            value: result.0,
            successfulAt: result.0?.capturedAt,
            decodingFailure: result.1,
            sourceID: sourceID,
            datasetType: .renderedWarnings
        )
    }

    func renderedIQHistoryState(
        sourceID: RadarSourceID
    ) async throws -> SegmentState<CodexRenderedIQHistorySnapshot> {
        let context = ModelContext(container)
        let snapshots = try context.fetch(FetchDescriptor<CodexRenderedIQHistorySnapshotEntity>())
            .filter { $0.sourceID == sourceID.rawValue }
            .sorted {
                if $0.chronologyAt != $1.chronologyAt { return $0.chronologyAt > $1.chronologyAt }
                return $0.contentFingerprint > $1.contentFingerprint
            }
        let result: (CodexRenderedIQHistorySnapshot?, SegmentError?) = decodeNewest(snapshots) { snapshot in
            let candidate = try verifiedRenderedIQHistory(snapshot)
            guard candidate.sourceID == sourceID else { throw RepositoryIntegrityError.mismatchedSnapshot }
            return candidate
        }
        return try await state(
            value: result.0,
            successfulAt: result.0?.capturedAt,
            decodingFailure: result.1,
            sourceID: sourceID,
            datasetType: .renderedIQHistory
        )
    }

    func snapshotCount(datasetType: RadarDatasetType, sourceID: RadarSourceID) throws -> Int {
        let context = ModelContext(container)
        switch datasetType {
        case .benchmark:
            return try context.fetch(FetchDescriptor<BenchmarkSnapshotEntity>()).count { $0.sourceID == sourceID.rawValue }
        case .community:
            return try context.fetch(FetchDescriptor<CommunitySnapshotEntity>()).count { $0.sourceID == sourceID.rawValue }
        case .sourceStatus:
            return try context.fetch(FetchDescriptor<SourceStatusSnapshotEntity>()).count { $0.sourceID == sourceID.rawValue }
        case .renderedWarnings:
            return try context.fetch(FetchDescriptor<CodexRenderedWarningSnapshotEntity>()).count { $0.sourceID == sourceID.rawValue }
        case .renderedIQHistory:
            return try context.fetch(FetchDescriptor<CodexRenderedIQHistorySnapshotEntity>()).count { $0.sourceID == sourceID.rawValue }
        }
    }

    func benchmarkHistory(sourceID: RadarSourceID) throws -> [BenchmarkDataset] {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<BenchmarkSnapshotEntity>())
            .filter { $0.sourceID == sourceID.rawValue }
            .compactMap { try? verifiedBenchmark($0) }
            .sorted {
                let left = $0.sourceUpdatedAt ?? $0.fetchedAt
                let right = $1.sourceUpdatedAt ?? $1.fetchedAt
                if left != right { return left < right }
                return $0.seriesRevision < $1.seriesRevision
            }
    }

    func renderedWarningHistory(sourceID: RadarSourceID) throws -> [CodexRenderedWarningSnapshot] {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<CodexRenderedWarningSnapshotEntity>())
            .filter { $0.sourceID == sourceID.rawValue }
            .compactMap { try? verifiedRenderedWarning($0) }
            .sorted {
                if $0.capturedAt != $1.capturedAt { return $0.capturedAt < $1.capturedAt }
                return $0.semanticFingerprint < $1.semanticFingerprint
            }
    }

    func renderedIQHistoryHistory(sourceID: RadarSourceID) throws -> [CodexRenderedIQHistorySnapshot] {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<CodexRenderedIQHistorySnapshotEntity>())
            .filter { $0.sourceID == sourceID.rawValue }
            .compactMap { try? verifiedRenderedIQHistory($0) }
            .sorted {
                if $0.capturedAt != $1.capturedAt { return $0.capturedAt < $1.capturedAt }
                return $0.semanticFingerprint < $1.semanticFingerprint
            }
    }

    func metadata(sourceID: RadarSourceID, datasetType: RadarDatasetType) async throws -> SyncMetadata {
        try await metadataStore.metadata(sourceID: sourceID, datasetType: datasetType)
    }

    func recordFailure(
        sourceID: RadarSourceID,
        datasetType: RadarDatasetType,
        attemptedAt: Date,
        error: SegmentError,
        retryAfter: Date? = nil
    ) async throws {
        try await metadataStore.update(sourceID: sourceID, datasetType: datasetType) {
            $0.lastAttemptedAt = attemptedAt
            $0.lastError = SyncErrorMetadata(error)
            $0.retryAfter = retryAfter
            $0.consecutiveFailures = ($0.consecutiveFailures ?? 0) + 1
        }
    }

    func recordNotModified(
        sourceID: RadarSourceID,
        datasetType: RadarDatasetType,
        attemptedAt: Date,
        etag: String?,
        lastModified: String?
    ) async throws {
        try await metadataStore.update(sourceID: sourceID, datasetType: datasetType) {
            $0.lastAttemptedAt = attemptedAt
            $0.lastSuccessfulAt = attemptedAt
            $0.lastError = nil
            $0.etag = etag ?? $0.etag
            $0.lastModified = lastModified ?? $0.lastModified
            $0.retryAfter = nil
            $0.backoffUntil = nil
            $0.consecutiveFailures = 0
        }
    }

    func recordValidators(
        sourceID: RadarSourceID,
        datasetType: RadarDatasetType,
        validators: HTTPValidators
    ) async throws {
        try await metadataStore.update(sourceID: sourceID, datasetType: datasetType) {
            $0.etag = validators.etag
            $0.lastModified = validators.lastModified
            $0.retryAfter = nil
        }
    }

    func recordBackoff(
        sourceID: RadarSourceID,
        datasetType: RadarDatasetType,
        until: Date?,
        failureCount: Int
    ) async throws {
        try await metadataStore.update(sourceID: sourceID, datasetType: datasetType) {
            $0.backoffUntil = until
            $0.consecutiveFailures = failureCount
        }
    }

    func deleteNormalizedHistory(sourceID: RadarSourceID) async throws {
        let leaseID = UUID()
        deletionLeaseReservations.append(leaseID)
        defer { releaseDeletionLease(leaseID) }
        try await waitForDeletionLease(leaseID)
        await deletionLeaseCheckpoint?()
        try await metadataStore.delete(sourceID: sourceID)

        // ponytail: metadata and SwiftData are not transactional; metadata-first preserves normalized rows on a later save failure. Add a journal only if cross-store atomicity becomes required.
        let context = ModelContext(container)
        for entity in try context.fetch(FetchDescriptor<BenchmarkSnapshotEntity>()) where entity.sourceID == sourceID.rawValue {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<CommunitySnapshotEntity>()) where entity.sourceID == sourceID.rawValue {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<SourceStatusSnapshotEntity>()) where entity.sourceID == sourceID.rawValue {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<CodexRenderedWarningSnapshotEntity>()) where entity.sourceID == sourceID.rawValue {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<CodexRenderedIQHistorySnapshotEntity>()) where entity.sourceID == sourceID.rawValue {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<CodexRadarStatusSnapshotEntity>()) where entity.sourceID == sourceID.rawValue {
            context.delete(entity)
        }
        try context.save()
    }

    private func recordSuccess(sourceID: RadarSourceID, datasetType: RadarDatasetType, at date: Date) async throws {
        try await metadataStore.update(sourceID: sourceID, datasetType: datasetType) {
            $0.lastAttemptedAt = date
            $0.lastSuccessfulAt = date
            $0.lastError = nil
            $0.retryAfter = nil
            $0.backoffUntil = nil
            $0.consecutiveFailures = 0
        }
    }

    func beginExportSnapshot() async throws -> ExportSnapshotToken {
        try await waitForExportLease()
        let token = ExportSnapshotToken(id: UUID(), cutoff: Date())
        activeExportSnapshot = ActiveExportSnapshot(token: token, context: ModelContext(container))
        return token
    }

    func endExportSnapshot(_ token: ExportSnapshotToken) {
        guard activeExportSnapshot?.token == token else { return }
        activeExportSnapshot = nil
        resumeLeaseWaiters()
    }

    private func releaseDeletionLease(_ id: UUID) {
        deletionLeaseReservations.removeAll { $0 == id }
        resumeLeaseWaiters()
    }

    private func resumeLeaseWaiters() {
        let waiters = exportLeaseWaiters.values
        exportLeaseWaiters.removeAll()
        waiters.forEach { $0.resume(returning: ()) }
    }

    func exportContext(for token: ExportSnapshotToken) throws -> ModelContext {
        guard let activeExportSnapshot, activeExportSnapshot.token == token else {
            throw ExportError.repositoryUnavailable
        }
        return activeExportSnapshot.context
    }

    func verifiedBenchmark(_ snapshot: BenchmarkSnapshotEntity) throws -> BenchmarkDataset {
        let candidate = try JSONDecoder.radar.decode(BenchmarkDataset.self, from: snapshot.encodedDataset)
        guard candidate.sourceID.rawValue == snapshot.sourceID,
              candidate.seriesRevision == snapshot.seriesRevision,
              candidate.sourceUpdatedAt == snapshot.sourceUpdatedAt,
              try ContentFingerprint.benchmark(candidate) == snapshot.contentFingerprint else {
            throw RepositoryIntegrityError.mismatchedSnapshot
        }
        return candidate
    }

    func verifiedCommunity(_ snapshot: CommunitySnapshotEntity) throws -> CommunityDataset {
        let candidate = try JSONDecoder.radar.decode(CommunityDataset.self, from: snapshot.encodedDataset)
        guard candidate.sourceID.rawValue == snapshot.sourceID,
              candidate.sourceUpdatedAt == snapshot.sourceUpdatedAt,
              try ContentFingerprint.community(candidate, seriesRevision: snapshot.seriesRevision) == snapshot.contentFingerprint else {
            throw RepositoryIntegrityError.mismatchedSnapshot
        }
        return candidate
    }

    func verifiedSourceStatus(_ snapshot: SourceStatusSnapshotEntity) throws -> SourceStatusDataset {
        let candidate = try JSONDecoder.radar.decode(SourceStatusDataset.self, from: snapshot.encodedDataset)
        guard candidate.sourceID.rawValue == snapshot.sourceID,
              candidate.sourceUpdatedAt == snapshot.sourceUpdatedAt,
              try ContentFingerprint.sourceStatus(candidate, seriesRevision: snapshot.seriesRevision) == snapshot.contentFingerprint else {
            throw RepositoryIntegrityError.mismatchedSnapshot
        }
        return candidate
    }

    func verifiedRenderedWarning(
        _ snapshot: CodexRenderedWarningSnapshotEntity
    ) throws -> CodexRenderedWarningSnapshot {
        let candidate = try JSONDecoder.radar.decode(
            CodexRenderedWarningSnapshot.self,
            from: snapshot.encodedSnapshot
        )
        let fingerprint = try ContentFingerprint.renderedWarning(candidate)
        guard candidate.sourceID.rawValue == snapshot.sourceID,
              candidate.parserRevision == snapshot.parserRevision,
              candidate.finalOrigin == snapshot.finalOrigin,
              candidate.sourceTimeLabel == snapshot.sourceTimeLabel,
              candidate.capturedAt == snapshot.capturedAt,
              candidate.capturedAt == snapshot.chronologyAt,
              candidate.semanticFingerprint == snapshot.contentFingerprint,
              fingerprint == snapshot.contentFingerprint else {
            throw RepositoryIntegrityError.mismatchedSnapshot
        }
        return candidate
    }

    func verifiedRenderedIQHistory(
        _ snapshot: CodexRenderedIQHistorySnapshotEntity
    ) throws -> CodexRenderedIQHistorySnapshot {
        let candidate = try JSONDecoder.radar.decode(
            CodexRenderedIQHistorySnapshot.self,
            from: snapshot.encodedSnapshot
        )
        let fingerprint = try ContentFingerprint.renderedIQHistory(candidate)
        guard candidate.sourceID.rawValue == snapshot.sourceID,
              candidate.parserRevision == snapshot.parserRevision,
              candidate.finalOrigin == snapshot.finalOrigin,
              candidate.capturedAt == snapshot.capturedAt,
              candidate.capturedAt == snapshot.chronologyAt,
              candidate.semanticFingerprint == snapshot.contentFingerprint,
              fingerprint == snapshot.contentFingerprint else {
            throw RepositoryIntegrityError.mismatchedSnapshot
        }
        return candidate
    }

    private func waitForExportLease() async throws {
        while activeExportSnapshot != nil || !deletionLeaseReservations.isEmpty {
            try await suspendForLease()
        }
        try Task.checkCancellation()
    }

    private func waitForDeletionLease(_ id: UUID) async throws {
        while activeExportSnapshot != nil || deletionLeaseReservations.first != id {
            try await suspendForLease()
        }
        try Task.checkCancellation()
    }

    private func suspendForLease() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    exportLeaseWaiters[id] = continuation
                    leaseWaiterDidSuspend?()
                }
            }
        } onCancel: {
            Task { await self.cancelExportLeaseWaiter(id) }
        }
    }

    private func cancelExportLeaseWaiter(_ id: UUID) {
        exportLeaseWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private static func repairChronology(in container: ModelContainer) {
        let context = ModelContext(container)
        do {
            var changed = false
            for entity in try context.fetch(FetchDescriptor<BenchmarkSnapshotEntity>()) {
                let expected = entity.sourceUpdatedAt ?? entity.fetchedAt
                if entity.chronologyAt != expected { entity.chronologyAt = expected; changed = true }
            }
            for entity in try context.fetch(FetchDescriptor<CommunitySnapshotEntity>()) {
                let expected = entity.sourceUpdatedAt ?? entity.fetchedAt
                if entity.chronologyAt != expected { entity.chronologyAt = expected; changed = true }
            }
            for entity in try context.fetch(FetchDescriptor<SourceStatusSnapshotEntity>()) {
                let expected = entity.sourceUpdatedAt ?? entity.fetchedAt
                if entity.chronologyAt != expected { entity.chronologyAt = expected; changed = true }
            }
            for entity in try context.fetch(FetchDescriptor<CodexRenderedWarningSnapshotEntity>()) {
                if entity.chronologyAt != entity.capturedAt {
                    entity.chronologyAt = entity.capturedAt
                    changed = true
                }
            }
            for entity in try context.fetch(FetchDescriptor<CodexRenderedIQHistorySnapshotEntity>()) {
                if entity.chronologyAt != entity.capturedAt {
                    entity.chronologyAt = entity.capturedAt
                    changed = true
                }
            }
            if changed { try context.save() }
        } catch {
            context.rollback()
        }
    }

    private func pruneRenderedWarnings(
        sourceID: RadarSourceID,
        parserRevision: String,
        context: ModelContext
    ) throws {
        let entities = try context.fetch(FetchDescriptor<CodexRenderedWarningSnapshotEntity>())
            .filter {
                $0.sourceID == sourceID.rawValue
                    && $0.parserRevision == parserRevision
            }
        var valid: [CodexRenderedWarningSnapshotEntity] = []
        for entity in entities {
            do {
                _ = try verifiedRenderedWarning(entity)
                valid.append(entity)
            } catch {
                context.delete(entity)
            }
        }
        let obsolete = valid.sorted {
            if $0.chronologyAt != $1.chronologyAt { return $0.chronologyAt > $1.chronologyAt }
            return $0.contentFingerprint > $1.contentFingerprint
        }.dropFirst(256)
        obsolete.forEach(context.delete)
    }

    private func pruneRenderedIQHistory(
        sourceID: RadarSourceID,
        parserRevision: String,
        context: ModelContext
    ) throws {
        let entities = try context.fetch(FetchDescriptor<CodexRenderedIQHistorySnapshotEntity>())
            .filter {
                $0.sourceID == sourceID.rawValue
                    && $0.parserRevision == parserRevision
            }
        var valid: [CodexRenderedIQHistorySnapshotEntity] = []
        for entity in entities {
            do {
                _ = try verifiedRenderedIQHistory(entity)
                valid.append(entity)
            } catch {
                context.delete(entity)
            }
        }
        let obsolete = valid.sorted {
            if $0.chronologyAt != $1.chronologyAt { return $0.chronologyAt > $1.chronologyAt }
            return $0.contentFingerprint > $1.contentFingerprint
        }.dropFirst(256)
        obsolete.forEach(context.delete)
    }

    private func decodeNewest<Entity, Value>(
        _ snapshots: [Entity],
        decode: (Entity) throws -> Value
    ) -> (Value?, SegmentError?) {
        var decodingFailure: SegmentError?
        for snapshot in snapshots {
            do {
                return (try decode(snapshot), decodingFailure)
            } catch {
                decodingFailure = SegmentError(kind: .decoding, message: "A stored snapshot could not be decoded")
            }
        }
        return (nil, decodingFailure)
    }

    private func state<Value: Sendable>(
        value: Value?,
        successfulAt: Date?,
        decodingFailure: SegmentError?,
        sourceID: RadarSourceID,
        datasetType: RadarDatasetType
    ) async throws -> SegmentState<Value> {
        let metadata = try await metadataStore.metadata(sourceID: sourceID, datasetType: datasetType)
        let metadataFailure = try await metadataStore.corruptionError()
        return SegmentState(
            value: value,
            lastSuccessfulAt: metadata.lastSuccessfulAt ?? successfulAt,
            lastAttemptedAt: metadata.lastAttemptedAt,
            error: decodingFailure
                ?? metadataFailure.map { SegmentError(kind: $0.kind, message: $0.message) }
                ?? metadata.lastError.map { SegmentError(kind: $0.kind, message: $0.message) },
            isStale: false
        )
    }
}

private struct ActiveExportSnapshot {
    let token: ExportSnapshotToken
    let context: ModelContext
}
