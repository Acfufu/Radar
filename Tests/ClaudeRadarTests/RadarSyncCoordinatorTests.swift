import Foundation
import SwiftData
import Testing
@testable import ClaudeRadar

@Suite("RadarSyncCoordinatorTests", .serialized)
struct RadarSyncCoordinatorTests {
    @Test("simultaneous refreshes coalesce while community failure preserves healthy benchmark and status")
    func coalescedSegmentedRefresh() async throws {
        // Given
        let fixture = try repositoryFixture()
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [.json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"))],
            communityURL: [.status(url: communityURL, code: 500)],
        ], gatedURL: benchmarkURL)
        let source = ClaudeCodeRadarSource(configuration: configuration, transport: transport)
        let published = ProjectionRecorder()
        let coordinator = RadarSyncCoordinator(
            source: source,
            repository: fixture.repository,
            projectionDidChange: { projection in await published.append(projection) }
        )

        // When
        let first = Task { await coordinator.refresh(trigger: .manual) }
        await transport.waitUntilGatedRequestStarts()
        let second = Task { await coordinator.refresh(trigger: .periodic) }
        await transport.release()
        _ = await (first.value, second.value)
        let state = try await coordinator.projection()

        // Then
        #expect(await transport.requestCount(for: benchmarkURL) == 1)
        #expect(await transport.requestCount(for: communityURL) == 1)
        #expect(state.benchmark.value != nil)
        #expect(state.sourceStatus.value != nil)
        #expect(state.community.value == nil)
        #expect(state.community.error?.kind == .http)
        #expect(await published.count == 1)
        #expect(await published.last?.benchmark.value != nil)
    }

    @Test("manual periodic network and wake entries install one active refresh before policy awaits")
    func trueSimultaneousEntry() async throws {
        // Given
        let fixture = try repositoryFixture()
        let now = Date(timeIntervalSince1970: 20_000)
        let clock = TestRadarClock(now)
        try await fixture.repository.recordBackoff(
            sourceID: .claudeCodeRadar,
            datasetType: .benchmark,
            until: now.addingTimeInterval(3_600),
            failureCount: 1
        )
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: Array(repeating: .json(url: benchmarkURL, body: try fixtureData("claude-radar-valid")), count: 8),
            communityURL: Array(repeating: .json(url: communityURL, body: try fixtureData("claude-radar-community-valid")), count: 8),
        ], gatedURL: benchmarkURL)
        let coordinator = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: transport),
            repository: fixture.repository,
            clock: clock
        )
        let barrier = StartBarrier(target: 20)
        let triggers: [SyncTrigger] = [.manual, .periodic, .networkRecovery, .sleepRecovery]

        // When
        let callers = (0..<20).map { index in
            Task {
                await barrier.arriveAndWait()
                await coordinator.refresh(trigger: triggers[index % triggers.count])
            }
        }
        await barrier.waitUntilFull()
        await barrier.release()
        await transport.waitUntilGatedRequestStarts()
        await Task.yield()
        await transport.release()
        for caller in callers { await caller.value }

        // Then
        #expect(await transport.requestCount(for: benchmarkURL) == 1)
        #expect(await transport.requestCount(for: communityURL) == 1)
    }

    @Test("manual joining after periodic eligibility retries the endpoint skipped by backoff")
    func lateManualJoinRetriesSkippedEndpointGroup() async throws {
        let fixture = try repositoryFixture()
        let now = Date(timeIntervalSince1970: 20_500)
        try await fixture.repository.recordFailure(
            sourceID: .claudeCodeRadar,
            datasetType: .community,
            attemptedAt: now,
            error: SegmentError(kind: .network, message: "community offline")
        )
        try await fixture.repository.recordBackoff(
            sourceID: .claudeCodeRadar,
            datasetType: .community,
            until: now.addingTimeInterval(3_600),
            failureCount: 2
        )
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [
                .json(url: benchmarkURL, body: try fixtureData("claude-radar-valid")),
                .json(url: benchmarkURL, body: try fixtureData("claude-radar-valid")),
            ],
            communityURL: [.json(url: communityURL, body: try fixtureData("claude-radar-community-valid"))],
        ], gatedURL: benchmarkURL)
        let coordinator = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: transport),
            repository: fixture.repository,
            clock: TestRadarClock(now)
        )

        let periodic = Task { await coordinator.refresh(trigger: .periodic) }
        await transport.waitUntilGatedRequestStarts()
        let manual = Task { await coordinator.refresh(trigger: .manual) }
        for _ in 0..<20 { await Task.yield() }
        await transport.release()
        _ = await (periodic.value, manual.value)

        #expect(await transport.requestCount(for: benchmarkURL) == 1)
        #expect(await transport.requestCount(for: communityURL) == 1)
        #expect(try await fixture.repository.snapshotCount(datasetType: .benchmark, sourceID: .claudeCodeRadar) == 1)
        #expect(try await fixture.repository.snapshotCount(datasetType: .sourceStatus, sourceID: .claudeCodeRadar) == 1)
        #expect(try await fixture.repository.snapshotCount(datasetType: .community, sourceID: .claudeCodeRadar) == 1)
        for datasetType in [RadarDatasetType.benchmark, .community, .sourceStatus] {
            let metadata = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: datasetType)
            #expect(metadata.lastError == nil)
            #expect(metadata.backoffUntil == nil)
        }
    }

    @Test("failed new benchmark never overwrites LKG while a newer community segment saves")
    func lastKnownGoodSurvivesPartialFailure() async throws {
        // Given
        let fixture = try repositoryFixture()
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [
                .json(url: benchmarkURL, body: try fixtureData("claude-radar-valid")),
                .json(url: benchmarkURL, body: Data(#"{"ok":true,"labels":[],"iq":{"models":[]},"quota":{"metrics":[{"key":"h5","value":1}],"usage":[{"key":"h5","used_pct":10}]}}"#.utf8)),
            ],
            communityURL: [
                .json(url: communityURL, body: try fixtureData("claude-radar-community-valid")),
                .json(url: communityURL, body: try fixtureData("claude-radar-community-valid")),
            ],
        ])
        let coordinator = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: transport),
            repository: fixture.repository
        )
        _ = await coordinator.refresh(trigger: .manual)

        // When
        _ = await coordinator.refresh(trigger: .manual)
        let state = try await coordinator.projection()

        // Then
        #expect(state.benchmark.value?.models.first?.qualityScore == 60)
        #expect(state.benchmark.error?.kind == .validation)
        #expect(state.community.value != nil)
        #expect(try await fixture.repository.snapshotCount(datasetType: .benchmark, sourceID: .claudeCodeRadar) == 1)
    }

    @Test("quit cancels active acquisition and prevents later work")
    func quitCancellation() async throws {
        // Given
        let fixture = try repositoryFixture()
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [.json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"))],
            communityURL: [.json(url: communityURL, body: try fixtureData("claude-radar-community-valid"))],
        ], gatedURL: benchmarkURL)
        let coordinator = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: transport),
            repository: fixture.repository
        )
        let refresh = Task { await coordinator.refresh(trigger: .startup) }
        await transport.waitUntilGatedRequestStarts()

        // When
        let stopping = Task { await coordinator.stop() }
        await Task.yield()
        await transport.release()
        await stopping.value
        _ = await refresh.value
        _ = await coordinator.refresh(trigger: .manual)

        // Then
        let lifecycle = await coordinator.lifecycleState()
        #expect(lifecycle.isStopped)
        #expect(!lifecycle.hasActiveTask)
        #expect(await transport.requestCount(for: benchmarkURL) == 1)
    }

    @Test("stop is bounded when transport ignores task cancellation and late results cannot persist")
    func boundedStopWithHungTransport() async throws {
        // Given
        let fixture = try repositoryFixture()
        let rawRoot = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let rawStore = RawSampleStore(dataRoot: rawRoot)
        let transport = CancellationIgnoringTransport(
            response: .json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"))
        )
        let coordinator = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: transport, rawSampleStore: rawStore),
            repository: fixture.repository
        )
        let refresh = Task { await coordinator.refresh(trigger: .startup) }
        await transport.waitUntilRequestCount(2)
        let completion = CompletionFlag()

        // When
        let stopping = Task {
            await coordinator.stop()
            await completion.markCompleted()
        }
        try await Task.sleep(for: .milliseconds(100))

        // Then
        #expect(await completion.isCompleted)
        #expect(await transport.cancelAllCount == 1)
        #expect((await coordinator.lifecycleState()).isStopped)
        await transport.releaseAll()
        await stopping.value
        await refresh.value
        await coordinator.refresh(trigger: .manual)
        #expect(await transport.requestCount == 2)
        #expect(try await fixture.repository.snapshotCount(datasetType: .benchmark, sourceID: .claudeCodeRadar) == 0)
        #expect(try await fixture.repository.snapshotCount(datasetType: .community, sourceID: .claudeCodeRadar) == 0)
        #expect(try await fixture.repository.snapshotCount(datasetType: .sourceStatus, sourceID: .claudeCodeRadar) == 0)
        #expect(try await rawStore.samples(sourceID: .claudeCodeRadar).isEmpty)
    }

    @Test("persisted validators survive coordinator restart and 304 refreshes metadata without history")
    func restartValidatorsAndNotModified() async throws {
        // Given
        let fixture = try repositoryFixture()
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [
                .json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"), headers: ["ETag": "\"stable\""]),
                .status(url: benchmarkURL, code: 304, headers: ["ETag": "\"stable\""]),
            ],
        ])
        let noCommunity = ClaudeRadarConfiguration(benchmarkURL: benchmarkURL, communityURL: nil, sourceStatusURL: nil)
        let first = RadarSyncCoordinator(source: ClaudeCodeRadarSource(configuration: noCommunity, transport: transport), repository: fixture.repository)
        _ = await first.refresh(trigger: .manual)
        let restarted = RadarSyncCoordinator(source: ClaudeCodeRadarSource(configuration: noCommunity, transport: transport), repository: fixture.repository)

        // When
        _ = await restarted.refresh(trigger: .manual)
        let metadata = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark)

        // Then
        #expect(await transport.requestCount(for: benchmarkURL) == 2)
        #expect(await transport.lastRequest(for: benchmarkURL)?.value(forHTTPHeaderField: "If-None-Match") == "\"stable\"")
        #expect(metadata.lastError == nil)
        #expect(metadata.lastSuccessfulAt == metadata.lastAttemptedAt)
        #expect(try await fixture.repository.snapshotCount(datasetType: .benchmark, sourceID: .claudeCodeRadar) == 1)
    }

    @Test("manual refresh bypasses elapsed backoff but never Retry After")
    func manualBackoffPolicy() async throws {
        // Given
        let fixture = try repositoryFixture()
        let now = Date(timeIntervalSince1970: 1_000)
        let clock = TestRadarClock(now)
        try await fixture.repository.recordBackoff(sourceID: .claudeCodeRadar, datasetType: .benchmark, until: now.addingTimeInterval(60), failureCount: 1)
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [.json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"))],
        ])
        let noCommunity = ClaudeRadarConfiguration(benchmarkURL: benchmarkURL, communityURL: nil, sourceStatusURL: nil)
        let coordinator = RadarSyncCoordinator(source: ClaudeCodeRadarSource(configuration: noCommunity, transport: transport), repository: fixture.repository, clock: clock)
        await coordinator.refresh(trigger: .periodic)

        // When
        await coordinator.refresh(trigger: .manual)
        try await fixture.repository.recordFailure(sourceID: .claudeCodeRadar, datasetType: .benchmark, attemptedAt: now, error: SegmentError(kind: .http, message: "retry"), retryAfter: now.addingTimeInterval(120))
        await coordinator.refresh(trigger: .manual)

        // Then
        #expect(await transport.requestCount(for: benchmarkURL) == 1)
    }

    @Test("restart hydrates consecutive failures and advances from one minute to five minutes")
    func restartBackoffContinuation() async throws {
        // Given
        let fixture = try repositoryFixture()
        let clock = TestRadarClock(Date(timeIntervalSince1970: 3_000))
        let firstTransport = GatedRoutingTransport(routes: [
            benchmarkURL: [.status(url: benchmarkURL, code: 500)],
            communityURL: [.status(url: communityURL, code: 500)],
        ])
        let first = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: firstTransport),
            repository: fixture.repository,
            clock: clock
        )
        await first.refresh(trigger: .startup)
        let firstMetadata = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark)
        clock.advance(by: 61)
        let secondTransport = GatedRoutingTransport(routes: [
            benchmarkURL: [.status(url: benchmarkURL, code: 500)],
            communityURL: [.status(url: communityURL, code: 500)],
        ])
        let restarted = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: secondTransport),
            repository: fixture.repository,
            clock: clock
        )

        // When
        await restarted.refresh(trigger: .periodic)
        let secondMetadata = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark)

        // Then
        #expect(firstMetadata.consecutiveFailures == 1)
        #expect(firstMetadata.backoffUntil == Date(timeIntervalSince1970: 3_060))
        #expect(secondMetadata.consecutiveFailures == 2)
        #expect(secondMetadata.backoffUntil == Date(timeIntervalSince1970: 3_361))
    }

    @Test("backoff follows the frozen schedule and caps Retry After across restart")
    func fullBackoffAndRetryAfterCap() async throws {
        // Given
        let policy = SyncPolicy()
        #expect((1...8).map { policy.backoff(failureCount: $0) } == [60, 300, 900, 1_800, 7_200, 21_600, 21_600, 21_600])
        let fixture = try repositoryFixture()
        let now = Date(timeIntervalSince1970: 10_000)
        let clock = TestRadarClock(now)
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [
                .status(url: benchmarkURL, code: 429, headers: ["Retry-After": "999999"]),
                .json(url: benchmarkURL, body: try fixtureData("claude-radar-valid")),
            ],
        ])
        let configuration = ClaudeRadarConfiguration(benchmarkURL: benchmarkURL, communityURL: nil, sourceStatusURL: nil)
        let first = RadarSyncCoordinator(source: ClaudeCodeRadarSource(configuration: configuration, transport: transport), repository: fixture.repository, clock: clock)
        await first.refresh(trigger: .manual)
        let metadata = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark)

        // When
        let restarted = RadarSyncCoordinator(source: ClaudeCodeRadarSource(configuration: configuration, transport: transport), repository: fixture.repository, clock: clock)
        await restarted.refresh(trigger: .manual)
        clock.advance(by: 21_601)
        await restarted.refresh(trigger: .manual)

        // Then
        #expect(metadata.retryAfter == now.addingTimeInterval(21_600))
        #expect(await transport.requestCount(for: benchmarkURL) == 2)
    }

    @Test("network recovery waits for the minimum attempt interval")
    func networkRecoveryMinimumInterval() async throws {
        // Given
        let fixture = try repositoryFixture()
        let now = Date(timeIntervalSince1970: 2_000)
        let clock = TestRadarClock(now)
        try await fixture.repository.recordFailure(sourceID: .claudeCodeRadar, datasetType: .benchmark, attemptedAt: now, error: SegmentError(kind: .network, message: "offline"))
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [.json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"))],
        ])
        let noCommunity = ClaudeRadarConfiguration(benchmarkURL: benchmarkURL, communityURL: nil, sourceStatusURL: nil)
        let coordinator = RadarSyncCoordinator(source: ClaudeCodeRadarSource(configuration: noCommunity, transport: transport), repository: fixture.repository, clock: clock)
        await coordinator.refresh(trigger: .networkRecovery)

        // When
        clock.advance(by: 61)
        await coordinator.refresh(trigger: .networkRecovery)

        // Then
        #expect(await transport.requestCount(for: benchmarkURL) == 1)
    }

    @Test("periodic network and wake lifecycle registration is idempotent and stops once")
    func lifecycleRegistrationIsIdempotent() async throws {
        // Given
        let fixture = try repositoryFixture()
        let network = CountingNetworkMonitor()
        let wake = CountingSleepNotifier()
        let coordinator = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(
                configuration: ClaudeRadarConfiguration(benchmarkURL: benchmarkURL, communityURL: nil, sourceStatusURL: nil),
                transport: GatedRoutingTransport(routes: [:])
            ),
            repository: fixture.repository,
            networkMonitor: network,
            sleepNotifier: wake
        )

        // When
        await coordinator.startLifecycleTriggers()
        await coordinator.startLifecycleTriggers()
        await coordinator.startPeriodicRefresh()
        await coordinator.startPeriodicRefresh()
        await coordinator.stop()
        network.fireRecovery()
        wake.fireRecovery()
        try await Task.sleep(for: .milliseconds(20))

        // Then
        #expect(network.startCount == 1)
        #expect(wake.startCount == 1)
        #expect(network.stopCount == 1)
        #expect(wake.stopCount == 1)
        #expect(!(await coordinator.lifecycleState()).hasActiveTask)
    }

    @Test("stale community triggers recovery even when benchmark is fresh")
    func staleCommunityRecovery() async throws {
        // Given
        let fixture = try repositoryFixture()
        let now = Date(timeIntervalSince1970: 4_000)
        let clock = TestRadarClock(now)
        _ = try await fixture.repository.insertBenchmark(testBenchmark(fetchedAt: now))
        clock.advance(by: 61)
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [.json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"))],
            communityURL: [.json(url: communityURL, body: try fixtureData("claude-radar-community-valid"))],
        ])
        let coordinator = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: transport),
            repository: fixture.repository,
            clock: clock
        )

        // When
        await coordinator.refresh(trigger: .networkRecovery)

        // Then
        #expect(await transport.requestCount(for: benchmarkURL) == 1)
        #expect(await transport.requestCount(for: communityURL) == 1)
    }

    @Test("304 without validator headers preserves persisted validators")
    func notModifiedMergesValidators() async throws {
        // Given
        let fixture = try repositoryFixture()
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [
                .json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"), headers: ["ETag": "\"stable\"", "Last-Modified": "Wed, 15 Jul 2026 01:00:00 GMT"]),
                .status(url: benchmarkURL, code: 304),
            ],
        ])
        let noCommunity = ClaudeRadarConfiguration(benchmarkURL: benchmarkURL, communityURL: nil, sourceStatusURL: nil)
        let first = RadarSyncCoordinator(source: ClaudeCodeRadarSource(configuration: noCommunity, transport: transport), repository: fixture.repository)
        await first.refresh(trigger: .manual)
        let restarted = RadarSyncCoordinator(source: ClaudeCodeRadarSource(configuration: noCommunity, transport: transport), repository: fixture.repository)

        // When
        await restarted.refresh(trigger: .manual)
        let metadata = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark)

        // Then
        #expect(metadata.etag == "\"stable\"")
        #expect(metadata.lastModified == "Wed, 15 Jul 2026 01:00:00 GMT")
    }

    @Test("unhealthy source-status sibling suppresses shared validators and forces a repair body")
    func unhealthySiblingForcesFullEnvelope() async throws {
        // Given
        let fixture = try repositoryFixture()
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [
                .json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"), headers: ["ETag": "\"shared\""]),
                .json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"), headers: ["ETag": "\"repaired\""]),
            ],
        ])
        let configuration = ClaudeRadarConfiguration(benchmarkURL: benchmarkURL, communityURL: nil, sourceStatusURL: nil)
        let first = RadarSyncCoordinator(source: ClaudeCodeRadarSource(configuration: configuration, transport: transport), repository: fixture.repository)
        await first.refresh(trigger: .manual)
        try await fixture.repository.recordFailure(
            sourceID: .claudeCodeRadar,
            datasetType: .sourceStatus,
            attemptedAt: Date(),
            error: SegmentError(kind: .decoding, message: "corrupt current status")
        )

        // When
        let restarted = RadarSyncCoordinator(source: ClaudeCodeRadarSource(configuration: configuration, transport: transport), repository: fixture.repository)
        await restarted.refresh(trigger: .manual)
        let requests = await transport.requests(for: benchmarkURL)

        // Then
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(requests[1].value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect((try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .sourceStatus)).lastError == nil)
    }

    @Test("304 without local LKG remains failed and retries without stale validators")
    func notModifiedRequiresLKG() async throws {
        // Given
        let fixture = try repositoryFixture()
        try await fixture.repository.recordValidators(
            sourceID: .claudeCodeRadar,
            datasetType: .benchmark,
            validators: HTTPValidators(etag: "\"orphan\"", lastModified: nil)
        )
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [
                .status(url: benchmarkURL, code: 304),
                .json(url: benchmarkURL, body: try fixtureData("claude-radar-valid")),
            ],
        ])
        let noCommunity = ClaudeRadarConfiguration(benchmarkURL: benchmarkURL, communityURL: nil, sourceStatusURL: nil)
        let coordinator = RadarSyncCoordinator(source: ClaudeCodeRadarSource(configuration: noCommunity, transport: transport), repository: fixture.repository)

        // When
        await coordinator.refresh(trigger: .manual)
        let missingState = try await coordinator.projection()
        await coordinator.refresh(trigger: .manual)
        let requests = await transport.requests(for: benchmarkURL)

        // Then
        #expect(missingState.benchmark.value == nil)
        #expect(missingState.benchmark.error != nil)
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(requests[1].value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(try await fixture.repository.snapshotCount(datasetType: .benchmark, sourceID: .claudeCodeRadar) == 1)
    }

    @Test("unconfigured community is neutral and cannot clear failed shared-envelope backoff")
    func absentCommunityDoesNotClearBackoff() async throws {
        // Given
        let fixture = try repositoryFixture()
        let now = Date(timeIntervalSince1970: 5_000)
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [.status(url: benchmarkURL, code: 500)],
        ])
        let noCommunity = ClaudeRadarConfiguration(benchmarkURL: benchmarkURL, communityURL: nil, sourceStatusURL: nil)
        let coordinator = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: noCommunity, transport: transport),
            repository: fixture.repository,
            clock: TestRadarClock(now)
        )

        // When
        await coordinator.refresh(trigger: .startup)
        let metadata = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark)

        // Then
        #expect(metadata.consecutiveFailures == 1)
        #expect(metadata.backoffUntil == now.addingTimeInterval(60))
    }

    @Test("successful community cannot clear failing envelope backoff across restart")
    func segmentBackoffSurvivesRestart() async throws {
        let fixture = try repositoryFixture()
        let firstAttempt = Date(timeIntervalSince1970: 8_000)
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [
                .status(url: benchmarkURL, code: 500),
                .status(url: benchmarkURL, code: 500),
            ],
            communityURL: [
                .json(url: communityURL, body: try fixtureData("claude-radar-community-valid")),
                .json(url: communityURL, body: try fixtureData("claude-radar-community-valid")),
            ],
        ])
        let first = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: transport),
            repository: fixture.repository,
            clock: TestRadarClock(firstAttempt)
        )

        await first.refresh(trigger: .manual)
        let firstBenchmark = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark)
        let firstCommunity = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .community)
        let secondAttempt = firstAttempt.addingTimeInterval(61)
        let restarted = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: transport),
            repository: fixture.repository,
            clock: TestRadarClock(secondAttempt)
        )
        await restarted.refresh(trigger: .periodic)
        let secondBenchmark = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark)
        let secondCommunity = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .community)

        #expect(firstBenchmark.consecutiveFailures == 1)
        #expect(firstBenchmark.backoffUntil == firstAttempt.addingTimeInterval(60))
        #expect(firstCommunity.consecutiveFailures == 0)
        #expect(firstCommunity.backoffUntil == nil)
        #expect(secondBenchmark.consecutiveFailures == 2)
        #expect(secondBenchmark.backoffUntil == secondAttempt.addingTimeInterval(5 * 60))
        #expect(secondCommunity.consecutiveFailures == 0)
        #expect(secondCommunity.backoffUntil == nil)
    }

    @Test("community backoff skips only community while periodic shared acquisition succeeds")
    func communityBackoffDoesNotBlockSharedEndpoint() async throws {
        let fixture = try repositoryFixture()
        let now = Date(timeIntervalSince1970: 12_000)
        try await fixture.repository.recordFailure(
            sourceID: .claudeCodeRadar,
            datasetType: .community,
            attemptedAt: now,
            error: SegmentError(kind: .http, message: "community unavailable")
        )
        try await fixture.repository.recordBackoff(
            sourceID: .claudeCodeRadar,
            datasetType: .community,
            until: now.addingTimeInterval(6 * 60 * 60),
            failureCount: 6
        )
        let communityBefore = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .community)
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [.json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"))],
            communityURL: [.json(url: communityURL, body: try fixtureData("claude-radar-community-valid"))],
        ])
        let coordinator = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: transport),
            repository: fixture.repository,
            clock: TestRadarClock(now)
        )

        await coordinator.refresh(trigger: .periodic)

        #expect(await transport.requestCount(for: benchmarkURL) == 1)
        #expect(await transport.requestCount(for: communityURL) == 0)
        #expect(try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .community) == communityBefore)
        #expect(try await fixture.repository.snapshotCount(datasetType: .benchmark, sourceID: .claudeCodeRadar) == 1)
    }

    @Test("manual honors shared Retry After while independent community acquisition succeeds")
    func sharedRetryAfterDoesNotBlockManualCommunityEndpoint() async throws {
        let fixture = try repositoryFixture()
        let now = Date(timeIntervalSince1970: 13_000)
        try await fixture.repository.recordFailure(
            sourceID: .claudeCodeRadar,
            datasetType: .benchmark,
            attemptedAt: now,
            error: SegmentError(kind: .http, message: "shared rate limited"),
            retryAfter: now.addingTimeInterval(600)
        )
        let benchmarkBefore = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark)
        let statusBefore = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .sourceStatus)
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [.json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"))],
            communityURL: [.json(url: communityURL, body: try fixtureData("claude-radar-community-valid"))],
        ])
        let coordinator = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: transport),
            repository: fixture.repository,
            clock: TestRadarClock(now)
        )

        await coordinator.refresh(trigger: .manual)

        #expect(await transport.requestCount(for: benchmarkURL) == 0)
        #expect(await transport.requestCount(for: communityURL) == 1)
        #expect(try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark) == benchmarkBefore)
        #expect(try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .sourceStatus) == statusBefore)
        #expect(try await fixture.repository.snapshotCount(datasetType: .community, sourceID: .claudeCodeRadar) == 1)
    }

    @Test("shared backoff skips only shared acquisition while periodic community succeeds")
    func sharedBackoffDoesNotBlockCommunityEndpoint() async throws {
        let fixture = try repositoryFixture()
        let now = Date(timeIntervalSince1970: 13_500)
        for type in [RadarDatasetType.benchmark, .sourceStatus] {
            try await fixture.repository.recordFailure(
                sourceID: .claudeCodeRadar,
                datasetType: type,
                attemptedAt: now,
                error: SegmentError(kind: .http, message: "shared unavailable")
            )
            try await fixture.repository.recordBackoff(
                sourceID: .claudeCodeRadar,
                datasetType: type,
                until: now.addingTimeInterval(6 * 60 * 60),
                failureCount: 6
            )
        }
        let benchmarkBefore = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark)
        let statusBefore = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .sourceStatus)
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [.json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"))],
            communityURL: [.json(url: communityURL, body: try fixtureData("claude-radar-community-valid"))],
        ])
        let coordinator = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: transport),
            repository: fixture.repository,
            clock: TestRadarClock(now)
        )

        await coordinator.refresh(trigger: .periodic)

        #expect(await transport.requestCount(for: benchmarkURL) == 0)
        #expect(await transport.requestCount(for: communityURL) == 1)
        #expect(try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark) == benchmarkBefore)
        #expect(try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .sourceStatus) == statusBefore)
        #expect(try await fixture.repository.snapshotCount(datasetType: .community, sourceID: .claudeCodeRadar) == 1)
    }

    @Test("manual bypasses community elapsed backoff without bypassing shared Retry After")
    func manualBackoffBypassIsEndpointScoped() async throws {
        let fixture = try repositoryFixture()
        let now = Date(timeIntervalSince1970: 14_000)
        try await fixture.repository.recordFailure(
            sourceID: .claudeCodeRadar,
            datasetType: .benchmark,
            attemptedAt: now,
            error: SegmentError(kind: .http, message: "shared rate limited"),
            retryAfter: now.addingTimeInterval(600)
        )
        try await fixture.repository.recordFailure(
            sourceID: .claudeCodeRadar,
            datasetType: .community,
            attemptedAt: now,
            error: SegmentError(kind: .network, message: "community offline")
        )
        try await fixture.repository.recordBackoff(
            sourceID: .claudeCodeRadar,
            datasetType: .community,
            until: now.addingTimeInterval(600),
            failureCount: 2
        )
        let benchmarkBefore = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark)
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [.json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"))],
            communityURL: [.json(url: communityURL, body: try fixtureData("claude-radar-community-valid"))],
        ])
        let coordinator = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: transport),
            repository: fixture.repository,
            clock: TestRadarClock(now)
        )

        await coordinator.refresh(trigger: .manual)

        #expect(await transport.requestCount(for: benchmarkURL) == 0)
        #expect(await transport.requestCount(for: communityURL) == 1)
        #expect(try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark) == benchmarkBefore)
        let communityAfter = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .community)
        #expect(communityAfter.lastError == nil)
        #expect(communityAfter.retryAfter == nil)
        #expect(communityAfter.backoffUntil == nil)
        #expect(communityAfter.consecutiveFailures == 0)
    }

    @Test("recovery minimum interval blocks only the recently attempted endpoint group")
    func recoveryMinimumIntervalIsEndpointScoped() async throws {
        let fixture = try repositoryFixture()
        let now = Date(timeIntervalSince1970: 15_000)
        for type in [RadarDatasetType.benchmark, .sourceStatus] {
            try await fixture.repository.recordFailure(
                sourceID: .claudeCodeRadar,
                datasetType: type,
                attemptedAt: now,
                error: SegmentError(kind: .network, message: "shared offline")
            )
        }
        let benchmarkBefore = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark)
        let statusBefore = try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .sourceStatus)
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [.json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"))],
            communityURL: [.json(url: communityURL, body: try fixtureData("claude-radar-community-valid"))],
        ])
        let coordinator = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: transport),
            repository: fixture.repository,
            clock: TestRadarClock(now)
        )

        await coordinator.refresh(trigger: .networkRecovery)

        #expect(await transport.requestCount(for: benchmarkURL) == 0)
        #expect(await transport.requestCount(for: communityURL) == 1)
        #expect(try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark) == benchmarkBefore)
        #expect(try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .sourceStatus) == statusBefore)
    }

    @Test("blocked shared and community groups create no acquisition task or metadata mutation")
    func bothEndpointGroupsBlocked() async throws {
        let fixture = try repositoryFixture()
        let now = Date(timeIntervalSince1970: 16_000)
        for type in [RadarDatasetType.benchmark, .sourceStatus, .community] {
            try await fixture.repository.recordFailure(
                sourceID: .claudeCodeRadar,
                datasetType: type,
                attemptedAt: now,
                error: SegmentError(kind: .http, message: "blocked"),
                retryAfter: now.addingTimeInterval(600)
            )
        }
        let before = [
            try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark),
            try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .sourceStatus),
            try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .community),
        ]
        let transport = GatedRoutingTransport(routes: [
            benchmarkURL: [.json(url: benchmarkURL, body: try fixtureData("claude-radar-valid"))],
            communityURL: [.json(url: communityURL, body: try fixtureData("claude-radar-community-valid"))],
        ])
        let coordinator = RadarSyncCoordinator(
            source: ClaudeCodeRadarSource(configuration: configuration, transport: transport),
            repository: fixture.repository,
            clock: TestRadarClock(now)
        )

        await coordinator.refresh(trigger: .periodic)

        #expect(await transport.requestCount(for: benchmarkURL) == 0)
        #expect(await transport.requestCount(for: communityURL) == 0)
        #expect(!(await coordinator.lifecycleState()).hasActiveTask)
        let after = [
            try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .benchmark),
            try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .sourceStatus),
            try await fixture.repository.metadata(sourceID: .claudeCodeRadar, datasetType: .community),
        ]
        #expect(after == before)
    }

    private var benchmarkURL: URL { URL(string: "https://sync.invalid/benchmark")! }
    private var communityURL: URL { URL(string: "https://sync.invalid/community")! }
    private var configuration: ClaudeRadarConfiguration {
        ClaudeRadarConfiguration(benchmarkURL: benchmarkURL, communityURL: communityURL, sourceStatusURL: nil)
    }

    private func fixtureData(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appending(path: "Sources/ClaudeRadar/Resources/Fixtures/\(name).json"))
    }

    private func repositoryFixture() throws -> RepositoryFixture {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let container = try RadarModelSchema.makeContainer(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return RepositoryFixture(root: root, container: container, repository: RadarRepository(container: container, metadataStore: SyncMetadataStore(root: root)))
    }

    private func testBenchmark(fetchedAt: Date) -> BenchmarkDataset {
        let id = ModelID(sourceID: .claudeCodeRadar, upstreamKey: "fresh")
        return BenchmarkDataset(
            sourceID: .claudeCodeRadar,
            sourceUpdatedAt: fetchedAt,
            fetchedAt: fetchedAt,
            benchmarkName: nil,
            benchmarkVersion: nil,
            seriesRevision: ClaudeRadarConfiguration.seriesRevision,
            models: [ModelBenchmark(
                id: id,
                descriptor: ModelDescriptor(id: id, upstreamName: "Fresh", displayName: "Fresh"),
                qualityScore: 1,
                passedTasks: 1,
                validTasks: 1,
                invalidTasks: 0,
                benchmarkCostUSD: 1,
                inputTokens: nil,
                outputTokens: nil,
                cacheReadTokens: nil,
                cacheCreationTokens: nil,
                totalTokens: nil,
                elapsedSeconds: 1,
                agentSteps: nil,
                cacheHitPercent: nil
            )]
        )
    }
}

