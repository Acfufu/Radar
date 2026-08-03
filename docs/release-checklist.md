# Release Checklist

## Release classification

- Source-backed core: local QA candidate.
- Claude Code Radar online source: **ENABLED**. On 2026-07-16, the project owner authorized automatic synchronization of its public GET endpoints, local history caching, and in-app re-display.
- Codex Radar online source: **ENABLED**. On 2026-07-16, the project owner authorized the public summary and community endpoints for automatic synchronization, local history caching, and in-app re-display. The approved noncommercial rendered-page path separately reads only warning values visible on the public homepage; it is not official API authorization, and the protected full API remains out of scope.
- Codex rendered 24-hour IQ history: **LIVE READINESS PASS**. The 2026-07-27 anonymous nonpersistent WebKit acceptance produced one aggregate plus four model series with exactly 24 points each, parser revision `codex-radar-rendered-iq-history-v1`, exact origin `https://deng.codexradar.com`, and a verified semantic fingerprint. Receipt: `.omo/evidence/ulw/codex-iq-history-implementation-20260727/G004-debug-release-live/a2/live-anonymous-iq-history.json`. This remains rendered-DOM observation, not API/endpoint/response interception or a license/API permission claim; any challenge, consent, schema/origin drift, navigation failure, bridge failure, or timeout is still BLOCKED rather than empty success.
- SWE-bench Verified online source: **ENABLED**. Radar reads the official published leaderboard, projects only the mini-SWE-agent v2 cohort, and never runs or submits an evaluation.
- External Developer ID distribution: **BLOCKED** unless the release evidence contains a Developer ID Application signature plus successful notarization, stapling, validation, and Gatekeeper receipts. An ad-hoc signature is local QA only.

## Final bundle

- Canonical artifact: `.build/app/ClaudeRadar.app`
- Installed application path: `/Applications/ClaudeRadar.app`
- User data path: `~/Library/Application Support/ClaudeRadar`
- Normalized SwiftData store: `~/Library/Application Support/ClaudeRadar/Radar.store` (with system-managed sidecars when present)
- Raw diagnostics: `~/Library/Application Support/ClaudeRadar/RawSamples`
- Preferences: `~/Library/Preferences/com.acfufu.ClaudeRadar.plist`

Release assembly must contain only `ClaudeRadar.icns` under Resources and no fixture JSON, Debug seed/evidence resource, test data, partial export, helper, LaunchAgent, or separately bundled third-party executable. All three public source runtimes start with the app; changing the selected source room changes display only.

Final route matrix: Information Overview; Claude Overview/Decision Lens/Models/Trends/Source Status/Export; Codex Overview/Decision Lens/Models/Trends/Intelligence Center/Source Status/Export; SWE Models, Trends only when same-revision comparable history exists, Source Status, and Export. Metric vocabulary, units, Decision Lens inputs, trend datasets, accessibility descriptions, and Export choices remain source-local; no route implies a unified cross-source rank.

Final reconciliation local-QA binding: temporary-index source/test/support tree `914e787b2311841ebd95c3efc0027050dd050b74`; Debug executable/bundle-manifest SHA-256 `e2fc4ab0bf9fce1ad7e57fe6d655319d9e67865dad0815d3c4493352a385897b` / `aa6163057b2fdb19d5809ac30b2cfdda13bfff75e8a3f224b090130ef507666e`; Release executable/bundle-manifest SHA-256 `4dcbaf13f338319e1ae20d6812f249e6219b7e7fa0d2af80ea4eb9faf885a026` / `ac6b5d2b8214ec54bc4e57ba68561da3b7a99ee18e32968a8e42b6d20013c03c`. Plist lint and strict codesign pass; Release Resources are icon-only and the signature is ad-hoc hardened runtime.

