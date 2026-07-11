# Vitals Design QA

## 2026-07-11 redesign pass

A multi-reviewer audit (grok CLI, codex CLI, and four specialized Claude
lenses — information architecture, visual design, data-viz integrity,
secondary surfaces; 146 findings synthesized into one plan) drove a redesign
of every surface. Verification screenshots live in `dist/renders/`.

### Truthfulness fixes (P0)

- **Sparklines no longer min-max normalize.** `Sparkline` has exactly two
  scales: absolute 0–1 for percent metrics, and a shared tiered ceiling
  (`RateScale` in VitalsCore) for byte rates. A flat disk line renders flat.
- **AI token accounting normalized.** Codex reports `input_tokens` inclusive
  of `cached_input_tokens` (Claude's cache counts are separate);
  `parseCodexLine` now subtracts so `input + output + cached == total` holds
  for both providers and the provider cards' split bars are honest.
- Storage "Fill over time" is absolute 0–100% with a delta headline
  ("Effectively flat this 1H" below a 0.5 GB threshold) and a fixed height —
  no more full-window chart of a flat line.
- The swap band in the memory lane draws 1:1 on the RAM scale (visibility
  floor 1.5 pt) instead of the old unlabeled ×4 amplification.
- Age-fade on history bars removed — old data no longer fabricates a rising
  trend; only the live bucket is highlighted.
- Network strip cell lost its progress capsule (a fraction of a self-tuning
  ceiling is not a capacity) and its value is direction-labeled ("↓ 2.4 MB/s")
  on every surface that shows it.
- Processes search is labeled "Filter top N" and its empty state explains the
  ranked-sample scope instead of returning a false "no matches".

### Structure

- One number, one home: the strip owns current values (CPU w/ 1-minute load,
  Memory w/ total RAM, Network ↓/↑, Disk, Battery when present); lanes own
  history with inline headers carrying each lane's unique fact (CPU: 5m/15m
  load; Memory: swap; Network: upload + interface). The footer bar is deleted;
  a shared wall-clock time axis under the lanes replaces it ("filling" chip
  included). Tooltips lead with the bucket's wall-clock interval.
- Side rail: status card (attention states only get tint; swap-in-use is
  neutral copy), top-5 processes (title links to Processes), compact Machine
  table (Chip / Cores / Thermal / Uptime).
- Memory lane: step-area chart (memory is a level, not a bursty rate),
  composition bar on a neutral track (free = track, not a painted segment),
  full-word legend (Wired/Active/Inactive/Compressed/Free), swap annotated
  separately in amber.
- AI Usage page rebuilt: Today summary; truthful "Last 7 days" stacked daily
  bars (per-day scans via the existing `AIUsageScanner.scanCodex/scanClaude`
  day APIs, cached in `MonitorController.usageDays`; past days immutable,
  today tracks the live snapshot); provider cards with input/output/cached
  split bars; privacy footnote.
- Storage page rebuilt: startup-volume card, mounted-volumes list
  (`FileManager.mountedVolumeURLs`, internal/external badges), honest fill
  chart. The old "free space" card (an inverted copy of the same series in a
  borrowed green) is gone.
- Network page: merged download/upload hero card, labeled y-axis
  (0 / mid / ceiling) and time ticks on Throughput, single shared tier scale.
- Menu popover: header shows the range and opens the main window (visible
  chevron), Paused chip instead of an always-green dot, real tooltips on all
  footer buttons, Disk row uses a capacity capsule instead of a meaningless
  sparkline for a constant, merged Network row, divider before Quit.
- Time-range control also appears on Network and Storage (the pages whose
  charts it drives). Appearance is a Settings preference; the header toggle
  was removed.

### Type & color system

- Seven-token ramp in `Style.swift` (`VText`): pageTitle 20, metricL 22
  rounded, metricM 17 rounded, body 13, caption 11, kicker 11 upper/tracked,
  micro 9 (chart captions only). No persistent text below 11 pt.
- `VitalsColor` has fill/text pairs per metric; tinted text under 17 pt passes
  ≥4.5:1 in both schemes. One blue (CPU = brand accent; Codex aliases it),
  network teal, upload/Claude purple, memory orange (composition = one-hue
  ramp, compressed desaturated violet-gray), amber = swap only, red = thermal
  only, disk steel blue-gray. Axis labels and scale captions use secondary,
  not tertiary, for dark-mode legibility.

### Render harness

- Captures from an off-screen `NSWindow` (`cacheDisplay`), so AppKit-backed
  controls (grouped Form, TextField, Picker) rasterize — Settings and the
  Processes toolbar are reviewable. Fixed-size surfaces must clear
  `NSHostingView.sizingOptions` (it under-measures fixed frames and
  center-clips the capture); the self-sizing menu popover keeps them for
  `fittingSize`.
- All five sections render via `--section overview|ai|processes|network|storage`;
  settings via `--surface settings`.

### Verification

- `swift test` (7 tests), `make selftest` (30 checks), `make app` (signed
  release bundle) all pass.
- All fixtures re-rendered light + dark.
- Second-opinion round: updated renders went back to the grok and codex CLIs.
  Both confirmed the original P0s fixed; their converged #1 remaining issue
  (inconsistent AI token accounting) was root-caused to Codex-vs-Claude
  schema semantics and fixed at the parser (see above), along with the faint
  tertiary text, unlabeled download value, Disk missing from the strip, and
  the oversized Storage chart they flagged.

### Known intentional choices

- Chart mark language is deliberately per-semantics: bars for bursty rates
  (CPU, memory, network), lines for compact trends.
- The status card aggregates thermal, battery, CPU, memory, and swap signals;
  "Healthy" is scoped by its explanatory copy.
- No system-wide GPU/Neural Engine utilization: macOS exposes no supported
  public API; Vitals does not fabricate metrics. AI usage shows locally
  measured tokens/sessions only — no cost estimates.
