# Release Checklist

## Release classification

- Source-backed core: local QA candidate.
- Claude Code Radar online source: **ENABLED**. On 2026-07-16, the project owner authorized automatic synchronization of its public GET endpoints, local history caching, and in-app re-display.
- Codex Radar online source: **ENABLED**. On 2026-07-16, the project owner authorized the public summary and community endpoints for automatic synchronization, local history caching, and in-app re-display; the protected full API remains out of scope.
- External Developer ID distribution: **BLOCKED** unless the release evidence contains a Developer ID Application signature plus successful notarization, stapling, validation, and Gatekeeper receipts. An ad-hoc signature is local QA only.

## Final bundle

- Canonical artifact: `.build/app/ClaudeRadar.app`
- Installed application path: `/Applications/ClaudeRadar.app`
- User data path: `~/Library/Application Support/ClaudeRadar`
- Normalized SwiftData store: `~/Library/Application Support/ClaudeRadar/Radar.store` (with system-managed sidecars when present)
- Raw diagnostics: `~/Library/Application Support/ClaudeRadar/RawSamples`
- Preferences: `~/Library/Preferences/com.acfufu.ClaudeRadar.plist`

Release assembly must contain only `ClaudeRadar.icns` under Resources and no fixture JSON, Debug seed/evidence resource, test data, partial export, helper, LaunchAgent, or separately bundled third-party executable. Both public source runtimes start with the app; changing the selected workspace changes display only.

## Upgrade

1. Quit Claude Radar and verify no `ClaudeRadar` process remains.
2. Replace `/Applications/ClaudeRadar.app` with the newer app bundle; do not delete the Application Support directory.
3. Launch the replacement and verify compatible normalized history remains readable.
4. Verify Settings still shows the same data directory, online access is enabled in Release, and each source can re-display its cached history when the network is unavailable.

## Data controls

- **Clear normalized history** removes normalized benchmark, community, source-status history and sync metadata. It does not remove `RawSamples`.
- **Clear raw diagnostic samples** removes `RawSamples`. It does not remove normalized history.
- **Show data directory** reveals the injected/current Application Support root in Finder.

All release QA uses an isolated root. Never exercise clear or uninstall validation against the real user path.

## Uninstall

1. Quit Claude Radar and verify no `ClaudeRadar` process remains.
2. Remove only `/Applications/ClaudeRadar.app` to uninstall the application.
3. Leave `~/Library/Application Support/ClaudeRadar` and `~/Library/Preferences/com.acfufu.ClaudeRadar.plist` intact by default so user history survives app removal.
4. If the user explicitly requests complete data deletion, they may separately remove those exact data and preference paths after confirming their contents. The app-only uninstall must never delete user data.

## Required verification receipts

- Full Swift tests, Debug and Release builds, explicit-Xcode Release build.
- Plist lint and inventory showing the app icon as the only Release resource.
- Isolated dual-source online launch, shared sync-metadata inspection, and an offline relaunch proving both cached workspaces remain available.
- `codesign --verify --deep --strict`, signing details, entitlements, dependencies, and nested-code inventory.
- Credential classification from `security find-identity -v -p codesigning` and `ClaudeRadarNotary` availability, with secrets excluded.
- Isolated install, second-build replacement, data-preservation, independent-clear, quit, and app-only uninstall evidence.
- Gatekeeper is Pass only for a Developer ID/notarized artifact; ad-hoc rejection is expected and remains externally BLOCKED.