private final class TestRadarClock: RadarClock, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) { self.date = date }

    func now() -> Date {
        lock.withLock { date }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock { date = date.addingTimeInterval(interval) }
    }
}

private actor StartBarrier {
    private let target: Int
    private var arrivals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var fullWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    init(target: Int) { self.target = target }

    func arriveAndWait() async {
        arrivals += 1
        if arrivals == target {
            for waiter in fullWaiters { waiter.resume() }
            fullWaiters.removeAll()
        }
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func waitUntilFull() async {
        if arrivals == target { return }
        await withCheckedContinuation { fullWaiters.append($0) }
    }

    func release() {
        released = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

private actor CompletionFlag {
    private(set) var isCompleted = false
    func markCompleted() { isCompleted = true }
}

private final class CountingNetworkMonitor: NetworkMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0
    private var callback: (@Sendable () -> Void)?
    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
    func start(_ recovered: @escaping @Sendable () -> Void) {
        lock.withLock {
            starts += 1
            callback = recovered
        }
    }
    func stop() {
        lock.withLock {
            stops += 1
            callback = nil
        }
    }
    func fireRecovery() { lock.withLock { callback }?() }
}

private final class CountingSleepNotifier: SleepRecoveryNotifying, @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0
    private var callback: (@Sendable () -> Void)?
    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
    func start(_ recovered: @escaping @Sendable () -> Void) {
        lock.withLock {
            starts += 1
            callback = recovered
        }
    }
    func stop() {
        lock.withLock {
            stops += 1
            callback = nil
        }
    }
    func fireRecovery() { lock.withLock { callback }?() }
}

private actor ProjectionRecorder {
    private var values: [RadarSyncProjection] = []
    var count: Int { values.count }
    var last: RadarSyncProjection? { values.last }
    func append(_ projection: RadarSyncProjection) { values.append(projection) }
}

private actor CancellationIgnoringTransport: HTTPTransport {
    private let response: HTTPTransportResponse
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var requestCount = 0
    private(set) var cancelAllCount = 0

    init(response: HTTPTransportResponse) { self.response = response }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        requestCount += 1
        let ready = countWaiters.filter { requestCount >= $0.0 }
        countWaiters.removeAll { requestCount >= $0.0 }
        for waiter in ready { waiter.1.resume() }
        await withCheckedContinuation { continuations.append($0) }
        return HTTPTransportResponse(
            data: response.data,
            response: HTTPURLResponse(
                url: request.url!,
                statusCode: response.response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
        )
    }

    func cancelAll() async { cancelAllCount += 1 }

    func waitUntilRequestCount(_ expected: Int) async {
        if requestCount >= expected { return }
        await withCheckedContinuation { countWaiters.append((expected, $0)) }
    }

    func releaseAll() {
        for continuation in continuations { continuation.resume() }
        continuations.removeAll()
    }
}

private actor GatedRoutingTransport: HTTPTransport {
    private var routes: [URL: [HTTPTransportResponse]]
    private let gatedURL: URL?
    private var counts: [URL: Int] = [:]
    private var requests: [URL: [URLRequest]] = [:]
    private var gateContinuation: CheckedContinuation<Void, Never>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []

    init(routes: [URL: [HTTPTransportResponse]], gatedURL: URL? = nil) {
        self.routes = routes
        self.gatedURL = gatedURL
    }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        guard let url = request.url, var responses = routes[url], !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        counts[url, default: 0] += 1
        requests[url, default: []].append(request)
        routes[url] = Array(responses.dropFirst())
        if url == gatedURL, counts[url] == 1 {
            for continuation in startContinuations { continuation.resume() }
            startContinuations.removeAll()
            await withCheckedContinuation { gateContinuation = $0 }
        }
        return responses.removeFirst()
    }

    func waitUntilGatedRequestStarts() async {
        if let gatedURL, counts[gatedURL, default: 0] > 0 { return }
        await withCheckedContinuation { startContinuations.append($0) }
    }

    func release() {
        gateContinuation?.resume()
        gateContinuation = nil
    }

    func requestCount(for url: URL) -> Int { counts[url, default: 0] }
    func lastRequest(for url: URL) -> URLRequest? { requests[url]?.last }
    func requests(for url: URL) -> [URLRequest] { requests[url] ?? [] }
}
