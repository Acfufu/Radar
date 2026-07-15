# Claude Code Radar Source Contract

## Release boundary

- Homepage: `https://claudecoderadar.com/?lang=en`
- Development support: `experimental`
- public online default: disabled
- Access: the inspected GET endpoints are public and require no authentication.
- Permission: no affirmative license or terms were found that grant caching, local history retention, redistribution, or re-display. Fixture-backed development may proceed, but public online access remains disabled until that permission is documented.
- Access controls: the app must not bypass authentication, challenges, rate limits, or other access controls and must not persist cookies or sensitive request headers.
- Phase 7 Release enforcement: `AppEnvironment.current()` compiles online access to `false` outside Debug, the Release bundle excludes every development fixture, and Settings/About disclose the same boundary. See `release-checklist.md` and `third-party-notices.md`.

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
| `iq.models[].latest_label` | Pointer into the aligned `labels[]` series | Optional string; when present it must exactly match one label or benchmark projection fails. When absent, Phase 1 deliberately selects the final aligned point because the source arrays are ordered measurement histories; this fallback is covered by a dedicated parser test. |
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
