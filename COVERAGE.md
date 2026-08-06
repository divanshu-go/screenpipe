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

- Mapped specs: 98
- Declared test blocks: 278
- Weighted coverage points: 214.4

| Platform | Specs | Declared tests | Weighted points | Layers | Features | Critical score |
| --- | --- | --- | --- | --- | --- | --- |
| windows | 76 | 240 | 193.9 | 15 | 84 | 91% |
| macos | 94 | 241 | 185.2 | 17 | 86 | 89% |
| linux | 66 | 200 | 163.7 | 14 | 79 | 88% |

### Core Engine

- Mapped suites: 32
- Mapped Rust files: 312
- Active test blocks: 2925
- Ignored/manual test blocks: 134
- Weighted coverage points: 2404.0

| Platform | Suites | Active tests | Ignored tests | Weighted points | Layers | Flows | Critical score |
| --- | --- | --- | --- | --- | --- | --- | --- |
| windows | 29 | 2797 | 129 | 2345.2 | 21 | 11 | 100% |
| macos | 29 | 2848 | 109 | 2355.1 | 22 | 11 | 100% |
| linux | 25 | 2486 | 102 | 2064.1 | 20 | 11 | 100% |

## Refresh

From `apps/screenpipe-app-tauri`:

```bash
bun run coverage:all
bun run coverage:all:check
```

For core line coverage, install/use `cargo llvm-cov` and feed its JSON
summary into `coverage:core`; the core dashboard documents the exact command.