Current verification disposition is **PASS for the final explicit-Xcode Swift suite**: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test` passed 331 tests in 44 suites; the previous loopback `NSURLErrorDomain Code=-1004` did not recur, and `CodexRenderedIQHistoryLiveTests` is skipped by design. The approved 13-suite presentation/source-contract regression passed 106/106; adding `CodexRenderedIQHistoryOverviewContractTests` passed 109 tests in 14 suites and verifies the split that includes `OfficialOverviewTrendSections.swift`. Isolated Debug process smoke covered Information Overview, Claude Export, Codex Intelligence Center, and SWE Models with targeted PID cleanup. Todo 7 screenshot/AX/VoiceOver completion remains **BLOCKED** because captures showed the macOS Sleep/lock overlay and System Events lacked assistive access (`-25211`).

## Upgrade

1. Quit Claude Radar and verify no `ClaudeRadar` process remains.
2. Replace `/Applications/ClaudeRadar.app` with the newer app bundle; do not delete the Application Support directory.
3. Launch the replacement and verify compatible normalized history remains readable.
4. Verify Settings still shows the same data directory, online access is enabled in Release, and each source can re-display its cached history when the network is unavailable.

## Data controls

- **Clear normalized history** removes normalized benchmark, community, source-status, rendered-warning history, and sync metadata. It also removes `rendered-iq-history` snapshots and their sync metadata. It does not remove `RawSamples`.
- **Clear raw diagnostic samples** removes `RawSamples`. It does not remove normalized history, including rendered-warning snapshots.
- **Show data directory** reveals the injected/current Application Support root in Finder.

All release QA uses an isolated root. Never exercise clear or uninstall validation against the real user path.

## Uninstall

1. Quit Claude Radar and verify no `ClaudeRadar` process remains.
2. Remove only `/Applications/ClaudeRadar.app` to uninstall the application.
3. Leave `~/Library/Application Support/ClaudeRadar` and `~/Library/Preferences/com.acfufu.ClaudeRadar.plist` intact by default so user history survives app removal.
4. If the user explicitly requests complete data deletion, they may separately remove those exact data and preference paths after confirming their contents. The app-only uninstall must never delete user data.

## Required verification receipts

- Full Swift tests with honest failure accounting, approved focused regression, and fresh Debug and Release packaged builds.
- Plist lint and inventory showing the app icon as the only Release resource.
- Isolated three-source online launch, shared sync-metadata inspection, and source-room checks proving that cached data remains isolated.
- Isolated noncommercial Codex page rendering that produces fresh official cards or an explicit rendered empty state. Challenge, schema drift, or page unavailability is **BLOCKED** live readiness, not Pass.
- Isolated noncommercial `deng.codexradar.com` rendering that produces a fresh normalized 24-point IQ snapshot, with exact aggregate/model counts, origin/revision, semantic fingerprint, nonpersistent WebKit receipt, and exact attribution/backlink. A blocked/challenged/drifted/timed-out page is **BLOCKED**, never Pass or an inferred empty result.
- Export inspection proving `rendered-warnings` contains only normalized source/provenance/card fields and no HTML, script, cookies, browser storage/profile, response body, authorization, or endpoint/interception material.
- Export inspection proving `rendered-iq-history` schema version 1 contains only normalized source/provenance/series/point fields, with no HTML, script, cookies, browser storage/profile, response body, authorization, API, or interception material; verify the official curve remains distinct from local IQ fitting.
- SWE-bench live acceptance proving the mini-SWE-agent v2 cohort count, `% Resolved` mapping, 500-task denominator, source-local Pareto analysis, inspector, and permanent read-only/provenance copy.
- `codesign --verify --deep --strict`, signing details, entitlements, dependencies, and nested-code inventory.
- Chart/accessibility contract inspection proving all chart surfaces expose native descriptors and non-color series meaning; rendered screenshot/AX/VoiceOver PASS requires an unlocked owner session with Accessibility permission.
- Credential classification from `security find-identity -v -p codesigning` and `ClaudeRadarNotary` availability, with secrets excluded.
- Isolated install, second-build replacement, data-preservation, independent-clear, quit, and app-only uninstall evidence.
- Gatekeeper is Pass only for a Developer ID/notarized artifact; ad-hoc rejection is expected and remains externally BLOCKED.
