<div align="center">

<img alt="Claude Radar app icon" src="Assets/ClaudeRadar.png" width="128" height="128">

# Claude Radar

**A native macOS workspace for reading public model-benchmark snapshots without pretending that unlike sources share one score.**

[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-111111?logo=apple)](Package.swift)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](Package.swift)
[![Published snapshot v0.2.0](https://img.shields.io/badge/published_snapshot-v0.2.0-4C8BF5)](https://github.com/Acfufu/Radar/releases/tag/v0.2.0)

[简体中文](README_zh.md) | English

</div>

Claude Radar is a menu-bar and workspace app for three independent public source rooms: **Claude Code Radar**, **Codex Radar**, and **SWE-bench Verified**. Start in **Information Overview** to see the sources side by side, then open a room for its own vocabulary, history, analysis, and export scope. It deliberately has **no unified ranking, composite score, or cross-source recommendation**.

> [!IMPORTANT]
> Radar reads, validates, stores, analyzes, displays, and exports already-published information. It does not run a benchmark, submit a result, or write to an upstream system.

## What you can inspect

| Source room | Native information | Analysis boundary |
| --- | --- | --- |
| Claude Code Radar | Benchmark, community, and source-status snapshots | Models, histories, trends, derived metrics, and Pareto comparisons remain in this source. |
| Codex Radar | Public summary, community snapshots, and warning values already rendered on the public homepage | Official rendered warnings and local IQ fitting stay independent. The protected full Codex API is excluded: Radar does not request, emulate, retry, or bypass it. |
| SWE-bench Verified | Published `mini-SWE-agent` v2 leaderboard results | `% Resolved`, 500-task counts, cost efficiency, source-local Pareto, and provenance; Radar never runs the evaluator or submits results. |

The information overview keeps these rooms separate. Trends never bridge incompatible source revisions, and a failed refresh keeps the last valid data labeled rather than replacing it with a failure.

## Native workflow

1. Open the workspace from the menu bar and begin at **Information Overview**.
2. Enter a source room to inspect its models or leaderboard, source-scoped history and trends, and source status or SWE-bench methodology.
3. Use source-local metrics and Pareto views to compare only compatible rows.
4. Export the selected source data as a JSON ZIP, or use Settings to clear normalized history and raw diagnostics independently.

Radar stores normalized source snapshots in a local SwiftData store, keeps bounded raw diagnostic samples separately, and writes exports locally. The default data root is:

```text
~/Library/Application Support/ClaudeRadar/
├── Radar.store          # normalized SwiftData history
├── SyncMetadata.json    # source-scoped synchronization metadata
└── RawSamples/          # bounded raw diagnostics
```

Removing the app does not automatically remove this data. The Settings controls keep **Clear normalized history** and **Clear raw diagnostic samples** separate; review an export before sharing it because raw samples and ZIPs can contain upstream-provided content.

The Codex rendered-page reader uses nonpersistent WebKit. Page-owned JavaScript and subresources may render the public page, but Radar does not intercept or retain their responses; only bounded normalized warning fields enter history or the `rendered-warnings` export. No page HTML, scripts, cookies, browser storage/profile, response bodies, credentials, or endpoint material is retained.

## Get a published snapshot

[v0.2.0](https://github.com/Acfufu/Radar/releases/tag/v0.2.0) is the published `bf05ad7` snapshot. It provides an ad-hoc signed local-QA archive, not a Developer ID-signed or notarized distribution.

```bash
curl -LO "https://github.com/Acfufu/Radar/releases/download/v0.2.0/ClaudeRadar-0.2.0-macos.zip"
curl -LO "https://github.com/Acfufu/Radar/releases/download/v0.2.0/ClaudeRadar-0.2.0-macos.zip.sha256"
shasum -a 256 -c ClaudeRadar-0.2.0-macos.zip.sha256
ditto -x -k ClaudeRadar-0.2.0-macos.zip .
open ClaudeRadar.app
```

If macOS blocks a first launch, use Finder’s **Open** command and review the system warning. Current development on `dev` is newer unpublished work; it is not the v0.2.0 download.

## Build the current source

Radar requires **macOS 26+**. The package uses Swift 6 and the repository scripts select Xcode when it is installed at `/Applications/Xcode.app`.

```bash
git clone "https://github.com/Acfufu/Radar.git"
cd Radar
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcrun swift test
./Scripts/build-app.sh debug
RADAR_FIXTURE_MODE="ui" RADAR_DATA_ROOT="/tmp/ClaudeRadar-Demo" \
  .build/app/ClaudeRadar.app/Contents/MacOS/ClaudeRadar
```

The observable Debug-fixture result is a native workspace opening on Information Overview with three independent source cards. The generated bundle is `.build/app/ClaudeRadar.app`.

To exercise the Release build instead, use `./Scripts/build-app.sh release` and open that same bundle. Debug `ui` fixtures are sanitized local data and do not synchronize. Release enables the three documented public source adapters; Debug `RADAR_FIXTURE_MODE="online"` runs those public adapters against an isolated `RADAR_DATA_ROOT`. Neither mode promises network-free operation.

## Data movement and verification boundary

- Published public responses are validated before local persistence. Source identities, history, trends, exports, rankings, and analysis stay source-scoped.
- Release contains the app icon but no fixture or Debug-QA resources. Its approved public sources synchronize at startup and on the configured schedule.
- Normalized history, raw diagnostics, preferences, and exported archives stay on the Mac unless you move or share them.
- Codex Radar’s public summary and community endpoints are in scope; its credential-protected full API is not.
- The current source and the v0.2.0 snapshot are different release states. Build current development work from source rather than treating the archived download as current.

For source contracts and operational detail, see [the source contract](docs/source-contract.md), [release checklist](docs/release-checklist.md), and [implementation status](docs/implementation-status.md).

## Attribution and license

Radar is not affiliated with or endorsed by Claude Code Radar, Codex Radar, SWE-bench, or Princeton University. The exact upstream attribution and reuse boundaries are in [third-party notices](docs/third-party-notices.md).

No license file is present. No permission to reuse or redistribute this repository is granted unless its owner explicitly says so.
