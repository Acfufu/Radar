<!-- markdownlint-disable -->

<div align="center">

# Claude Radar

<div>
  <img alt="Platform: macOS 26 or later" src="https://img.shields.io/badge/macOS-26%2B-111111?logo=apple">
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white">
  <img alt="Version 0.1.0" src="https://img.shields.io/badge/version-0.1.0-4C8BF5">
  <img alt="Status: local QA preview" src="https://img.shields.io/badge/status-local_QA_preview-D97706">
</div>

<br>

[简体中文](README_zh.md) | English

A native macOS workspace for inspecting model benchmark snapshots, trends, source health, and reproducible exports.

Claude Radar turns Claude Code Radar-compatible snapshot data into a menu bar summary and a detailed SwiftUI workspace. The current repository is a **fixture-backed local QA preview**: public Release builds intentionally keep online collection disabled until upstream reuse permission is documented.

</div>

<!-- markdownlint-restore -->

## Install

Claude Radar currently ships from source and requires macOS 26 or later with Xcode 26 and Swift 6.2.

```bash
git clone "https://github.com/Acfufu/Radar.git"
cd Radar
./Scripts/build-app.sh release
open .build/app/ClaudeRadar.app
```

The generated app is ad-hoc signed for local use. It is not notarized for external distribution.

## Highlights

- Summarizes model count, quality, cost efficiency, source revision, quota estimates, and quality/cost Pareto frontiers.
- Browses model metrics with search, sorting, dynamic columns, and per-model detail.
- Charts historical quality, cost, token, and duration trends without joining incompatible source revisions.
- Keeps benchmark, community-rating, and source-status segments independent so one failed segment does not erase the others.
- Preserves normalized history and bounded raw diagnostic samples locally with explicit deletion controls.
- Exports selected datasets to a paginated JSON ZIP with a manifest, optional date limits, and opt-in raw samples.
- Stays available from the menu bar after the main workspace closes and can register itself as a login item.

## Use

The Release build opens the full workspace, but its online source is disabled and a fresh install therefore contains no benchmark data. To exercise the implemented product surface with sanitized development fixtures:

```bash
./Scripts/build-app.sh debug
RADAR_FIXTURE_MODE="ui" \
RADAR_DATA_ROOT="/tmp/ClaudeRadar-Demo" \
.build/app/ClaudeRadar.app/Contents/MacOS/ClaudeRadar
```

Use the sidebar to open Overview, Models, Trends, Source Status, and Export. The menu bar scope icon provides a compact quality summary and can reopen the workspace.

For the deterministic synchronization sequence used by runtime QA, replace `RADAR_FIXTURE_MODE="ui"` with `RADAR_FIXTURE_MODE="sequence"` and use a fresh `RADAR_DATA_ROOT`.

## Data And Export

Claude Radar stores its normal local data under:

```text
~/Library/Application Support/ClaudeRadar/
├── Radar.store
└── RawSamples/
```

Exports can contain models, benchmark runs, community ratings, source status, and optionally the currently retained raw samples. Each ZIP contains paginated JSON files plus `manifest.json`; page size and date bounds are configurable in the Export view.

Settings provides separate actions for clearing normalized history and raw diagnostic samples. Removing the application does not automatically remove either dataset.

## Privacy And Permissions

- Release builds do not contact the Claude Code Radar endpoints.
- Debug sequence mode uses the configured public endpoints only as part of local development QA; the shipped fixtures are hand-sanitized.
- Normalized history, raw samples, preferences, and exports remain on the Mac unless the user moves or shares them.
- Raw samples and exported archives may contain source-provided content. Review them before sharing and keep raw export disabled when it is unnecessary.
- The app uses macOS Service Management only when the user enables **Launch at Login**.

## Compatibility And Limitations

- Requires macOS 26 or later; there is no Windows, Linux, iOS, or web build.
- Version `0.1.0` is a local QA preview, not a notarized public release.
- Public online collection is blocked because no affirmative upstream permission for caching, historical retention, redistribution, or re-display has been documented.
- Release builds intentionally exclude fixture JSON and Debug QA resources. A fresh Release build is therefore an empty local workspace until an authorized data path exists.
- Community ratings and quota estimates are source-reported context; they do not alter benchmark quality, derived metrics, or Pareto calculations.

## Develop

Build and test with the repository scripts and Swift Package Manager:

```bash
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" swift test
./Scripts/build-app.sh debug
./script/build_and_run.sh --verify
```

Useful commands:

```bash
./script/build_and_run.sh run
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
```

The Swift package has no third-party package dependencies. Architecture and release evidence are documented in [`docs/implementation-status.md`](docs/implementation-status.md), [`docs/source-contract.md`](docs/source-contract.md), and [`docs/release-checklist.md`](docs/release-checklist.md).

## Security

Claude Radar validates source payloads before persistence, stores diagnostics under an app-specific data root, and creates exports through a temporary package before installing the final ZIP. Treat the local data directory and exported archives as potentially sensitive. Do not run destructive data-control QA against your real Application Support directory; use an isolated `RADAR_DATA_ROOT` in Debug builds.

## Third-Party Data

Claude Radar is not affiliated with or endorsed by Claude Code Radar. See [`docs/third-party-notices.md`](docs/third-party-notices.md) for the attribution and current reuse boundary.

## License Status

No license has been specified yet. Do not assume reuse rights beyond what the repository owner explicitly grants.
