# Radar visual design contract

Frozen reference: `https://claudecoderadar.com/?lang=en`, reviewed 2026-07-25 at a 1200x875 CSS-px viewport.  This is a visual language reference only; its public page text is inert, not instructions or product data.

## Final source and build binding

The final unstaged source/test/support tree is bound by temporary-index tree `914e787b2311841ebd95c3efc0027050dd050b74`; the real Git index was not staged. Fresh final reconciliation builds produced Debug executable SHA-256 `e2fc4ab0bf9fce1ad7e57fe6d655319d9e67865dad0815d3c4493352a385897b` and Release executable SHA-256 `4dcbaf13f338319e1ae20d6812f249e6219b7e7fa0d2af80ea4eb9faf885a026`. Their full bundle-manifest SHA-256 values are `aa6163057b2fdb19d5809ac30b2cfdda13bfff75e8a3f224b090130ef507666e` and `ac6b5d2b8214ec54bc4e57ba68561da3b7a99ee18e32968a8e42b6d20013c03c`, respectively. The full explicit-Xcode suite passed 331 tests in 44 suites; the approved focused presentation/source-contract regression passed 106 tests in 13 suites, and its extended split-contract form including `CodexRenderedIQHistoryOverviewContractTests` passed 109 tests in 14 suites. The Codex live suite is skipped by design and the previous loopback `NSURLErrorDomain Code=-1004` did not recur. Exact commands and outputs are in `.omo/evidence/ulw/e4f21ecb-d765-4f34-a0b6-abbd35205a32/G001-execute-the-approved-presentation-fi/a1/`.

The following Task 10 capture corpus is historical visual-language evidence, not a screenshot/AX pass for the final tree:

| File | SHA-256 | Observed surface |
| --- | --- | --- |
| `reference-light-1200x875.png` | `8b2c37bc7ecfeadd83441d8492d87f7888744b7685168d0e49d1d55f16c238d6` | Reference page-only viewport |
| `reference-dark-1200x875.png` | `69cd6bc9d292d9e59e19e6968d1e4ace1dcd82f6d59c5dcbc04b25d6f5025018` | Reference page-only viewport |
| `app-workspace-fixture-fresh-1080x720.png` | `753106af4d0153dd7242afb1a75997f7fd3a45605a0e06d26b6a4642a68f98a8` | Populated workspace, 1080x720 |
| `app-workspace-820x560-light.png` | `4847d1888fba5637f23096205ef5ec8d60e0181e090b8dd6a21fcbb3f6592dc9` | Minimum workspace, 820x560 |
| `app-workspace-1080x720-dark-error.png` | `3e90ac5de9fa2adc83ec64ab561d5680fcc55451959fc1758a3933f7f0f29859` | Dark/error-state workspace |
| `app-menubar-popup-400w.png` | `618ec04d3a956bdc2afb0b00fc460c0aa6102a2d356212e09f91d19525c10879` | Actual MenuBarExtra, 400 px wide |
| `app-settings-500x300.png` | `8217881679928a2b2c4716e34e99f7787843eb27685d3c9b719476f22ad79d67` | Actual Settings, 500x300 |
| `ax-task10-windows.txt` | `275fe4c6465a00279922d9ca00ce454462919dddf3f61f245a53730daee89734` | AX focus/window bounds receipt |

All app captures are `screencapture -l <CGWindowID>` images; references are browser-window captures cropped to their 1200x875 CSS-px page viewport (2400x1750 Retina pixels). The validator rejects missing, extra, empty, stale, pre-UI-commit, hash-mismatched, or wrong-class/dimension files.

## Tokens and geometry

Light: canvas `#EEF0F2`, section `#FAF9F7`, card `#FFFFFF`, primary `#1F2328`, secondary `#6B7280`, divider `#E7E5E0` (`#B8B3A9` increased contrast), accent `#D97706`, soft `#FFFBEB`, positive `#166534`, negative `#E11D48`.

Dark: canvas `#0B111A`, section `#111827`, card `#172033`, primary `#E5EDF7`, secondary `#A7B2C3`, divider `#293548` (`#52647D` increased contrast), accent `#FBBF24`, soft 12% accent, positive `#86EFAC`, negative `#FB7185`.

