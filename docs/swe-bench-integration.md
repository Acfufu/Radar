# SWE-bench Integration Exploration

As of 2026-07-19. Implemented in the current working tree.

## Decision

The best next source for Radar is the **SWE-bench Verified model comparison shown by default on swebench.com: mini-SWE-agent v2**, not the raw SWE-bench issue corpus and not the heterogeneous “all agents” leaderboard.

Implementation status: the two planned stages are complete. Stage 1 adds the global information overview and visible source rooms while preserving source-native semantics. Stage 2 adds the official SWE-bench adapter, validated projection, leaderboard, inspector, provenance page, source-local analysis, cache/history/export integration, and focused regressions.

This cohort is already a model-level comparison under one agent baseline, so it maps cleanly to Radar's existing `BenchmarkDataset`:

- one independent source: `swe-bench-verified-mini-v2`;
- one row per unique leaderboard submission;
- `% Resolved` as the quality score;
- 500 as the valid-task count;
- total run cost when the source publishes it;
- no cross-source joins with Claude Code Radar or Codex Radar.

The official site itself selects mini-SWE-agent v2 by default and builds that view from the `bash-only` board filtered to `mini-swe-agent_version` beginning with `2.` ([picker](https://github.com/SWE-bench/swe-bench.github.io/blob/15491f17ea8274f55686338291d7da27df4d1bd7/templates/_leaderboard_table.html#L17-L29), [filter implementation](https://github.com/SWE-bench/swe-bench.github.io/blob/15491f17ea8274f55686338291d7da27df4d1bd7/js/mainResults.js#L432-L474)).

Skipped for this increment:

- the 500 issue/task records in SWE-bench Verified;
- the SWE-bench evaluation harness;
- all-agent, Lite, Full, Multilingual, and Multimodal boards;
- a generic provider/plugin framework;
- model-name joins across Radar sources.

## Why this fits Radar

Radar currently stores source-scoped model benchmark snapshots with quality, pass counts, cost, tokens, and elapsed time in `BenchmarkDataset`. SwiftData stores the encoded normalized dataset and deduplicates it by source and semantic fingerprint. This is a direct fit for leaderboard results.

The raw SWE-bench datasets are different: each row is a repository issue, base commit, problem statement, gold patch, and tests. Those rows cannot truthfully be represented as `ModelBenchmark`. The official dataset guide documents this task-level schema and its variants ([pinned guide](https://github.com/princeton-nlp/SWE-bench/blob/f7bbbb2ccdf479001d6467c9e34af59e44a840f9/docs/guides/datasets.md#L7-L85)).

Radar is also a viewer, not an evaluation runner. The official evaluator uses Docker, and the current project README warns that evaluation is resource-intensive and recommends an x86_64 machine with at least 120 GB free storage, 16 GB RAM, and 8 CPU cores ([pinned README](https://github.com/princeton-nlp/SWE-bench/blob/f7bbbb2ccdf479001d6467c9e34af59e44a840f9/README.md#L53-L102)). Running it inside the macOS app is out of scope.

## Authoritative live source

Use the official website repository's generated-data input:

`https://raw.githubusercontent.com/SWE-bench/swe-bench.github.io/master/data/leaderboards.json`

The website repository documents `data/leaderboards.json` as the source used to build the rendered leaderboard ([data flow](https://github.com/SWE-bench/swe-bench.github.io/blob/15491f17ea8274f55686338291d7da27df4d1bd7/README.md#L156-L205)). Official submission artifacts remain in the separate [`SWE-bench/experiments`](https://github.com/SWE-bench/experiments) repository; Radar should not crawl hundreds of submission folders when the official site already publishes the normalized leaderboard.

Observed on 2026-07-19:

| Property | Observation |
| --- | --- |
| File commit | [`7c4289f30aa1a1c63c2e2a25aae30c16d92b5114`](https://github.com/SWE-bench/swe-bench.github.io/blob/7c4289f30aa1a1c63c2e2a25aae30c16d92b5114/data/leaderboards.json) |
| Commit date | 2026-02-27T16:59:49Z |
| Response size | 7,323,841 bytes |
| SHA-256 | `c3bf3a74d7d67ba7e2777e197f96894601917e8e186a078133897ed3e81566e5` |
| MIME | `text/plain; charset=utf-8` |
| Cache validator | ETag present; `Cache-Control: max-age=300` |
| mini-SWE-agent v2 rows | 14 source rows, 13 unique `folder` values |

This is an official repository file, but not a versioned API. The parser must fail closed on missing boards, changed field types, conflicting duplicate identities, or unsafe bounds.

## Mapping

Select exactly one board named `bash-only`, then keep entries where:

- `mini-swe-agent_version` starts with `2.`;
- `warning` is absent or null;
- `folder`, `name`, and `resolved` are valid;
- `folder` is unique after deterministic duplicate handling.

Map only the fields Radar uses:

| Upstream | Radar | Rule |
| --- | --- | --- |
| `folder` | `ModelID.upstreamKey` | Stable submission identity, not a guessed model-name join |
| `name` | model display/upstream name | Trim only surrounding whitespace |
| `resolved` | `qualityScore` | Decimal percentage in `0...100` |
| `resolved` + Verified size | `passedTasks` | Derive only when `resolved × 500 / 100` is an exact integer |
| constant | `validTasks` | `500`, the Verified task count |
| `cost` | `benchmarkCostUSD` | Total evaluation cost; keep `nil` when absent |
| none | tokens, elapsed, steps, cache, community | Keep `nil`; do not fabricate |

Dataset metadata:

- `benchmarkName`: `SWE-bench Verified · mini-SWE-agent v2`
- `benchmarkVersion`: `mini-SWE-agent 2.x`
- `seriesRevision`: `swe-bench-verified-mini-v2-v1`
- `sourceUpdatedAt`: `nil`; use local `fetchedAt` for snapshot chronology because submission dates do not capture edits to older rows.

The current upstream file contains two semantically identical rows sharing one `folder`. Collapse only exact semantic duplicates deterministically. If rows with the same `folder` disagree on score, cost, version, or tags used for filtering, reject the whole benchmark projection and retain the last known good snapshot.

Large `per_instance_details`, logos, sites, tags, S3 links, and trajectories are deliberately not projected. `JSONDecoder` can ignore them. They remain in the bounded raw sample for audit/export.

## Front-end information architecture

### Recommended shape

SWE-bench needs a source-native content surface because the current overview assumes IQ, model families, reasoning tiers, community ratings, subscriptions, and quota data. It should **not** become a standalone product area named `Benchmarks`, and it should not be forced through those existing cards.

Use one global information overview plus independent source rooms:

```text
Radar
├── 信息总览
├── 来源
│   ├── Claude Code Radar
│   ├── Codex Radar
│   └── SWE-bench Verified
└── 导出
```

Selecting a source opens its native, source-scoped analysis. The room header owns its internal destinations:

```text
Claude / Codex: [概览] [模型] [趋势] [来源与口径]
SWE-bench:      [榜单] [趋势] [来源与口径]
```

`信息总览` may show all source freshness states and one source-native highlight per source, but it must use stable source order and visibly separate source bands. It has no global model table, common score label, shared numeric axis, combined ranking, cross-source recommendation, or cross-source Pareto.

This is preferable to the two alternatives:

- Keeping only the current source picker is the smallest change, but the active source becomes hidden state and every destination falsely appears to have the same semantics.
- Adding a separate `Benchmarks` namespace gives SWE-bench strong isolation, but creates a second navigation ontology and makes Radar look closer to an evaluation product.

The recommended shape preserves one mental model: Radar contains read-only information sources; each source decides which published views are meaningful.

### Global information overview

The new landing page is an integration surface, not a comparison surface:

- operational strip: last successful read, freshness, LKG/error, retained snapshots;
- one source band each for Claude, Codex, and SWE-bench;
- native metric names such as `IQ` or `% Resolved`, never a generic `Score`;
- one within-source change observation when a compatible prior snapshot exists;
- `打开来源分析` and `打开上游页面` actions;
- persistent copy: `各来源口径独立，不生成统一排名`.

Do not align native metrics into shared columns or color scales. Adjacency must not imply comparability.

### SWE-bench room

The default `榜单` surface combines a compact summary, analysis, and the complete result table:

```text
┌──────────────────────┬──────────────────────────────────────────────────────────┐
│ 信息总览              │ SWE-bench Verified  [只读]      [读取最新] [打开上游]    │
│                      │ mini-SWE-agent v2 · 500 tasks · 来源更新时间             │
│ 来源                 │ [榜单] [趋势] [来源与口径]                               │
│   Claude Code Radar  │                                                          │
│   Codex Radar        │ ┌────────┬────────┬────────┬────────────┐                │
│ ● SWE-bench Verified │ │模型数   │最高解决率│任务数   │最佳每解决成本│                │
│                      │ └────────┴────────┴────────┴────────────┘                │
│ 导出                 │ ┌────────────────────────┬─────────────────────────────┐ │
│                      │ │ 总成本 × % Resolved    │ 同口径 Pareto 候选          │ │
│                      │ └────────────────────────┴─────────────────────────────┘ │
│                      │ 搜索 / 排序 / 仅显示有成本数据                            │
│                      │ ┌──────────────────────────────────────┬───────────────┐ │
│                      │ │模型  %Resolved  Resolved/500  Cost  │详情 Inspector │ │
│                      │ │…                                     │口径/历史/出处 │ │
│                      │ └──────────────────────────────────────┴───────────────┘ │
└──────────────────────┴──────────────────────────────────────────────────────────┘
```

Summary cards:

- comparable model configurations;
- highest `% Resolved`;
- fixed Verified task count;
- lowest transparent `cost / resolved task` when both inputs exist.

Analysis:

- scatter plot: total evaluation cost on X, `% Resolved` on Y;
- Pareto classification only within `Verified + mini-SWE-agent v2 + seriesRevision`;
- no model-family inference, subscription recommendation, community value, quota, token, cache, or elapsed-time card unless SWE-bench publishes and the contract validates such a field.

Result table:

- configuration/model name;
- `% Resolved`;
- exact `resolved / 500`;
- total evaluation cost;
- cost per resolved task;
- optional upstream link.

Selecting a row opens an inspector with source-local identity, cohort, revision, measured values, transparent formulas, compatible history, provenance, and fetch time.

`趋势` is visible only after at least two comparable semantic snapshots exist. It never connects different families, cohorts, or `seriesRevision` values. With only one snapshot, omit the destination instead of showing an empty promise.

`来源与口径` replaces quota-oriented source status for SWE-bench:

- official URL and attribution;
- Verified, mini-SWE-agent v2, and 500-task definitions;
- current source revision and freshness;
- last refresh error and LKG state;
- license/non-affiliation disclosure;
- permanent read-only statement.

Toolbar language is limited to `读取最新`, `筛选`, `打开上游`, and `导出本地副本`. Never show `运行`, `重跑`, `提交`, `生成`, `发布`, job progress, or upstream edit/delete actions.

## Minimal code shape

Reuse the existing source, repository, fingerprint, history, export, and runtime machinery. The required product changes are bounded:

1. Add `SWEBenchConfiguration`, DTOs, and a parser with one small sanitized fixture.
2. Add `RadarSourceID.sweBenchVerified` and a third runtime.
3. Make the HTTP response policy source-specific:
   - keep the existing 5 MiB / JSON-only policy for current sources;
   - allow `text/plain` and at most 16 MiB only for SWE-bench;
   - retain HTTPS, same-host redirect, cookie, credential, timeout, ETag, and retry protections.
4. Make embedded source status optional. SWE-bench has benchmark data but no community or quota/status segment; absence must not be recorded as a synchronization failure.
5. Replace the hidden source-picker mode with the global overview and source-room navigation described above. Keep source-native destination lists rather than rendering empty or semantically false pages.
6. Add source-specific presentation at the room boundary:
   - label the metric `% Resolved`, not `IQ`;
   - treat rows as model configurations under mini-SWE-agent v2;
   - hide quota, community, model-family/tier, and source-status UI;
   - keep the compatible model table, pass rate, cost, Pareto, refresh, cache restoration, and export behavior;
   - expose trends only after comparable history exists.
7. Move attribution text into the source descriptor or handle this source explicitly. The current two-way attribution conditional would otherwise mislabel SWE-bench as Claude Code Radar.

Do not build a generic plugin registry or generalized ETL layer. A third explicit source plus one explicit presentation branch is enough; generalize only after another source needs the same variation.

The current raw retention policy keeps three successful payloads, so the observed disk cost is about 22 MB and the 16 MiB response cap creates a 48 MiB worst-case success-retention budget for this source.

## License and provenance gate

The SWE-bench evaluator/code repository is MIT licensed, but the **website and leaderboard-data repository is CC BY-NC 4.0**, not MIT ([pinned license](https://github.com/SWE-bench/swe-bench.github.io/blob/a0a7d29ec767639126ad4dc5b80397638854a705/LICENSE#L1-L20)).

Before enabling the source in a Release build:

- confirm Radar's distribution/use is noncommercial, or obtain separate permission for commercial use;
- show attribution to SWE-bench in the sidebar/About surface and exports;
- add the license and source boundary to `docs/third-party-notices.md` and `docs/source-contract.md`;
- do not imply affiliation, endorsement, or that every displayed run was directly verified by the SWE-bench team.

`checked` in the upstream data is a separate run-verification signal and currently drifts across boolean, string, null, and missing values. The MVP should not claim or display verification until that field receives an explicit, tested normalization contract.

## Acceptance

Parser:

- exactly one `bash-only` board;
- only mini-SWE-agent `2.x`, non-warning rows;
- unique non-empty submission identity after exact-duplicate collapse;
- non-empty display name;
- score in `0...100`;
- exact pass-count derivation against 500 or `nil`;
- nonnegative bounded cost;
- at most 500 normalized rows;
- conflicting duplicate or schema drift rejects the new snapshot.

Runtime:

- first online refresh stores one source-scoped benchmark snapshot and a bounded raw sample;
- a repeated ETag response produces no duplicate snapshot;
- a changed payload creates one new semantic snapshot;
- invalid/oversized data retains the last known good value;
- offline relaunch restores the SWE-bench workspace;
- Claude, Codex, and SWE-bench history, metadata, export, and analysis remain isolated;
- missing community/source-status capabilities produce no error banner or retry backoff.

UI:

- the source selector shows `SWE-bench Verified`;
- the overview says `% Resolved`, never `IQ`;
- no quota, community, family/tier, or personal-usage claims appear;
- score, pass count, total cost, sorting, filtering, Pareto, refresh, and export are exercised in the packaged app;
- attribution and the noncommercial license boundary are visible.

## If the intended feature is the raw issue dataset

That is a separate product feature, not a source-adapter variant.

Start with the 500-row `princeton-nlp/SWE-bench_Verified` test split and pin an exact Hugging Face revision. Store only task-catalog fields needed for browsing (`instance_id`, `repo`, `base_commit`, `problem_statement`, `version`, and `created_at` when present). Keep `patch`, `test_patch`, `FAIL_TO_PASS`, and `PASS_TO_PASS` out of model-facing data to prevent gold-solution leakage.

It requires a dedicated task entity, task index, and task-detail view. Do not map issue rows to `ModelBenchmark`, and do not add the Docker evaluator unless running evaluations becomes an explicit product requirement.
