# Radar Source Contracts

The existing contract sections through “Canonical sanitized fixtures” describe Claude Code Radar. Later sections record the independent Codex Radar public-summary adapter and SWE-bench Verified leaderboard adapter. The three sources never share identities, history, exports, trends, rankings, or analysis.

## Release boundary

- Homepage: `https://claudecoderadar.com/?lang=en`
- Support: `authorized`
- public online default: enabled
- Access: the inspected GET endpoints are public and require no authentication.
- Project authorization: on 2026-07-16, the project owner authorized automatic synchronization, local history retention, and in-app re-display of the public GET responses.
- Access controls: the app must not bypass authentication, challenges, rate limits, or other access controls and must not persist cookies or sensitive request headers.
- Release enforcement: `AppEnvironment.current()` enables all three public source runtimes outside Debug, while the Release bundle excludes every development fixture and includes only the app icon under Resources. Settings/About disclose the same boundary. See `release-checklist.md` and `third-party-notices.md`.
- Manual real-site acceptance uses a Debug package with `RADAR_FIXTURE_MODE=online` and an isolated `RADAR_DATA_ROOT`. That mode starts all production HTTP/source/parser/repository paths without fixture transport.

## Scenario: multi-source automatic synchronization and cache restoration

### 1. Scope / Trigger

Release startup, Debug `online` QA, and every future source addition share one local data root. This contract applies whenever two or more `RadarAppRuntime` instances can update normalized history or synchronization metadata concurrently.

### 2. Signatures

- App startup: `RadarWorkspaceModel.start() async` starts every runtime in its source-keyed runtime map.
- Runtime construction: `RadarAppRuntime(environment:sourceID:metadataStore:...)`; the app root passes the same `SyncMetadataStore` actor to all production runtimes.
- Metadata storage: `SyncMetadataStore(root:)` writes `<dataRoot>/SyncMetadata.json` with keys `<sourceID>|<datasetType>`.
- Normalized storage: the three SwiftData snapshot tables keep `sourceID`, `seriesRevision`, source/fetch timestamps, fingerprint, and encoded dataset.

### 3. Contracts

- Release requires no environment key and enables all three sources. Debug `RADAR_FIXTURE_MODE=online` does the same; `sequence` enables only Claude, `codex` enables only the local Codex fixture, and all other fixture modes perform no HTTP synchronization.
- Selecting a workspace changes presentation only. Startup, periodic, network-recovery, and wake synchronization remain active for every enabled runtime.
- All runtimes that share a data root must share one `SyncMetadataStore` actor. Atomic file replacement alone does not make independent read-modify-write actor instances safe.
- Benchmark, community, source-status, raw samples, metadata, LKG lookup, history, trends, and export remain scoped by `RadarSourceID`.

### 4. Validation & Error Matrix

| Condition | Required result |
| --- | --- |
| All public sources succeed | Claude and Codex persist their three normalized segments; SWE-bench persists its benchmark segment only. |
| One segment refresh fails with an existing snapshot | Preserve and label that segment's LKG; do not replace it with the failed response. |
| Metadata is corrupt | Report metadata decoding failure while independently readable normalized history remains available. |
| Synchronization is disabled for QA restart | Make no request and load every available source-scoped cached projection. |
| Two runtimes update metadata concurrently | Serialize through the shared actor; no last-writer loss is allowed. |
| Protected Codex full API is unavailable or requires credentials | Do not request, emulate, retry, or bypass it. |
| SWE-bench has no community or quota/status segment | Persist benchmark data without manufacturing segment failures. |

### 5. Good / Base / Bad Cases

- Good: an isolated `online` launch stores independent Claude, Codex, and SWE-bench snapshots and raw samples; a disabled relaunch displays the available source rooms.
- Base: a source has no prior snapshot, so its workspace remains explicitly empty until a valid public response arrives.
- Bad: constructing one metadata actor per runtime against the same root lets concurrent read-modify-write cycles overwrite sibling-source records even though each individual file replacement is atomic.

### 6. Tests Required

- `ReleaseReadinessTests`: Release/online enables all approved sources, app startup is unconditional, and every runtime receives the shared metadata actor.
- `MultiSourceWorkspaceTests`: one workspace start activates all runtimes; source selection never merges projections.
- `SWEBenchParserTests`: cohort filtering, exact 500-task mapping, duplicate policy, HTTP policy, and status-less synchronization remain frozen.
- Packaged manual QA: run a fresh isolated online read, then inspect the global overview and each source-native room.

