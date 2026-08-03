# Product

<!-- impeccable:product-schema 1 -->

## Platform

macOS

## Users

AI and software-engineering developers and researchers who need to inspect published model-benchmark data on a Mac without mixing incompatible sources or relying on a browser tab workflow.

## Product Purpose

Claude Radar is a native macOS menu-bar app and workspace for reading public model-benchmark snapshots. It validates, stores, analyzes, displays, and exports information already published by upstream sources. Success means that a user can move from an overview into a source-specific room, inspect current and historical evidence, understand freshness and provenance, and export the selected source's data without losing the last valid state after a refresh failure.

## Positioning

Claude Radar gives Claude Code Radar, Codex Radar, and SWE-bench Verified separate rooms, vocabularies, histories, analyses, and export scopes. It deliberately does not create a unified ranking, composite score, or cross-source recommendation; source boundaries are part of the product's meaning rather than an implementation detail.

## Operating Context

- The primary workflow starts from the menu bar and Information Overview, then enters one source room to inspect models or a leaderboard, history, trends, source status, and provenance.
- Users compare only compatible rows inside the selected source, use source-local Pareto or efficiency views where available, and export selected data as a JSON ZIP.
- Settings separately manage normalized history, raw diagnostics, refresh behavior, and appearance.
- The app keeps normalized history, synchronization metadata, bounded raw samples, preferences, and exports on the Mac unless the user moves or shares them.
- Debug fixture modes support deterministic local UI and lifecycle evaluation; public adapters are used only through the app's documented source paths.

## Capabilities and Constraints

- Claude Code Radar provides benchmark, community, and source-status snapshots, model history, trends, derived metrics, and source-local comparisons.
- Codex Radar provides public summaries, community data, active-window quota context, rendered public-page warnings, and a rendered 24-hour IQ history. Official rendered IQ history and local IQ fitting remain independent.
- SWE-bench Verified provides published mini-SWE-agent v2 leaderboard results, `% Resolved`, 500-task counts, cost efficiency, within-cohort Pareto analysis, filters, sorting, and provenance.
- Each source has an independent runtime, parser contract, history, metadata, raw-sample scope, export scope, and last-known-good recovery path. Trends do not bridge incompatible source revisions.
- Radar reads already-published information only. It does not run benchmarks, submit results, generate upstream source data, or write to upstream systems.
- The app uses public source contracts and excludes credential-protected full APIs. The rendered Codex reader uses nonpersistent WebKit and does not retain page HTML, scripts, cookies, browser storage, response bodies, credentials, or endpoint material.
- Refresh failures must preserve valid history and expose the resulting state; invalid or stale data must not be presented as fresh.
- Raw samples and exported archives may contain upstream-provided content and must be reviewed before sharing. Removing the app does not automatically remove its local data.

## Brand Commitments

- Product name: Claude Radar; executable and bundle identity: ClaudeRadar.
- Preserve the exact source names Claude Code Radar, Codex Radar, and SWE-bench Verified, with source attribution and the existing non-affiliation statement.
- Maintain the existing English and Simplified Chinese documentation surfaces and the checked-in Claude Radar icon assets.
- The project is licensed under GPL-3.0-only.

## Evidence on Hand

- Product documentation: `README.md`, `README_zh.md`, `docs/source-contract.md`, `docs/implementation-status.md`, `docs/release-checklist.md`, and `docs/third-party-notices.md`.
- Native implementation: `Sources/ClaudeRadar/`, `Package.swift`, and `Config/ClaudeRadar-Info.plist`.
- Visual and identity assets: `Assets/ClaudeRadar.png`, `Assets/ClaudeRadar.icns`, and `Assets/readme/`.
- Evidence is limited to implemented behavior, public source data, checked-in fixtures, and documented provenance. Do not invent testimonials, customer claims, benchmark results, pricing, or upstream affiliation.

## Product Principles

- Preserve evidence and provenance before adding interpretation.
- Keep metrics native to their source; never imply cross-source comparability that the data does not support.
- Fail safely: retain last-known-good data and label freshness, validation, and runtime state explicitly.
- Keep collection read-only, local-first, and inspectable.
- Prefer native macOS workflows and clear source boundaries over a generic aggregation layer.

## Accessibility & Inclusion

Use native macOS controls and preserve the existing explicit accessibility labels and identifiers for source state, metric cards, charts, and rendered-data sections. The product has no additional user-specific accessibility requirement confirmed beyond maintaining those labels, readable source attribution, and selectable diagnostic text.
