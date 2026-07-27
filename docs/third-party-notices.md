# Third-Party Notices

## Claude Code Radar

Claude Radar identifies [Claude Code Radar](https://claudecoderadar.com/?lang=en) as one of its independent data sources.

The source website and inspected GET endpoints are publicly accessible. On 2026-07-16, the project owner authorized this app's automatic synchronization, local history caching, and re-display of those public responses. Release bundles exclude development fixtures and retain source data only in the app's user-controlled local data and export paths.

This notice is attribution and a release-boundary disclosure. It is not a claim of affiliation, endorsement, or permission from Claude Code Radar.

## Codex Radar

Claude Radar identifies [Codex Radar](https://codexradar.com/) as one of its independent data sources. Where Codex data is displayed, the required attribution is: `数据来自 Codex 雷达 codexradar.com`.

On 2026-07-16, the project owner authorized this app's automatic synchronization, local history caching, and re-display of Codex Radar's public summary and community responses. The project owner also approved noncommercial observation of warning values already rendered on the public homepage. That rendered-DOM path is not official API authorization or a license grant.

The page may make its own JavaScript and subresource requests while rendering. Radar uses nonpersistent WebKit, does not author or intercept those responses, and persists or exports only bounded normalized warning fields. It retains no page HTML, script source, cookies, browser storage/profile, response bodies, credentials, or endpoint/interception material. The official rendered warning and Radar's local IQ fitting remain independent. Codex Radar's public summary separately states that full JSON API access requires authorization; the app does not call or bypass the protected full API.

The same boundary applies to the approved rendered 24-hour IQ history at [deng.codexradar.com](https://deng.codexradar.com/): anonymous, noncommercial, browser-visible DOM observation only, through `WKWebsiteDataStore.nonPersistent()`. The reader does not call or intercept APIs/endpoints or responses and retains no HTML, cookies, profile/storage data, scripts, body text, response bodies, credentials, or interception material. It accepts exactly one aggregate plus one to seven model series, each with exactly 24 visible points, under parser revision `codex-radar-rendered-iq-history-v1`. The normalized `rendered-iq-history` export is schema version 1; official history and the app's `本地 IQ 拟合` are independent. The exact displayed attribution is `数据来自分布式雷达 deng.codexradar.com · powered by codexradar`, linked back to `https://deng.codexradar.com/`.

This notice is attribution and a release-boundary disclosure. It is not a claim of affiliation, endorsement, or permission from Codex Radar.

## SWE-bench

Claude Radar identifies [SWE-bench](https://www.swebench.com/) as one of its independent read-only data sources. The app reads the official website repository's published [`data/leaderboards.json`](https://github.com/SWE-bench/swe-bench.github.io/blob/master/data/leaderboards.json) and displays only the SWE-bench Verified mini-SWE-agent v2 cohort.

Radar does not run the SWE-bench evaluation harness, submit results, download task instances, or write to any SWE-bench system. Upstream source code, data, names, and logos remain governed by their respective upstream terms; this repository does not grant additional reuse rights.

This notice is attribution and a release-boundary disclosure. It is not a claim of affiliation, endorsement, or permission from SWE-bench or Princeton University.

## Apple frameworks

The app uses macOS system frameworks supplied by Apple. No separately bundled third-party executable, framework, helper, or service is included in the Release app.