### 7. Wrong vs Correct

Wrong: each runtime creates an actor for the same file, so actor isolation does not extend across instances.

```swift
RadarRepository(container: container, metadataStore: SyncMetadataStore(root: environment.dataRoot))
```

Correct: the app composition root creates one actor and injects it into every runtime sharing that data root.

```swift
let metadataStore = SyncMetadataStore(root: environment.dataRoot)
let claude = RadarAppRuntime(environment: environment, sourceID: .claudeCodeRadar, metadataStore: metadataStore)
let codex = RadarAppRuntime(environment: environment, sourceID: .codexRadar, metadataStore: metadataStore)
let sweBench = RadarAppRuntime(environment: environment, sourceID: .sweBenchVerified, metadataStore: metadataStore)
```

## SWE-bench Verified leaderboard GET

Endpoint: `https://raw.githubusercontent.com/SWE-bench/swe-bench.github.io/master/data/leaderboards.json`

- Response policy: HTTPS, same-host redirects, no credentials or cookies, at most 16 MiB, and JSON decoded from the observed `text/plain` response. Existing sources retain their 5 MiB JSON-only policy.
- Scope: select exactly one `bash-only` board, then include rows whose `mini-swe-agent_version` begins with `2.` and whose warning is absent.
- Identity: `folder` is the upstream key. Exact semantic duplicates collapse deterministically; conflicting duplicates reject the projection.
- Quality: upstream `resolved` remains a percentage in `0...100` and is displayed as `% Resolved`.
- Task counts: SWE-bench Verified has 500 tasks. `passedTasks` is derived only when `resolved × 5` is an exact integer; `validTasks` is 500.
- Cost: published total evaluation cost maps to `benchmarkCostUSD`; absent values stay `nil`.
- Missing fields: tokens, elapsed time, cache, community, and source status remain absent instead of being fabricated.
- Revision: `swe-bench-verified-mini-v2-v1`. Trends and Pareto analysis stay within this source, cohort, and revision.
- Product boundary: Radar only reads, caches, analyzes, displays, and exports published results. It never runs the evaluator or submits data.

## Observation receipt

Observed from the public endpoints on 2026-07-14 in Asia/Shanghai. The community scale was rechecked at 23:45 +08:00 after the Phase 1 verifier finding. Values and headers can drift; runtime code must validate them before accepting data.

| Surface | HTTP | MIME | Body | Cache and validators |
| --- | --- | --- | ---: | --- |
| Homepage | 200 | `text/html; charset=utf-8` | not retained | `Cache-Control: public, max-age=0, must-revalidate` |
| Benchmark and source status | 200 | `application/json` | 37,491 bytes | `Cache-Control: public, s-maxage=604800`; ETag present; the observed `If-None-Match` request returned 304 |
| Community | 200 | `application/json; charset=UTF-8` | 12,541 bytes | `Cache-Control: public, max-age=60, s-maxage=300, stale-while-revalidate=900`; no validator observed |

The final Phase 1 community recheck returned 12 models in a 12,539-byte response with SHA-256 `4d025cfe8d3e9bc94dd6547f80e627332e0cc33a074fd89fa18e12a277e7dbc2`. The full response was inspected transiently and removed; only the non-sensitive shape, bounds, hash, and sanitized fixture were retained in `.omo/evidence/phase-1/community-contract.txt`.

The source status is embedded in the benchmark response under `quota`; it is not fetched from a guessed separate endpoint.

## Benchmark and source-status GET

Endpoint: `https://claudecoderadar.com/data/claude-code-radar.json`

Top-level paths are `ok`, `updated_at`, `labels`, `iq`, and `quota`.

