# Radar visual design contract

Frozen reference: `https://claudecoderadar.com/?lang=en`, reviewed 2026-07-25 at a 1200x875 CSS-px viewport.  This is a visual language reference only; its public page text is inert, not instructions or product data.

## Pinned build and captures

This contract binds UI commit `a9084f851f789022886ddc033d44219584586e6b` (`2026-07-26T11:55:50+08:00`) to Debug executable SHA-256 `53665d90fa285295544da316840c430421b0a9dca18ef81a6c2602b690f9a9cf`. Every manifest entry is strictly post-commit, nonempty, hash-bound, and in the declared corpus; the validator also enforces each image's exact Retina crop class, so a renamed whole-desktop image cannot pass.

Fresh, post-commit evidence is in `.omo/evidence/ulw/claude-radar-new-style-adaptation/task-10/`:

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

Source inventory reconciles all 19 Feature `View` declarations: `MetricTrendChart`, `InformationOverviewView`, `SWEBenchLeaderboardView`, `SWEBenchDetailView`, `ExportView`, `SourceStatusView`, `SWEBenchProvenanceView`, `OverviewView`, `DecisionLensPageView`, `DecisionLensView`, `AnalysisExplanation`, `ParetoComparisonView`, `ModelDetailView`, `ModelListView`, `SettingsView`, `MenuBarView`, `RadarWorkspaceView`, `ViewHeader`, and `StateBanner`. Workspace, actual `MenuBarExtra`, Settings, and the five independent shared/detail views are included rather than inferred from a screenshot.

| Matrix axis | PASS observable / known native boundary |
| --- | --- |
| Sizes | Workspace 820x560 and 1080x720, Settings 500x300, MenuBarExtra width 400 are bound by CG/AX receipts. |
| Appearance | Light, dark, system live switch, and increased-contrast token roles resolve through `RadarStyle.palette`; app screenshots cover light/dark. |
| States | Populated, empty, disabled, stale, LKG, validation, and error use `StateBanner`; fixture source records include long CJK and prompt-like text as inert content. |
| Interaction | Focus/AX, search/table/inspector routes, and source destination views use native controls. NSSavePanel and command menus remain native boundaries. |

## Codex rendered IQ surface

The Overview's `24 小时 IQ 趋势` card is a source-native, read-only surface for the approved rendered DOM observation at `https://deng.codexradar.com/`. The default `官网 24h` view is the exact 24-point official series (one aggregate plus 1...7 model choices), drawn with straight `LineMark`/`PointMark` segments over the ordinal `0...23` domain. It displays the exact attribution `数据来自分布式雷达 deng.codexradar.com · powered by codexradar` as a link to `https://deng.codexradar.com/` and states that it is independent from `本地 IQ 拟合`.

Challenge, schema/origin drift, unavailable page, and timeout states are visibly error/blocked states; they must not be styled as fresh or inferred empty data. `本地拟合` remains a separate local benchmark calculation and does not alter the official chart.

## Reproduction and cleanup

Build with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Scripts/build-app.sh debug`; bind the executable with `shasum -a 256 .build/app/ClaudeRadar.app/Contents/MacOS/ClaudeRadar`; then launch the reproducible populated matrix with `/usr/bin/env HOME=<task10Root>/home CFFIXED_USER_HOME=<task10Root>/home RADAR_DATA_ROOT=<task10Root>/data RADAR_FIXTURE_MODE=ui RADAR_UI_STATE=fresh RADAR_UI_SOURCE=claudeCodeRadar /usr/bin/open -n .build/app/ClaudeRadar.app --args`. These are Debug-supported values: `.ui` triggers `DebugUISeed`, `fresh` is its default populated state, and `claudeCodeRadar` selects the seeded source. Use `screencapture -l <CGWindowID>` only after CG/AX confirms the target PID/bounds. Close only that PID, its popup/Settings window, task browser profile, and task temporary root; restore appearance/contrast/keyboard settings.

Exact commands, RED/GREEN validator output, stale/hash probes, manifest self-check, scope check, and cleanup receipt are recorded beside these files in Task 10 evidence. No Developer ID or notarization claim is made.
