# Third-Party Notices

## Claude Code Radar

Claude Radar identifies [Claude Code Radar](https://claudecoderadar.com/?lang=en) as one of its independent data sources.

The source website and inspected GET endpoints are publicly accessible. On 2026-07-16, the project owner authorized this app's automatic synchronization, local history caching, and re-display of those public responses. Release bundles exclude development fixtures and retain source data only in the app's user-controlled local data and export paths.

This notice is attribution and a release-boundary disclosure. It is not a claim of affiliation, endorsement, or permission from Claude Code Radar.

## Codex Radar

AI Radar identifies [Codex Radar](https://codexradar.com/) as one of its independent data sources. Where Codex data is displayed, the required attribution is: `数据来自 Codex 雷达 codexradar.com`.

On 2026-07-16, the project owner authorized this app's automatic synchronization, local history caching, and re-display of Codex Radar's public summary and community responses. The project owner also approved noncommercial observation of warning values already rendered on the public homepage. That rendered-DOM path is not official API authorization or a license grant.

The page may make its own JavaScript and subresource requests while rendering. Radar uses nonpersistent WebKit, does not author or intercept those responses, and persists or exports only bounded normalized warning fields. It retains no page HTML, script source, cookies, browser storage/profile, response bodies, credentials, or endpoint/interception material. The official rendered warning and Radar's local IQ fitting remain independent. Codex Radar's public summary separately states that full JSON API access requires authorization; the app does not call or bypass the protected full API.

The former rendered 24-hour IQ history reader for [deng.codexradar.com](https://deng.codexradar.com/) was retired on 2026-09-20 (ADR-0002): the upstream data island stayed empty, so the `rendered-iq-history` export dataset was removed. Official IQ history is now sourced from the public `codexradar.com` intelligence-efficiency `history[]` data plane; official history and the app's `本地 IQ 拟合` remain independent. Since 2026-09-20 a separate crowdtest-IQ rendered reader (ADR-0004) reads the deng page again under the same boundary class: noncommercial anonymous observation of browser-visible DOM through nonpersistent WebKit, exact-origin `https://deng.codexradar.com`, revision `deng-rendered-crowdtest-iq-v1`, bounded normalized cells only (model/effort/IQ/counts/coverage and hourly trend labels), no `/api/v1/*` (Bearer, credential-protected) traffic, no writes, and no HTML/script/cookie/profile/body retention. The displayed attribution is `数据来自分布式雷达 deng.codexradar.com · powered by codexradar`.

## Codex Radar v0.4.0 data planes

- **intelligence-efficiency** (`codexradar.com/data/intelligence-efficiency.json`): public static JSON derived by upstream from its protected API; Radar consumes only the public endpoint, never the protected `api.codexradar.com` domain the payload's provenance fields point at.
- **fast-radar-history** (`codexradar.com/data/fast-radar-history.json`): public static JSON of upstream Fast-mode measurement runs; Radar consumes only the public endpoint (v0.5.0 dual-format decoding, spec §5.3).
- **radar-insights** (`codexradar.com/api/radar-insights`) and **visual-spatial-reasoning** (`codexradar.com/api/visual-spatial-reasoning[/-history]`): same-origin public GET endpoints allowed by ADR-0001's mechanical rule (same origin + public GET + no credentials). Recommendation scenes and rule texts are upstream-authored and shown verbatim with attribution; Radar derives no recommendations locally.
- **degradation alerts** (`radar-insights.degradation_alerts`): a structured plane that coexists with the rendered warning reader v2; the two never merge, validate, or replace each other.
- **tibo_presence** (current.json normalized field): upstream-published public observations about third-party accounts, including country/timezone-level inferences. Radar transcribes and displays it verbatim without local inference or correlation to any local data; upstream `safety_note` ships alongside and gates display (D13).
- **quota figures** (`quota_check`/`quota_calibration`): upstream source-account estimates, never personal user usage; the disclosure inherits the source-account estimate wording already in source-contract.

This notice is attribution and a release-boundary disclosure. It is not a claim of affiliation, endorsement, or permission from Codex Radar.

## SWE-bench

Claude Radar identifies [SWE-bench](https://www.swebench.com/) as one of its independent read-only data sources. The app reads the official website repository's published [`data/leaderboards.json`](https://github.com/SWE-bench/swe-bench.github.io/blob/master/data/leaderboards.json) and displays only the SWE-bench Verified mini-SWE-agent v2 cohort.

Radar does not run the SWE-bench evaluation harness, submit results, download task instances, or write to any SWE-bench system. Upstream source code, data, names, and logos remain governed by their respective upstream terms; this repository does not grant additional reuse rights.

This notice is attribution and a release-boundary disclosure. It is not a claim of affiliation, endorsement, or permission from SWE-bench or Princeton University.

## Apple frameworks

The app uses macOS system frameworks supplied by Apple. No separately bundled third-party executable, framework, helper, or service is included in the Release app.