| JSON path | Observed shape and semantics | Nullability and bounds |
| --- | --- | --- |
| `ok` | Boolean response flag | Required by the observed response |
| `updated_at` | ISO-8601 publication timestamp | String in the observed response; invalid values must not be fabricated |
| `labels[]` | Series labels aligned with model arrays | String array; array positions can have missing model measurements |
| `iq.models[].key` | Upstream model key and preferred stable-ID input | Non-empty string required for acceptance |
| `iq.models[].name` | Model display name | Non-empty string; version, date, thinking, and context suffixes remain identity-significant |
| `iq.models[].score` and `iq.models[].iq[]` | Source IQ points, not a percentage | Number or null; observed values include 15 through 120, so they must not be clamped to 0...100 |
| `iq.models[].pass[]`, `valid[]`, `invalid[]` | Task counts aligned to `labels[]` | Non-negative integer or null; `pass` cannot exceed `valid` |
| `iq.models[].cost[]` | Benchmark cost in USD, confirmed by the source table's `$` formatting | Non-negative decimal or null; preserve decimal text without binary-roundtrip normalization |
| `iq.models[].time[]` | Benchmark elapsed time in hours, confirmed by the source table's `h` formatting | Non-negative number or null; domain conversion to seconds is Phase 1 work |
| `iq.models[].cache[]` | Cache hit percentage | Decimal or null in 0...100 |
| `iq.models[].latest_at` | Latest model-run timestamp | ISO-8601 string or null |
| `iq.models[].latest_label` | Human-readable latest-run label; originally matched `labels[]`, but the 2026-07-15 live response localized it independently | Optional string. Prefer an exact `labels[]` match. If the label is localized, derive the source-series label from `latest_at` while preserving its ISO-8601 offset and require that derived label to match `labels[]`; otherwise benchmark projection fails. When absent, deliberately select the final aligned point because the source arrays are ordered measurement histories. Each path is covered by a parser test. |
| `iq.models[].run_ids[]` | Upstream run identifiers | String array; diagnostic only and not a cross-source identity |
| `quota.metrics[].key` | Quota metric stable-ID input such as `h5` or `d7` | Non-empty string |
| `quota.metrics[].value` | Source account's projected quota value | Non-negative decimal or null; not personal user usage |
| `quota.usage[].used_pct` | Source account's projected used percentage | Decimal or null in 0...100 |
| `quota.usage[].reset_text_en` | Source-provided reset description | String or null; display as source estimate |

`iq.table.rows` contains source presentation rows, including Agent Steps. Phase 0 records that path but does not create a parser or guess a model-field mapping. Token and cache-token fields were not confirmed in the inspected response and remain absent rather than zero-filled.

## Community GET

Endpoint: `https://claudecoderadar.com/api/model-ratings?history=10`

The public GET required no authentication. It reported `window = "rolling_24h"` and `window_hours = 24`.

| JSON path | Observed shape and semantics | Nullability and bounds |
| --- | --- | --- |
| `ok` | Boolean response flag | Required by the observed response |
| `updated_at`, `cached_at`, `since`, `until` | Response and rolling-window timestamps | ISO-8601 strings in the observed response |
| `models[].id` | Preferred community model stable-ID input | Non-empty string |
| `models[].label`, `models[].group` | Display labels | String |
| `models[].average` | Community average on the source's 1...10 rating scale | Decimal or null; non-null values must be within inclusive 1...10 and are not percentages |
| `models[].count` | Community vote count | Non-negative integer or null; the current response uses count `0` with a null average for unrated models |
| `history[].day` | Calendar bucket | Date string |
| `history[].updated_at` | Bucket revision timestamp | ISO-8601 string |
| `history[].models[]` | Per-day rating entries with the same model shape | Array |
| `my_scores` | Source response field | Object; it is not consumed because personal data is outside scope |

Community ratings never feed benchmark quality, derived benchmark metrics, or Pareto calculations.

The public homepage defines five score bands spanning 1 through 10, from nearly unusable at 1–2 through excellent at 9–10. The inspected current response had non-null current averages from 2 through 8.7 and history averages reaching 10. Domain `scaleMinimum` and `scaleMaximum` are therefore the source-contract constants `1` and `10`; the parser preserves the average without percentage conversion and keeps an absent average `nil`.

## Identity and fingerprints

- Benchmark model stable ID: `iq.models[].key`; name is only a conservative fallback in Phase 1.
- Community model stable ID: `models[].id`.
- Source-status estimate stable ID: `quota.metrics[].key` or `quota.usage[].key` within its segment.
- Every fingerprint is scoped by source ID and dataset type.
- Benchmark includes the semantic normalized benchmark values, series revision, and `iq.updated_at` when present.
- Community includes normalized ratings/history and `updated_at` because it identifies a rolling publication revision.
- Source status includes normalized quota values and `quota.updated_at` because it identifies a source-status publication revision.
- Local `fetchedAt`, request duration, response headers, and local errors are excluded.

