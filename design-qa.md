# Vitals Design QA

## Comparison Target

- Source visual truth: `/private/tmp/vitals-reference-light.png`, `/private/tmp/vitals-reference-dark.png`, and `/private/tmp/vitals-reference-menu.png`, cropped from the original ChatGPT-generated `System monitoring UI design concepts` image.
- Implementation screenshots:
  - `dist/renders/main-light.png`
  - `dist/renders/main-dark.png`
  - `dist/renders/menu-light.png`
  - `dist/renders/menu-dark.png`
  - `dist/renders/menu-ai-light.png`
  - `dist/renders/menu-ai-dark.png`
- Logical implementation viewport: 1180 × 450 points for the main dashboard; 282-point-wide menu panels.
- State: deterministic demo data, Overview selected, 1H selected, System and AI menu panels captured separately.

## Full-View Comparison Evidence

The source crops and implementation screenshots were opened together in the same comparison pass.

- Light dashboard: the implementation matches the source hierarchy and composition: slim left navigation, traffic-light title-bar treatment, compact header controls, five aligned metric cards, a wide system-activity panel, AI usage summary, and top-process table. Card borders, corner radii, white/near-white surfaces, and blue selected navigation match the source direction.
- Dark dashboard: the implementation matches the source's navy-black canvas, low-contrast borders, compact card density, colored metric series, restrained typography, and selected-navigation treatment. It intentionally preserves the same information architecture as light mode instead of removing Network and Storage navigation when the theme changes.
- Menu-bar surfaces: the System and AI panels match the ultra-minimal reference's narrow popover, compact metric rows, colored values/sparklines, three-button footer, and low-elevation native surface.

## Focused Region Comparison Evidence

- Metric cards: title/value/sparkline/detail alignment, color mapping, padding, and eight-point radii were inspected at full image resolution.
- Lower dashboard: activity legend/axes, AI progress rows, process columns, dividers, and real application icons were inspected against the corresponding source panels.
- Menu panels: row spacing, fixed label/value columns, sparkline scale, summary row, and footer-icon spacing were inspected against Option 3.

## Current Product QA Findings

- The Overview is exception-first and no longer labels high memory occupancy as macOS memory pressure. Swap use is presented as a neutral status note; thermal and battery conditions remain actionable signals.
- Network history uses an explicit shared scale with a 1 MB/s minimum instead of stretching each small burst to full height.
- AI Usage presents one consolidated daily summary with provider composition and explicit token-accounting/privacy copy.
- Processes is labeled as a ranked `Top 25` sample, supports name/PID search, and caches resolved application icons.
- Settings is a dedicated fixed-width native macOS Settings window rather than a duplicate dashboard destination.
- Main-screen typography and secondary contrast were raised where density previously compromised readability. The menu-bar surface remains intentionally compact.
- Background processes without a resolvable application bundle use the native `app.dashed` symbol. User-facing applications use their real macOS icons when available.

## Intentional Product Constraints

- GPU and Neural Engine cards show detected hardware and an unavailable global-load state rather than the fabricated percentages in the concept. macOS does not expose supported public system-wide utilization for those devices.
- AI cards show locally measured tokens and session counts. Cost, subscription quota, and a separate ChatGPT row are omitted because there is no trustworthy local billing source.
- Light and dark modes share navigation and content structure so changing appearance does not change product capability. The palette and density follow the two source variants.

## Required Fidelity Surfaces

- Fonts and typography: native SF Pro/SF Rounded optical weights reproduce the macOS concept hierarchy; small labels remain readable and do not clip.
- Spacing and layout rhythm: sidebar proportion, header margins, five-column metric grid, panel gaps, padding, radii, and dividers align with the source. The native window height is capped to avoid the large empty region found during live QA.
- Colors and visual tokens: CPU blue, GPU purple, NPU green, memory orange, and battery green match the source in both semantic themes with sufficient contrast.
- Image quality and asset fidelity: the concept has no raster content. The implementation uses SF Symbols and real running-application icons rather than drawn or placeholder artwork.
- Copy and content: source labels are preserved where truthful; unsupported or unavailable metrics are stated explicitly.
- Accessibility: navigation and controls expose native button roles, selected state, labels, help text, and keyboard focus behavior.

## Interaction Verification

- Live native app launched from `dist/Vitals.app`.
- Overview → AI Usage → Processes navigation was exercised through the accessibility interface and selected-state/content updates were confirmed.
- The native Settings window was opened from the sidebar and its controls, disabled alert state, explanatory copy, and scrolling behavior were confirmed.
- The only main window was closed and the running app was invoked again; the `main` SwiftUI window was recreated successfully.
- The light/dark appearance control was exercised in both directions and its icon/state change was confirmed.
- Time-range controls, menu-panel switcher, pause/resume, Settings link, and open-window action are implemented as native controls.
- Direct SystemUIServer automation was unavailable, so menu interaction fidelity is covered by the deterministic System and AI menu renders plus compiled native control wiring.

## Comparison History

- Formal pass 1: passed. The reference and final implementation captures had no remaining P0/P1/P2 mismatch. Only the P3 dynamic-process-icon fallback remains.

## Implementation Verification

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test`: 6 XCTest regressions passed.
- `make selftest`: 30 core/live checks passed.
- `make app`: release build, app assembly, ad-hoc signing, and signature validation passed.
- `make render-samples`: light/dark dashboard and menu fixtures rendered successfully.
- AI usage scanning now reads appended complete JSONL records by file offset, preserves cumulative Codex baselines and Claude record-ID deduplication, waits for partial trailing records, and resets safely on truncation.
- Scanner day boundaries accept an injected calendar for deterministic timezone behavior, and timestamp parsing does not share mutable formatter instances across concurrent static entry points.

final result: passed with screenshot-only accessibility limits documented above
