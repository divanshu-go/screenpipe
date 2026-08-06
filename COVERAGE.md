# Screenpipe Coverage

Screenpipe tracks coverage at two complementary layers:

- Tauri/WebDriver E2E coverage: real product UX and local API behavior by platform.
- Core engine coverage: Rust behavioral flow coverage across capture, audio, DB, accessibility, and engine crates.

These dashboards are behavioral maps, not a replacement for line or branch coverage.
Use them to see which product risks are represented, then layer runtime job
results and `cargo llvm-cov` data on top when judging release confidence.

## Dashboards

- E2E dashboard: [apps/screenpipe-app-tauri/e2e/COVERAGE.md](apps/screenpipe-app-tauri/e2e/COVERAGE.md)
- Core engine dashboard: [docs/coverage/CORE.md](docs/coverage/CORE.md)

## Current Snapshot

### Tauri E2E

- Mapped specs: 100
- Declared test blocks: 272
- Weighted coverage points: 211.4

| Platform | Specs | Declared tests | Weighted points | Layers | Features | Critical score |
| --- | --- | --- | --- | --- | --- | --- |
| windows | 78 | 234 | 190.9 | 15 | 80 | 91% |
| macos | 96 | 235 | 182.2 | 17 | 82 | 90% |
| linux | 68 | 194 | 160.7 | 14 | 75 | 88% |

### Core Engine

- Mapped suites: 32
- Mapped Rust files: 312
- Active test blocks: 2933
- Ignored/manual test blocks: 134
- Weighted coverage points: 2409.3

| Platform | Suites | Active tests | Ignored tests | Weighted points | Layers | Flows | Critical score |
| --- | --- | --- | --- | --- | --- | --- | --- |
| windows | 29 | 2802 | 129 | 2349.3 | 21 | 11 | 100% |
| macos | 29 | 2856 | 109 | 2360.4 | 22 | 11 | 100% |
| linux | 25 | 2491 | 102 | 2068.2 | 20 | 11 | 100% |

## Refresh

From `apps/screenpipe-app-tauri`:

```bash
bun run coverage:all
bun run coverage:all:check
```

For core line coverage, install/use `cargo llvm-cov` and feed its JSON
summary into `coverage:core`; the core dashboard documents the exact command.
