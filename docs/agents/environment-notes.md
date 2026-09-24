# Agent environment notes

Host/tooling lessons from completed goal loops — check here before running
packaged-app QA or editing the version surface.

1. **Shell noclobber (host zsh).** Redirecting `>` onto an existing path —
   including a file just created by `mktemp` — aborts the entire command line
   with `file exists`, which silently skips launches (the app never starts and
   later checks read stale state). Use `>|` to force, or generate fresh unique
   paths. (v050 F2: three QA runs lost to this.)
2. **Env vars are DEBUG-build-only.** `RADAR_FIXTURE_MODE`, `RADAR_DATA_ROOT`,
   `RADAR_UI_STATE/SOURCE/DESTINATION` are read by the Debug configuration.
   The release bundle ignores them and writes to the real
   `~/Library/Application Support/AIRadar/` — packaged QA must build with
   `./Scripts/build-app.sh debug` first. (v050 F2.)
3. **Never string-surgery `Config/AIRadar-Info.plist` with Python.** A batch
   version bump truncated the plist tail (v050 N7) and produced an invalid
   bundle. Edit via `plutil` (or full-file rewrite) and always `plutil -lint`
   before committing/rebuilding.
4. **Screenshot scrolling.** The SwiftUI ScrollView ignores Page Down; use
   CGEvent line-scroll (see the manifest v0.5.0 section for the rebuild
   recipe). AX-guided closed-loop scrolling is flaky — prefer destinations
   that render the subject above the fold. (v050 N6.)
5. **Per-process offline simulation.** Don't toggle Wi-Fi (it kills the agent's
   own session). `sandbox-exec -f <profile>` with `(version 1)(allow default)(deny network*)`
   blocks network for one process — verified working for packaged-app offline
   QA (v050 HR-4). Pair it with the Debug-seed rendered-warning states
   (`RADAR_UI_STATE=warning-lkg-error` etc., DebugUISeed.renderedWarningStates)
   to exercise LKG-retention paths. Note: `RADAR_UI_STATE` values beyond
   `fresh|stale` are only honored in fixture `ui` mode.
6. **Upstream DOM probes: check rendered, not just source.** codexradar.com
   embeds healthy degradation markers in the server HTML but its own hydration
   empties the grid client-side (2026-09-25): a `curl` marker count can be
   green while the rendered surface is dead. Probe with a real browser
   (ego-browser) before trusting marker-based readers.
