# R0 Visual Baseline Manifest

Captured 2026-09-04 after commit `f3cc5e7` (C0c fixture routing fix).
Purpose: P0 reskin comparison baseline (`docs/design-qa/baseline/p0-after/`
re-shoots the same matrix; per-pair human comparison tracked in
`docs/design-qa/human-review.md`).

## Capture parameters

- Build: `./Scripts/build-app.sh debug` (fixture UI mode)
- `RADAR_FIXTURE_MODE=ui`, `RADAR_DATA_ROOT=/tmp/AIRadar-Demo` (cleared per shot)
- `RADAR_UI_STATE=fresh|stale`; `RADAR_UI_SOURCE=<station rawValue>`;
  `RADAR_UI_DESTINATION=<Chinese rawValue>` (overview row omits the variable)
- Theme via `defaults write com.acfufu.ClaudeRadar appearance '暗色'|'亮色'`
- `screencapture -l<windowid> -o`; window enumerated via `/tmp/airadar-tools/winlist`
- Window pixel size 2160x1440 or 2478x1758 (Retina 2x; size follows persisted
  split-view layout and drifts between launches — recorded per file below,
  comparison is content-based, not pixel-exact)

## Matrix (18 destination instances x 2 themes x 2 seeds = 72 files)

| Station (RADAR_UI_SOURCE) | Tag | Destination (RADAR_UI_DESTINATION) | Count |
|---|---|---|---|
| (overview; source=claude-code-radar, no DESTINATION) | overview | 信息总览 | 4 |
| claude-code-radar | gailan / juece / moxing / qushi / laiyuan / daochu | 概览 / 决策透镜 / 模型 / 趋势 / 来源状态 / 导出 | 24 |
| codex-radar | gailan / juece / moxing / qushi / zhili / laiyuan / daochu | 概览 / 决策透镜 / 模型 / 趋势 / 智力中心 / 来源状态 / 导出 | 28 |
| swe-bench-verified | bangdan / qushi / laiyuan / daochu | 模型(榜单) / 趋势 / 来源状态(来源与口径) / 导出 | 16 |

File naming: `<source>__<tag>__<theme>__<state>.png` under this directory.

## Exemptions

- SWE-bench "no comparable history" form (3 destinations: 榜单/来源与口径/导出)
  is NOT captured: the ui fixture seeds two benchmark revisions, so
  `hasComparableHistory` is always true and the reduced form is unreachable
  without a DEBUG seed extension (not authorized in R0).

## Known capture caveats

- Window width alternates between 2160 and 2478 px (1239 pt vs 1080 pt
  content views) across launches; every file passed a width>=2000 and
  bytes>=20000 assertion.
- Fresh/stale fixture states share the seed data with different timestamps,
  so some pairs differ only in the "读取于" timestamp text.
