# Release Checklist

## Release classification

- Source-backed core: local QA candidate.
- Claude Code Radar online source: **ENABLED in current code; current live-provider validation not claimed**. Historical authorization record (2026-07-16): the project owner authorized automatic synchronization of its public GET endpoints, local history caching, and in-app re-display. This dated record is preserved for provenance, not as a current external-authorization receipt.
- Codex Radar online source: **ENABLED in current code; current live-provider validation not claimed**. Historical authorization record (2026-07-16) covers the public summary and community endpoints. The approved noncommercial rendered-page path is historical contract evidence; it separately reads only warning values visible on the public homepage, is not official API authorization, and the protected full API remains out of scope.
- Codex rendered 24-hour IQ history: **RETIRED 2026-09-20** (ADR-0002). The deng v1 reader, its export dataset, and its receipts are removed. The official IQ history card is sourced from the public intelligence-efficiency `history[]` plane instead.
- deng crowdtest IQ rendered reader: **RETIRED (hard) 2026-10-27** (ADR-0006, v0.6.0/grill G3). deng.codexradar.com was rebuilt into the「速蹬雷达」realtime ladder through a new `speed-api.codexradar.com` origin; the frozen `deng-rendered-crowdtest-iq-v1` contract lost all eight anchor classes with no migration trace. Reader trio, station cards, SwiftData entity, dataset type, fixtures, and tests removed. The deng domain and `speed-api.codexradar.com` both stay outside Radar's request scope. (Was NEW 2026-09-20 per ADR-0004.)
- Rendered degradation-warning reader: **SOFT-RETIRED, executed in v0.6.0** (ADR-0005, grill G4). Production scheduling stops at the app entry; both rendered card mounts are gated (`CodexRenderedWarningSoftRetire.isActive`); reader/contract/fixtures/tests kept for a one-line unfreeze. The structured (radar-insights JSON) alerts path carries the warning plane alone. The 2026-10-27 re-probe closed the thaw-as-is path (server markers shrank 2/4/2 → 2/1/1).
- v0.4.0 sidecars: radar-insights (`/api/radar-insights`) and visual-spatial-reasoning (`/api/visual-spatial-reasoning[/-history]`) under the ADR-0001 same-origin public GET rule; whitelist view stations (DSH/ZCode/Grok, ADR-0003) share the intelligence-efficiency sidecar — no independent sync. **2026-10-27 (spec v1.4, grill G5): all three endpoints returned 502 online — DEFERRED online acceptance until recovery; re-probe the schema on recovery before any contract change.**
- v0.5.0 changes (spec v1.3, issue #4): the Fast Radar page returns to navigation (spec §5.3 v1.3 note) with dual-format tolerant decoding of `/data/fast-radar-history.json` (legacy trio + active per-model `gpt-6-astra` shape); unified data-age badges (`DataAgeBadge`) annotate the quota-radar, comparisons, and monitored-at fields of current.json; whitelist check-set re-probed 2026-09-23 — constants unchanged.
- v0.6.0 changes (spec v1.4, issue #6): 额度雷达 degrades to two verbatim cards (quota_check「当前核查」+ quota_calibration「校准信息」, per-field `checked_at` age badges) after the upstream schema-3 plans-matrix rebuild — `rows`/`trend`/`updated_at` gone, DTO made Optional-tolerant, plans matrix not consumed; ie sidecar cap 8MiB→16MiB (measured 9.7MB payload, Fast-Radar keeps 8MiB); crowdtest IQ hard retirement (above); rendered-warning soft-retirement executed (above); Kimi placeholder maintained (upstream removed its own placeholder menu — not a counter-signal, grill G9).
- Manual UA/version step: the `AIRadar/0.6.0 (macOS; +https://github.com/Acfufu/Radar)` literal is pinned in the five HTTP adapters (ClaudeCodeRadarHTTP, IntelligenceEfficiency, FastRadarHistory, RadarInsights, VisualSpatialReasoning) and asserted by contract tests — step the version string together with the plist at every release.
- SWE-bench Verified online source: **ENABLED in current code; current live-provider validation not claimed**. Radar reads the official published leaderboard, projects only the mini-SWE-agent v2 cohort, and never runs or submits an evaluation.
- External Developer ID distribution: **BLOCKED** unless the release evidence contains a Developer ID Application signature plus successful notarization, stapling, validation, and Gatekeeper receipts. An ad-hoc signature is local QA only.

## Final bundle

- Canonical artifact: `.build/app/AIRadar.app`
- Installed application path: `/Applications/AIRadar.app`
- User data path: `~/Library/Application Support/ClaudeRadar`
- Normalized SwiftData store: `~/Library/Application Support/ClaudeRadar/Radar.store` (with system-managed sidecars when present)
- Raw diagnostics: `~/Library/Application Support/ClaudeRadar/RawSamples`
- Preferences: `~/Library/Preferences/com.acfufu.ClaudeRadar.plist`

Release assembly must contain only `AIRadar.icns` under Resources and no fixture JSON, Debug seed/evidence resource, test data, partial export, helper, LaunchAgent, or separately bundled third-party executable. All three public source runtimes start with the app; changing the selected source room changes display only.

Final route matrix (v0.6.0): 聚合站 Information Overview (incl. the cross-station comparison view; no banner, no export, D10; rendered-warning card hidden per ADR-0005 execution); Claude Code Overview/Decision Lens/Models/Trends/Source Status/Export (the overview crowdtest IQ card is removed with the ADR-0006 retirement); Codex 速览排行(三能力 tab + 官网 IQ 趋势卡; the crowdtest IQ card is removed)/预警与推荐(结构化卡 alone — the rendered warning card is hidden, ADR-0005)/效能 PK/额度雷达(「当前核查」+「校准信息」two verbatim cards with per-field checked_at age badges; the trend chart and three-tier estimate rows retired with the upstream schema-3 rebuild)/历史对比/Tibo 雷达/社区入口/决策透镜/趋势/来源状态/导出; Fast 雷达 between 额度雷达 and 历史对比 (dual-format page, spec §5.3 v1.3, unchanged in v0.6.0); DSH/ZCode/Grok single 效能排行 pages (whitelist-cropped, crowdtest IQ cards removed); Kimi 即将开放 placeholder; SWE Models, Trends only when same-revision comparable history exists, Source Status, and Export. Metric vocabulary, units, Decision Lens inputs, trend datasets, accessibility descriptions, and Export choices remain source-local; no route implies a unified cross-source rank.

Historical local-QA binding (preserved, not current G033 artifact evidence): temporary-index source/test/support tree `914e787b2311841ebd95c3efc0027050dd050b74`; Debug executable/bundle-manifest SHA-256 `e2fc4ab0bf9fce1ad7e57fe6d655319d9e67865dad0815d3c4493352a385897b` / `aa6163057b2fdb19d5809ac30b2cfdda13bfff75e8a3f224b090130ef507666e`; Release executable/bundle-manifest SHA-256 `4dcbaf13f338319e1ae20d6812f249e6219b7e7fa0d2af80ea4eb9faf885a026` / `ac6b5d2b8214ec54bc4e57ba68561da3b7a99ee18e32968a8e42b6d20013c03c`. The dated receipt records plist lint, strict codesign, icon-only Resources, and an ad-hoc hardened-runtime signature; no current artifact receipt is claimed here.

Current G033 source-test verification passes: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --filter 'ReleaseReadinessTests|Phase4SourceContractTests'` passed 12 tests in 2 suites (exit 0), and the required default `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test` passed 364 tests in 46 suites (exit 0). This task does not claim current live-provider, packaged-app, screenshot/AX/VoiceOver, Developer ID, notarization, stapling, or Gatekeeper validation.

## Upgrade

1. Quit AI Radar and verify no `AIRadar` process remains.
2. Replace `/Applications/AIRadar.app` with the newer app bundle; do not delete the Application Support directory.
3. Launch the replacement and verify compatible normalized history remains readable.
4. Verify Settings still shows the same data directory, online access is enabled in Release, and each source can re-display its cached history when the network is unavailable.

## Data controls

- **Clear normalized history** removes only the selected source's normalized benchmark, community, source-status, rendered-warning history, radar-insights, visual-spatial-reasoning, and sync metadata. Sibling-source normalized data and all `RawSamples` remain; a later legitimate synchronization may repopulate the selected source.
- **Clear raw diagnostic samples** removes `RawSamples` globally and independently. It does not remove normalized history for any source, including rendered-warning snapshots.
- **Show data directory** reveals the injected/current Application Support root in Finder.

All release QA uses an isolated root. Never exercise clear or uninstall validation against the real user path.

## Uninstall

1. Quit AI Radar and verify no `AIRadar` process remains.
2. Remove only `/Applications/AIRadar.app` to uninstall the application.
3. Leave `~/Library/Application Support/ClaudeRadar` and `~/Library/Preferences/com.acfufu.ClaudeRadar.plist` intact by default so user history survives app removal.
4. If the user explicitly requests complete data deletion, they may separately remove those exact data and preference paths after confirming their contents. The app-only uninstall must never delete user data.

## Release assets (v0.6.0; pattern since v0.5.0)

1. Confirm the version surface: plist `CFBundleShortVersionString` = 0.6.0, `CFBundleVersion` = 5; the `AIRadar/0.6.0` UA literal pinned in the five adapters (zero `AIRadar/0.5.0` remnants).
2. Build the release bundle: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/build-app.sh release` (ad-hoc hardened-runtime signature; Resources contain only `AIRadar.icns`).
3. Package: `cd .build/app && ditto -c -k --sequesterRsrc --keepParent AIRadar.app AIRadar-0.6.0-macos.zip && shasum -a 256 AIRadar-0.6.0-macos.zip > AIRadar-0.6.0-macos.zip.sha256`.
4. Publish (after the human gate): push `main`, `git tag v0.6.0` + push, `gh release create v0.6.0 --title "v0.6.0" --notes …` attaching both files; then swap the README/README_zh snapshot block to the v0.6.0 assets.
5. The archive stays ad-hoc signed — local QA only; Developer ID/notarization remains blocked (below).

## Required verification receipts

- Full Swift tests with honest failure accounting, approved focused regression, and fresh Debug and Release packaged builds.
- Plist lint and inventory showing the app icon as the only Release resource.
- Isolated three-source online launch, shared sync-metadata inspection, and source-room checks proving that cached data remains isolated.
- Isolated noncommercial Codex page rendering that produces fresh official cards or an explicit rendered empty state. Challenge, schema drift, or page unavailability is **BLOCKED** live readiness, not Pass.
- Online QA for the v0.5.0 planes (isolated `RADAR_DATA_ROOT`): after a live sync, SyncMetadata shows `fast-radar-history` `lastSuccessfulAt` non-nil with `FastRadarRunEntity` counts ≥ the upstream run total (119 at the 2026-09-22 freeze, legacy + per-model shapes); the Fast 雷达 page lists astra effort rows and the data-age badges render on 额度雷达 / 速览排行 / 历史对比.
- Online QA for the v0.6.0 planes (isolated `RADAR_DATA_ROOT`): after a live sync, SyncMetadata shows `codex|current` success (the schema-3 quota payload decodes — pre-fix it failed wholesale) and `intelligence-efficiency` success under the 16MiB cap (9.7MB at the 2026-10-27 freeze); the 额度雷达 page renders the two verbatim cards with their checked_at age badges; SyncMetadata records **no** `rendered-warnings` new sync attempts (soft-retired) and no crowdtest dataset rows. **radar-insights / visual-spatial-reasoning online acceptance is DEFERRED (grill G5): all three endpoints returned 502 at the 2026-10-27 recon — final-state failure with LKG retention is the expected behavior; re-probe the schema before any contract change on recovery.**
- Online QA for the v0.4.0 planes (isolated `RADAR_DATA_ROOT`): after a live sync, SyncMetadata shows `radar-insights` and `visual-spatial-reasoning` `lastSuccessfulAt` non-nil with entity counts > 0 (DEFERRED while the 502 outage holds, see above); the DSH/ZCode/Grok ranking pages and the aggregate comparison view show rows; the official IQ trend card renders series from `ie.json history[]`.
- No deng traffic at all (v0.6.0): the crowdtest rendered reader is removed with the ADR-0006 retirement; the transport/contract tests and a Release-binary marker scan confirm the `deng-rendered-crowdtest-iq` dataset name and the `crowdtestIQ` dataset case are absent, and no request path exists for deng.codexradar.com or speed-api.codexradar.com.
- Export inspection proving `rendered-warnings` contains only normalized source/provenance/card fields and no HTML, script, cookies, browser storage/profile, response body, authorization, or endpoint/interception material.
- No deng traffic remains at all: the v1 reader retired 2026-09-20 (ADR-0002) and the crowdtest reader retired 2026-10-27 (ADR-0006); contract tests plus a Release-binary marker scan confirm both dataset names and export cases are absent.
- SWE-bench live acceptance proving the mini-SWE-agent v2 cohort count, `% Resolved` mapping, 500-task denominator, source-local Pareto analysis, inspector, and permanent read-only/provenance copy.
- `codesign --verify --deep --strict`, signing details, entitlements, dependencies, and nested-code inventory.
- Chart/accessibility contract inspection proving all chart surfaces expose native descriptors and non-color series meaning; rendered screenshot/AX/VoiceOver PASS requires an unlocked owner session with Accessibility permission.
- Credential classification from `security find-identity -v -p codesigning` and `ClaudeRadarNotary` availability, with secrets excluded.
- Isolated install, second-build replacement, data-preservation, independent-clear, quit, and app-only uninstall evidence.
- Gatekeeper is Pass only for a Developer ID/notarized artifact; ad-hoc rejection is expected and remains externally BLOCKED.

## P2 online QA steps (recorded 2026-09-05)

Executed per commit during P2①–⑤ (fixed-field receipts live in each commit
message; this section records the re-runnable steps, it does not replace
those receipts).

1. Isolated online sync: launch with `RADAR_FIXTURE_MODE=online
   RADAR_DATA_ROOT="$TMPDIR/AIRadar-OnlineQA-<phase>"`, wait ≤120 s for the
   `SyncMetadata.json` rows `codex-radar|intelligence-efficiency`,
   `codex-radar|fast-radar-history`, `codex-radar|source-status`, and
   `codex-radar|community` to gain a non-nil `lastSuccessfulAt`, quit the
   app, then verify store entity counts (`ZINTELLIGENCEEFFICIENCYSNAPSHOTENTITY`,
   `ZFASTRADARRUNENTITY`, `ZCODERADARSTATUSSNAPSHOTENTITY` > 0) and that the
   community blob contains `group`/`history` but zero `my_scores`
   occurrences (D12). Delete the QA data root afterwards.
2. Programmatic export (P2⑤): relaunch with `RADAR_UI_EXPORT_DESTINATION=
   /tmp/out.zip RADAR_UI_SOURCE=codexRadar RADAR_UI_DESTINATION=导出`, press
   导出 ZIP…, then verify `manifest.json` lists `codex-station-status`,
   `intelligence-efficiency`, and `fast-radar-history` at schemaVersion 1
   (additive expansion does not bump the version, spec §5.1/§5.5).
3. The rendered-reader live readiness steps above remain BLOCKED-gated and
   are unchanged by P2.
