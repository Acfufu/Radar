# Radar Overview Design QA

## Verified surface

The current overview was inspected at a 1440 × 1024 pt viewport in macOS dark appearance with live Codex Radar data, the highest-quality goal, and the 20x Pro plan selected.

1. Peak IQ and the 24-hour signal occupy the primary hero.
2. Model-family health, the reasoning-tier heatmap, and subscription context form the second row.
3. Goal selection, model comparison, and the recommendation share one decision-lens surface.
4. Recent performance and live synchronization monitoring close the page.

## Data behavior

- The heatmap renders available family/tier combinations and uses dashes for unavailable tiers.
- The recommendation repeats the selected model's measured IQ, pass count, cost, and duration.
- The source timestamp uses `monitored_at`; a first-run history asks for more synchronization points instead of fabricating a trend.
- Plus, 5x Pro, and 20x Pro remain selectable, and the quota estimate is labeled as public measured context.
- Recent performance shows the five strongest current models, compatible-snapshot deltas, per-task cost, and average duration.
- Live monitoring shows source health, last synchronization age, the configured refresh interval, retained snapshot count, progress, and the next automatic check.

## Interaction verification

- The native source picker switched between independent Claude Code Radar and Codex Radar workspaces.
- All four decision goals were exercised and have focused recommendation coverage.
- The native subscription selector exposes Plus, 5x Pro, and 20x Pro.
- A manual refresh returned the live monitor to “刚刚”; unchanged source content remained one deduplicated snapshot.
- Light, dark, and system appearances were rendered, and appearance persistence has focused settings coverage.

## Result

No blocking visual defect remains at the target viewport. Text is uncropped, card boundaries are stable, and the required overview surfaces remain legible.