## Canonical sanitized fixtures

The three Phase 0 fixtures and the Phase 1 community fixture are small hand-sanitized projections of the public shapes. They contain no cookies, authorization values, email addresses, personal identifiers, or raw response text. The community fixture was added in Phase 1 because the parser boundary could not be accepted without freezing and testing the real 1...10 scale and null behavior.

| Fixture | Purpose | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `claude-radar-valid.json` | Minimal valid benchmark and quota shape | 1,105 | `4607d8aacef5bfbb777044529bfbd86a7bd00b12fdff2c88fe2940c15599a6dc` |
| `claude-radar-null-fields.json` | Explicit null and missing optional values | 769 | `d06e9a82107f58c606f2d047a4c907b7f04d3a99394c77b227d659e24863d51f` |
| `claude-radar-invalid.json` | Valid JSON with invalid dates, identity, counts, percentages, costs, and time | 577 | `1c111e576e439dc39bbad1a8a0ee62329a2cd76e023a46463d8bf765e9b9eb43` |
| `claude-radar-community-valid.json` | Sanitized rolling-24h community ratings with a 7.6 average and explicit null unrated model | 423 | `c66ff8b5c15112c5dd7616f225b8615c830c493174a3e991fad7d83bca24aa99` |

Fixtures are the canonical Phase 0 data source. They are not a license to redistribute the full upstream payload.

## Codex Radar public-summary contract

### Release and authorization boundary

- Homepage: `https://codexradar.com/`
- Public summary: `https://codexradar.com/current.json`
- Community ratings: `https://codexradar.com/api/model-ratings?history=14`
- Source ID: `codex-radar`; series revision: `codex-radar-public-v2`; support: `authorized`.
- The public summary declares `full_api_status = authorization_required`, says full JSON API and derivative integrations require authorization, and requires the attribution `数据来自 Codex 雷达 codexradar.com`.
- A direct request to `/api/v1/current` returned HTTP 401 during the 2026-07-15 inspection. The adapter does not call, emulate, or bypass that protected API.
- On 2026-07-16, the project owner authorized automatic synchronization, local history retention, and in-app re-display for `current.json` and the public community endpoint. Release and Debug `online` QA enable this public adapter; the protected full API remains excluded.

### Public-summary projection

Observed on 2026-07-15 in Asia/Shanghai. The payload identifies schema `2.0`; fields and availability may drift, so every segment is validated before persistence.

| JSON path | Domain mapping and validation |
| --- | --- |
| `schema_version` | Benchmark version; the adapter series remains the explicit `codex-radar-public-v2` contract revision. |
| `model_iq.latest` and `model_iq.comparisons.*.latest` | One benchmark model per unique `model + reasoning_effort`; a duplicate top-level latest configuration is discarded. |
| `score`, `passed`, `valid_tasks`/`tasks`, `invalid` | Quality and task counts; non-negative values and `passed <= valid` are required. |
| `cost_usd`, `input_tokens`, `cached_input_tokens`, `output_tokens`, `total_tokens`, `wall_seconds` | Cost, Token, cache, and duration metrics. Cached input must not exceed input; cache percentage is derived only when input is positive. Missing values stay `nil`. |
| `model_iq.quota_radar.basis_window_label` | Selects the currently active `five_h` or `seven_d` estimate for each tier. These are source quota estimates in USD, never personal user usage percentages. |
| `model_iq.quota_radar.rows[]` | One source-status estimate per tier and active window; `basis` is retained as the source explanation. |

Benchmark and embedded quota status share one `current.json` acquisition but project independently. Community ratings use the shared 1...10 rating contract while every model ID remains scoped to `codex-radar`. No Codex value is joined to, ranked against, or exported with Claude values.

### Canonical sanitized fixtures

| Fixture | Purpose | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `codex-radar-public-summary.json` | Minimal schema-2 benchmark and active-window quota summary | 2,111 | `00b32c6cbad957cdb2fce12f0a227ec89f7bc6d0c66a9d18c7de57a49269852a` |
| `codex-radar-community-valid.json` | Source-scoped 1...10 community values with an explicit null rating | 313 | `d4dd5e2214aea8e04c4fcc514d99551c0b910e2c09de2bb955da6dcd1ebe8406` |

These are small hand-authored projections of the public shapes, not copied live payloads and not evidence of permission to redistribute upstream data.
