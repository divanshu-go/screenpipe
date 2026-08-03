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

- Mapped specs: 90
- Declared test blocks: 252
- Weighted coverage points: 194.7

| Platform | Specs | Declared tests | Weighted points | Layers | Features | Critical score |
| --- | --- | --- | --- | --- | --- | --- |
| windows | 72 | 224 | 181.2 | 15 | 77 | 91% |
| macos | 86 | 215 | 165.5 | 17 | 79 | 89% |
| linux | 62 | 184 | 151.0 | 14 | 72 | 88% |

### Core Engine

- Mapped suites: 32
- Mapped Rust files: 309
- Active test blocks: 2865
- Ignored/manual test blocks: 133
- Weighted coverage points: 2360.1

| Platform | Suites | Active tests | Ignored tests | Weighted points | Layers | Flows | Critical score |
| --- | --- | --- | --- | --- | --- | --- | --- |
| windows | 29 | 2737 | 128 | 2301.4 | 21 | 11 | 100% |
| macos | 29 | 2788 | 108 | 2311.3 | 22 | 11 | 100% |
| linux | 25 | 2431 | 102 | 2023.7 | 20 | 11 | 100% |

## Refresh

From `apps/screenpipe-app-tauri`:

```bash
bun run coverage:all
bun run coverage:all:check
```

For core line coverage, install/use `cargo llvm-cov` and feed its JSON
summary into `coverage:core`; the core dashboard documents the exact command.
