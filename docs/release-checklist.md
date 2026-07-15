# Release Checklist

## Release classification

- Fixture-backed core: local QA candidate.
- Public online source: **BLOCKED**. The source is publicly accessible, but no affirmative permission for caching, history retention, redistribution, or re-display has been documented. Release keeps it disabled at compile time.
- External Developer ID distribution: **BLOCKED** unless the release evidence contains a Developer ID Application signature plus successful notarization, stapling, validation, and Gatekeeper receipts. An ad-hoc signature is local QA only.

## Final bundle

- Canonical artifact: `.build/app/ClaudeRadar.app`
- Installed application path: `/Applications/ClaudeRadar.app`
- User data path: `~/Library/Application Support/ClaudeRadar`
- Normalized SwiftData store: `~/Library/Application Support/ClaudeRadar/Radar.store` (with system-managed sidecars when present)
- Raw diagnostics: `~/Library/Application Support/ClaudeRadar/RawSamples`
- Preferences: `~/Library/Preferences/com.acfufu.ClaudeRadar.plist`

Release assembly must contain no fixture JSON, Debug seed/evidence resource, test data, partial export, helper, LaunchAgent, or separately bundled third-party executable. The online source must remain disabled unless ADR-011 permission is documented before rebuilding.

## Upgrade

1. Quit Claude Radar and verify no `ClaudeRadar` process remains.
2. Replace `/Applications/ClaudeRadar.app` with the newer app bundle; do not delete the Application Support directory.
3. Launch the replacement and verify compatible normalized history remains readable.
4. Verify Settings still shows the same data directory and that online access remains disabled in Release.

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
- Plist lint and inventory showing no Release fixture/test resources.
- `codesign --verify --deep --strict`, signing details, entitlements, dependencies, and nested-code inventory.
- Credential classification from `security find-identity -v -p codesigning` and `ClaudeRadarNotary` availability, with secrets excluded.
- Isolated install, second-build replacement, data-preservation, independent-clear, quit, and app-only uninstall evidence.
- Gatekeeper is Pass only for a Developer ID/notarized artifact; ad-hoc rejection is expected and remains externally BLOCKED.
