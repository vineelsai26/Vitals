# Vitals

Vitals is a minimal, local-first system monitor for macOS 14 and newer. It combines live Mac health with local Codex and Claude token activity in one native SwiftUI app and menu-bar panel.

## What it shows

- Overview with a current-values strip + three history lanes (CPU bars, stacked memory used/swap bars with composition bar, stacked network download/upload bars) over a shared wall-clock time axis
- CPU, memory, disk, network, battery, load averages, thermal state, and uptime
- Timestamped history with honest time-range labels (15M–30D of retained samples); charts use absolute scales or a labeled shared ceiling — flat series render flat
- Per-interface network rates, mounted volumes with capacity, and a ranked process list (CPU/memory sort, filter, context menu)
- Detected GPU and Apple Neural Engine hardware, with an honest unsupported state for system-wide utilization
- Codex and Claude tokens today plus a truthful last-7-days history, derived locally from session metadata (incremental scan; input/output/cached normalized across providers)
- Menu-bar dashboard with configurable labels, pause/resume, settings, and quit
- Optional threshold alerts (memory, battery, thermal)
- System / light / dark appearance modes

Vitals never reads Codex or Claude credential files, never displays prompt content, and does not send monitoring data over the network. Agent usage is best-effort because local session schemas can change.

### Keyboard

| Shortcut | Action |
|----------|--------|
| ⌘1–⌘5 | Navigate Overview → Storage |
| ⌘, | Settings |
| ⌘R | Refresh now |
| ⌘⇧P | Pause / resume monitoring |

## Build and run

```sh
make app
open dist/Vitals.app
```

## Verify

```sh
make selftest
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
make render-samples
```

The XCTest command uses the full Xcode toolchain because the standalone Command Line Tools installation does not include the XCTest module.

Rendered light/dark window and menu-bar samples are written to `dist/renders/`.