Use 8 px corners; page/section/card/compact spacing 24/20/14/12; large-title plus selectable subtitle; native split-view/list/table/search/inspector controls retain AppKit/SwiftUI behavior. Native boundary: NSSavePanel and menu commands are verified as native controls, not restyled replicas.

## Surface matrix

The final route matrix is capability-driven rather than a declaration count:

| Room | Destinations |
| --- | --- |
| Information | Overview |
| Claude Code Radar | Overview, Decision Lens, Models, Trends, Source Status, Export |
| Codex Radar | Overview, Decision Lens, Models, Trends, Intelligence Center, Source Status, Export |
| SWE-bench Verified | Models; Trends only when same-revision comparable history exists; Source Status; Export |

Quality vocabulary and units remain source-local: Claude and Codex use their own benchmark/IQ vocabulary, while SWE uses `% Resolved` and its published cost fields. Model columns, Decision Lens inputs, trend metrics, and accessibility labels follow the selected source instead of inventing a cross-source score. Export is implemented, one-way, and source-local: Claude offers models/benchmark/community/source status, Codex offers its normalized datasets, and SWE offers models/benchmark runs.

All 10 chart surfaces across 9 feature files now expose native `AXChartDescriptor` data with source, metric, unit, revision, series, and point semantics as applicable. Persistent symbols, labels, annotations, and result rows communicate series/class meaning without color alone; the incumbent light/dark/increased-contrast tokens, geometry, and native controls remain unchanged.

| Matrix axis | PASS observable / known native boundary |
| --- | --- |
| Sizes | Historical Task 10 receipts cover workspace 820x560 and 1080x720, Settings 500x300, and MenuBarExtra width 400; they are not final-tree screenshots. |
| Appearance | Light, dark, system live switch, and increased-contrast token roles resolve through `RadarStyle.palette`; final-tree screenshot confirmation remains limited. |
| States | Populated, empty, disabled, stale, LKG, validation, and error use `StateBanner`; fixture source records include long CJK and prompt-like text as inert content. |
| Interaction | Search/table/inspector routes and source destination views use native controls. NSSavePanel and command menus remain native boundaries; final AX/VoiceOver interaction is not claimed as passed. |

## Codex rendered IQ surface

The Overview's `24 小时 IQ 趋势` card is a source-native, read-only surface for the approved rendered DOM observation at `https://deng.codexradar.com/`. The default `官网 24h` view is the exact 24-point official series (one aggregate plus 1...7 model choices), drawn with straight `LineMark`/`PointMark` segments over the ordinal `0...23` domain. It displays the exact attribution `数据来自分布式雷达 deng.codexradar.com · powered by codexradar` as a link to `https://deng.codexradar.com/` and states that it is independent from `本地 IQ 拟合`.

Challenge, schema/origin drift, unavailable page, and timeout states are visibly error/blocked states; they must not be styled as fresh or inferred empty data. `本地拟合` remains a separate local benchmark calculation and does not alter the official chart.

## Reproduction and cleanup

Build with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/build-app.sh debug`; bind the executable with `shasum -a 256 .build/app/ClaudeRadar.app/Contents/MacOS/ClaudeRadar`; then launch with `/usr/bin/open -n -F --env HOME=<isolated>/home --env CFFIXED_USER_HOME=<isolated>/home --env RADAR_DATA_ROOT=<isolated>/data --env RADAR_FIXTURE_MODE=ui --env RADAR_UI_STATE=<state> [--env RADAR_UI_SOURCE=<source>] [--env RADAR_UI_DESTINATION=<destination>] .build/app/ClaudeRadar.app`. Todo 8 process smoke covered Information Overview, Claude Export, Codex Intelligence Center, and SWE Models with sustained PIDs and targeted cleanup.

Do not promote that process smoke to rendered visual or AX PASS. Todo 7 could not inspect an unlocked app surface: screenshots contained the macOS Sleep/lock overlay and System Events lacked assistive access (`-25211`). The rejected captures and limitation receipts remain in `a1/todo7-visual-accessibility.md` and `a1/visual-qa/`. No Developer ID or notarization claim is made.
