# PRD-AGENT-001 — Isolate screenpipe's pi agent config from the user's global `~/.pi/agent/`

Status: research / proposal
Issues: [#4002](https://github.com/mediar-ai/screenpipe/issues/4002) (isolate pi agent config), [#3812](https://github.com/mediar-ai/screenpipe/issues/3812) (bundled `web_search` extension conflicts with global pi extension)
Date: 2026-06-12

---

## 1. Problem

screenpipe embeds the [pi coding agent](https://github.com/earendil-works/pi) (`@earendil-works/pi-coding-agent`, pinned at 0.75.4) as the runtime for pipes and the in-app chat. The pi **binary** is already isolated (installed by us into `~/.screenpipe/pi-agent/`), but the pi **config** is not: screenpipe reads and writes the user's global `~/.pi/agent/` directory, which is shared with any standalone pi installation the user runs for their own work.

Two user-visible failures result:

### #4002 — screenpipe pollutes the user's global pi config
`ensure_pi_config()` (crates/screenpipe-core/src/agents/pi.rs:723) and `write_pi_config()` (apps/screenpipe-app-tauri/src-tauri/src/pi.rs:1166) merge a `screenpipe` provider + model catalog into `~/.pi/agent/models.json` and a `screenpipe` token into `~/.pi/agent/auth.json` on every pipe/chat run. Users who use pi independently see screenpipe's models in their pi model picker and (reasonably) don't want screenpipe rewriting config they use elsewhere. We already had one regression in this area (clobbering jeffutter's ollama `baseUrl`) that forced the careful field-level merge logic now in `ensure_pi_config` — symptom of fighting over a shared file.

### #3812 — global pi extensions break screenpipe pipe runs
Because pipes run with the user's global agent dir, pi loads the user's global `~/.pi/agent/settings.json` `packages` (installed under `~/.pi/agent/npm/node_modules/`) **in addition to** the extensions screenpipe installs into each pipe's project dir (`<pipe>/.pi/extensions/`). The user's `pi-web-access` package registers a tool named `web_search`; screenpipe's bundled `web-search.ts` registers the same name. Pi reports the collision as an error diagnostic, and in non-interactive mode (`-p` / `--mode json` — the only modes screenpipe uses) **any error diagnostic is fatal**: `main.js` does `process.exit(1)` after `reportDiagnostics()` (dist/main.js:519–522). The pipe dies before the agent starts.

The same generic-name risk exists for our other bundled tools: `mcp_list_tools`, `mcp_call` (mcp-bridge.ts), and any future extension tools.

Root cause for both: **screenpipe treats a user-owned global directory as its own application state.**

---

## 2. Current state — full inventory of `~/.pi/agent` touchpoints

| Touchpoint | Where | What it does |
|---|---|---|
| `get_pi_config_dir()` | crates/screenpipe-core/src/agents/pi.rs:1790 | hardcodes `~/.pi/agent` |
| `get_pi_config_dir()` (duplicate) | apps/screenpipe-app-tauri/src-tauri/src/pi.rs:471 | same, for the desktop chat path |
| `ensure_pi_config()` | crates pi.rs:723 | merges `screenpipe` provider + BYOK provider entries into global `models.json`; merges token into global `auth.json` (0600) |
| `write_pi_config()` | app pi.rs:1166 | same logic, desktop chat side |
| Provider preservation logic | crates pi.rs:846–896 | deliberately *reads* user's global entries (e.g. their ollama `baseUrl`, their `OPENAI_API_KEY`) and preserves them — i.e. today, sharing the global config is partly a **feature** some users rely on |
| Sessions | `~/.pi/agent/sessions/<encoded-cwd>/` | pi stores `--continue` history keyed by cwd; screenpipe chats run in `~/.screenpipe/pi-chat/`, title-gen in `~/.screenpipe/pi-title/`, pipes in `~/.screenpipe/pipes/<name>/` — all of these land session files in the user's global sessions dir |
| Global packages/extensions | `~/.pi/agent/settings.json` + `~/.pi/agent/npm/` | loaded into every screenpipe pipe/chat run (the #3812 vector) |
| `settings.json`, `trust.json`, `bin/` (fd/rg) | global | shared incidentally |
| Cache UI | apps .../commands.rs:3307 (`list_cache_files`) | lists `~/.pi/agent` as deletable "AI agent config (.pi/agent)" — **today this offers to delete the user's personal pi config**, a serious footgun that isolation also fixes |
| Per-pipe project config | `<pipe>/.pi/extensions/*.ts`, `<pipe>/.pi/skills/` | already isolated per-project; not the problem |

What screenpipe installs per project dir (all under `<project>/.pi/`): `web-search.ts`, `mcp-bridge.ts`, `context-pruning.ts`, `orphan-guard.ts`, `register-artifact.ts`, `sub-agent.ts` (opt-in), `screenpipe-permissions.ts` (when restricted), plus `skills/screenpipe-api`, `skills/screenpipe-cli`, team skill, and mirrored user-imported skills.

---

## 3. What pi itself offers for isolation (verified against installed 0.75.4 source + docs)

Pi resolves its agent dir in `dist/config.js`:

```js
export const ENV_AGENT_DIR = `${APP_NAME.toUpperCase()}_CODING_AGENT_DIR`;   // PI_CODING_AGENT_DIR
export const ENV_SESSION_DIR = `${APP_NAME.toUpperCase()}_CODING_AGENT_SESSION_DIR`;
export function getAgentDir() {
    const envDir = process.env[ENV_AGENT_DIR];
    if (envDir) return expandTildePath(envDir);
    return join(homedir(), CONFIG_DIR_NAME, "agent");                        // ~/.pi/agent
}
```

Everything hangs off `getAgentDir()`: `models.json`, `auth.json`, `settings.json`, `sessions/`, `extensions/`, `skills/`, `prompts/`, `themes/`, `npm/` packages, `bin/` (managed fd/rg), debug log, keybindings. So one env var moves the whole world:

| Mechanism | Granularity | Notes |
|---|---|---|
| `PI_CODING_AGENT_DIR=<dir>` | entire agent config | documented in pi README/usage.md; one closed upstream naming quirk ([earendil-works/pi#2390](https://github.com/earendil-works/pi/issues/2390)) — `PI_CONFIG_DIR` is *not* a thing, only `PI_CODING_AGENT_DIR` |
| `PI_CODING_AGENT_SESSION_DIR` / `--session-dir <dir>` | sessions only | useful if we ever want sessions in app data but config shared |
| `--no-extensions` + repeatable `-e <path>` | extension discovery | kills *all* discovery (global **and** project `.pi/extensions/`), then load only what we pass explicitly |
| `--no-skills` + `--skill <path>` | skill discovery | same pattern for skills |
| Project `.pi/settings.json` | per-project overrides | project packages win over global by identity, but **cannot disable** the user's global packages — not sufficient for #3812 |
| `piConfig` in package.json (`{"piConfig": {"name": "...", "configDir": "..."}}`) | full whitelabel/fork | changes app name, config dir name, and env-var prefix (e.g. `TAU_CODING_AGENT_DIR`); documented in docs/development.md as the official fork mechanism |
| SDK (`createAgentSession`, custom `agentDir`, custom `ResourceLoader`) | full programmatic control | docs/sdk.md: with a custom ResourceLoader, cwd/agentDir no longer control discovery at all |
| `PI_PACKAGE_DIR`, `PI_OFFLINE`, `PI_SKIP_VERSION_CHECK` | misc | worth setting `PI_SKIP_VERSION_CHECK=1` in our spawns regardless, so our pinned 0.75.4 never phones home for updates |

Extension conflict semantics (0.75.4, dist/core/resource-loader.js:279–291): all extensions stay loaded, precedence by load order, but every conflict is pushed as an **error** — and errors are fatal in non-interactive modes. So "conflicts are just diagnostics" is only true in interactive TUI use, never for screenpipe.

---

## 4. Prior art — how other products handle embedded agent config

- **Pi's own ecosystem expects embedders to isolate.** The official fork doc (docs/development.md) exists precisely so downstream products get their own config dir + env prefix. [pi-agent-sdk-starter](https://github.com/vanzan01/pi-agent-sdk-starter) ("batteries-included starter for agentic desktop apps with Pi SDK") embeds `@earendil-works/pi-coding-agent` so users don't need a global pi install, and keeps its own provider config. [OpenClaw](https://nader.substack.com/p/how-to-build-a-custom-agent-framework) builds on pi packages as libraries with its own state dir (`~/.openclaw`), not `~/.pi`. Desktop shells like [pi-gui](https://github.com/minghinmatthewlam/pi-gui) and [pi-desktop](https://github.com/gustavonline/pi-desktop) wrap pi sessions rather than fight over its global config.
- **Claude Code**: `CLAUDE_CONFIG_DIR` relocates all config/state; embedders (CI runners, IDE harnesses) set it to a private dir per host app.
- **OpenAI Codex CLI**: `CODEX_HOME` relocates `~/.codex` (config, auth, sessions) — same single-env-var pattern.
- **General XDG pattern** (opencode, gemini-cli, etc.): app-scoped state under the embedding app's data dir; never write into another tool's dotfolder.

The industry norm is unambiguous: an embedding product points the agent CLI at a private config home via env var, and ships its own migration. We are the outlier today.

---

## 5. Solution options

### Option A — Private agent home via `PI_CODING_AGENT_DIR` (recommended core fix)

Set `PI_CODING_AGENT_DIR=~/.screenpipe/pi-config` (i.e. `default_screenpipe_data_dir().join("pi-config")`) on every pi spawn, and change both `get_pi_config_dir()` implementations to return that same path.

Pros
- Fixes **both** issues at the root: screenpipe never touches `~/.pi/agent` again, and the user's global `settings.json` packages (`pi-web-access` etc.) are simply never loaded into screenpipe runs — the `web_search` collision disappears without renaming anything.
- Sessions (`--continue` chat history), trust state, managed fd/rg binaries, debug log all move inside screenpipe's data dir — backup/uninstall/cache accounting becomes honest.
- One env var; zero pi code changes; works identically on Windows/macOS/Linux; survives pi upgrades (it's a documented, stable contract — `ENV_AGENT_DIR` drives everything in config.js).
- The "delete AI agent config" entry in `list_cache_files` becomes safe (it would point at our dir, not the user's).

Cons / costs
- Loses the accidental feature of inheriting the user's global pi providers/auth (their ollama/openai BYOK entries). Must be handled by a one-time **seed copy** (§6) plus an escape hatch.
- Existing chat sessions live under the global `sessions/` dir; `--continue` would silently start fresh unless we migrate session dirs (§6).
- Users who intentionally installed global pi extensions to enhance screenpipe chats lose them; escape hatch covers this.
- Duplicates `bin/` (fd/rg, ~few MB) and any npm package state inside our dir — negligible.

### Option B — Prefix screenpipe-authored tool names (`sp_web_search`, `sp_mcp_list_tools`, `sp_mcp_call`)

Rename tools in `crates/screenpipe-core/assets/extensions/*.ts` (and the duplicated copies under `apps/screenpipe-app-tauri/src-tauri/assets/extensions/`), update every skill/prompt/system-prompt string that references the old names.

Pros: cheap; defense-in-depth even after Option A (a user could still install a conflicting package *inside* a pipe project, or via the escape hatch); directly what #3812 asked for.
Cons: doesn't address #4002 at all; old `--continue` sessions reference old tool names in history (harmless — models re-read the live tool list); any user pipe.md that hardcodes "use the web_search tool" needs the model to map intent (it will — tool descriptions stay the same).

### Option C — `--no-extensions` + explicit `-e <path>` per bundled extension

Disable discovery entirely and pass exactly our extension files.

Pros: deterministic extension set per run; immune to anything the user installs globally **or** drops into the pipe dir.
Cons: also blocks intentional project-local user extensions (some power users add their own to pipe dirs — this currently works); `--no-extensions` + N×`-e` lengthens the command line (Windows cmd length limits already bit us once — flags-before-`-p` comment in spawn_pi); doesn't fix #4002. Better as an optional "strict mode" than the default.

### Option D — Embed via the pi SDK instead of spawning the CLI

Run a bun-hosted SDK harness (`createAgentSession` with explicit `agentDir` and a custom `ResourceLoader`).

Pros: total control (exact extension list, no settings/trust/global anything); no CLI arg-length issues; richer event stream than `--mode json`.
Cons: a rewrite of the entire executor (spawn/kill/process-group/streaming logic in two large files), new failure surface, and we'd own re-implementing session persistence semantics. Disproportionate to the problem; revisit only if we outgrow the CLI.

### Option E — Whitelabel fork via `piConfig` (`configDir: ".screenpipe/pi"`)

We already patch pi's installed `package.json` (`seed_pi_package_json` pins deps), so injecting `piConfig` is technically easy and would also rename the env prefix.

Pros: same isolation as A, plus rebranded banner/log names.
Cons: changes the env var name to `<NAME>_CODING_AGENT_DIR`, breaking the documented contract and any user/docs muscle memory; patching upstream package metadata is more fragile across pi upgrades than setting one env var; zero additional benefit over A for our needs. Rejected.

### Option F — Stay shared, merge harder (status quo++)

Keep `~/.pi/agent`, write more conservatively (e.g. never write unless provider is screenpipe, namespace our provider key, skip global packages via project settings).

Cons: project settings **cannot** turn off global packages, so #3812 stays unfixed; #4002 explicitly asks us not to write there at all; we keep paying merge-bug tax forever. Rejected.

### Recommendation

**A + B together, with C as an optional strict flag later.**
A is the structural fix for both issues; B is cheap hardening so a conflict can never again be fatal regardless of where extensions come from. Ship in one release so CLI (`screenpipe-engine`) and desktop app switch simultaneously (they share `crates/screenpipe-core`, but the app's duplicated `pi.rs` must be changed in the same PR — ideally deduplicated onto the crate version while we're in there).

---

## 6. Migration & backward compatibility

### 6.1 One-time seed migration (first run after update)

On startup (both app and CLI paths), before the first pi spawn:

```
if !pi_config_dir().join(".migrated-from-global").exists():
    take file lock (concurrent pipes!) — e.g. create-exclusive marker.tmp
    if ~/.pi/agent exists:
        COPY (never move/delete):
          - models.json            → seed; preserves user BYOK providers (ollama/openai/custom)
                                     that pipes resolve today via the merge logic
          - auth.json              → seed (chmod 600); preserves provider creds + screenpipe token
          - settings.json          → seed, but STRIP the `packages` array (global packages are
                                     exactly the #3812 vector; user can re-add deliberately)
          - trust.json             → seed, so previously-trusted dirs don't re-prompt
          - sessions/<encoded-cwd>/ for every cwd under default_screenpipe_data_dir()
                                     (pi-chat, pi-title, pipes/<name>) → copy dirs verbatim so
                                     --continue keeps chat history. Encoding: `--` + cwd with
                                     `[/\:]`→`-` + `--` (matches pi's session-manager + the
                                     migration code in pi's own migrations.ts)
        do NOT copy: npm/, git/, extensions/, skills/, prompts/, themes/, bin/
        (bin/ fd/rg re-extract automatically; extensions/skills are the thing we're escaping)
    write .migrated-from-global marker (with source-version metadata for debugging)
```

Why copy instead of move: other agents/users may run standalone pi expecting their sessions; per CLAUDE.md we never delete user data. Disk cost is small (session JSONL + two JSON files).

### 6.2 Cleaning up what we previously wrote into the global config

Conservative, one-time, after a successful seed:
- Remove the `"screenpipe"` key from global `models.json` `providers` and global `auth.json` — these are unambiguously ours (we are the only writer of that key) and are exactly what #4002 complains about.
- Touch **nothing else** (not `ollama`, not `openai-byok` — we can't prove we created them; field-merge history shows users hand-edit these).
- Log what was removed; skip silently if files are unparseable.
- Alternative considered: leave global untouched entirely and let the user delete. Simpler/safer, but #4002's literal complaint is "screenpipe's models showing up there" — removing only our own provider key honors the request with minimal risk. Decision needed (open question Q1).

### 6.3 Escape hatch for users who *want* sharing

Some users deliberately point screenpipe at their global pi setup (BYOK entries, custom extensions). Provide:
- `SCREENPIPE_PI_AGENT_DIR=<dir>` env override (we honor it for the dir we pass through), so `SCREENPIPE_PI_AGENT_DIR=~/.pi/agent` restores exactly the old behavior;
- optionally a hidden setting in the app later if demand shows up. No UI work in v1.

### 6.4 Compatibility matrix

| Persona | Before | After | Action needed |
|---|---|---|---|
| Default user, screenpipe cloud only | works; pollutes `~/.pi/agent` | works; private dir; global cleaned of our key | none |
| User of standalone pi + screenpipe (#4002 reporter) | screenpipe models/auth appear in their pi | their pi config untouched by us | none — fixed |
| User with global `pi-web-access` (#3812 reporter) | pipe runs hard-fail | global packages not loaded; runs fine | re-add wanted extensions per-pipe or via escape hatch |
| BYOK via global `models.json` (jeffutter pattern) | pipes inherit ollama/openai entries | seed copy preserves entries at migration time; later global edits no longer flow through | document: edit `~/.screenpipe/pi-config/models.json` (or set escape hatch) |
| Existing chat history (`--continue`) | sessions in global dir | copied for screenpipe cwds; history continues | none |
| User pipes with project-local custom extensions | load | still load (project `.pi/` untouched) | none |
| `pi -r` browsing screenpipe sessions manually | visible in global pi | run `PI_CODING_AGENT_DIR=~/.screenpipe/pi-config pi -r` | docs note |
| Cache cleanup UI | offers to delete user's `~/.pi/agent` (!) | entry retargeted to our private dir; old entry shown only as "legacy" with clear label | code change in `list_cache_files` |
| Fresh install (no `~/.pi`) | created `~/.pi/agent` | never creates `~/.pi` | none |

### 6.5 Things that must change together (single release)

1. Both `get_pi_config_dir()` implementations (crate + app duplicate) → new path + `SCREENPIPE_PI_AGENT_DIR` override. Prefer deleting the app duplicate in favor of the crate fn.
2. Every pi spawn site sets `PI_CODING_AGENT_DIR` (crates pi.rs `spawn_pi`/`spawn_pi_streaming`, app pi.rs chat spawn, title-gen spawn, sub-agent extension's child spawns — check `sub-agent.ts` inherits env, it does via process env) and `PI_SKIP_VERSION_CHECK=1`.
3. Seed migration + global cleanup (§6.1/6.2) with lock + marker.
4. `list_cache_files` retarget (commands.rs:3307).
5. Tool renames `web_search`→`sp_web_search`, `mcp_list_tools`→`sp_mcp_list_tools`, `mcp_call`→`sp_mcp_call` in both asset copies + every reference in skills/system prompts/tool-presentation (`lib/chat/tool-presentation.ts` maps tool names to UI) + tests.
6. Docs: BYOK guide, "where is my chat history", escape hatch, `pi -r` tip.
7. TESTING.md additions (below).

### 6.6 Edge cases / risks

- **Concurrent first-run**: multiple scheduled pipes can hit migration simultaneously (the existing tmp-file-suffix dance in `ensure_pi_config` exists for this reason). Use an exclusive-create lock file; losers wait or skip.
- **Windows**: env var works the same; session-dir encoding replaces `\` and `:` (pi handles it); keep flags-before-`-p` ordering.
- **Pi's own startup migrations** (`runMigrations` — auth.json migration, sessions-from-root, tools→bin) run against the *new* dir; harmless on a seeded dir.
- **Rollback**: if a release must revert, the global dir still has the pre-migration state (we only copied + removed our own provider key); old builds resume working minus the screenpipe provider entry, which they rewrite on next run anyway.
- **Token freshness**: auth token is re-merged on every run by `ensure_pi_config`, so a stale seeded token self-heals.
- **`trust.json` semantics**: if not seeded, non-interactive runs could hit trust prompts → must verify `-p` mode behavior with untrusted dirs during implementation (pi may auto-trust in non-TTY; verify).
- **Upstream drift**: `ENV_AGENT_DIR` is derived from `APP_NAME` — stable while we pin versions; add a CI canary that greps the installed package for `PI_CODING_AGENT_DIR` after `ensure_installed` upgrades the pin.

---

## 7. Rollout plan

- **Phase 0 (this release, independent)**: tool renames (Option B) — fixes the fatal #3812 crash for affected users immediately, no migration risk.
- **Phase 1**: isolation (Option A) + seed migration + cache-UI retarget, behind the escape-hatch env var. Announce in changelog with the BYOK note.
- **Phase 2 (next release)**: global-config cleanup of our `screenpipe` keys (if Q1 answered yes), remove any transitional logging.
- **Optional later**: strict mode (`--no-extensions` + explicit `-e`) for enterprise/permission-restricted pipes.

### Test checklist
- Fresh install (no `~/.pi`, no `~/.screenpipe/pi-config`) → pipe + chat run; `~/.pi` never created.
- Upgrade with existing global config containing: screenpipe provider, user ollama BYOK, user packages (`pi-web-access`), chat sessions → seed copies the right subset; `--continue` resumes prior chat; pipe with `pi-web-access` installed globally runs clean.
- Two pipes scheduled at the same minute on first post-upgrade run → exactly one migration, no corrupt JSON.
- `SCREENPIPE_PI_AGENT_DIR=~/.pi/agent` restores legacy behavior.
- Windows run of all of the above.
- `sp_web_search` invoked end-to-end from a screenpipe-cloud pipe; UI tool-presentation renders renamed tools.
- Cache cleanup screen no longer lists the user's `~/.pi/agent`.

---

## 8. Open questions

1. **Q1**: Do we actively remove our `screenpipe` provider/auth keys from the user's global config post-migration, or leave the global file untouched and only stop writing? (Recommend: remove only our own key, log it.)
2. **Q2**: Seed `settings.json` with or without the user's `defaultProvider/defaultModel`? (Recommend: strip — screenpipe always passes `--provider/--model` explicitly, so it's inert; copying invites confusion.)
3. **Q3**: Should the escape hatch be env-only or also a visible app setting? (Recommend: env-only until requested.)
4. **Q4**: Deduplicate the app's `src-tauri/src/pi.rs` config-writing code onto `screenpipe-core` in the same PR, or follow up? (Same PR preferred — two writers of the same file is how we got the merge-bug history.)
5. **Q5**: Upstream ask — file an issue with pi for a first-class "conflicts are warnings in non-interactive mode" or per-package disable from project settings? Cheap goodwill either way; not a blocker since isolation sidesteps it.

---

## Sources

- Pi source (installed, `@earendil-works/pi-coding-agent@0.75.4`): `dist/config.js` (`getAgentDir`, `ENV_AGENT_DIR`), `dist/core/resource-loader.js` (discovery roots, conflict detection), `dist/main.js` (fatal error diagnostics in non-interactive mode), `docs/usage.md`, `docs/packages.md`, `docs/settings.md`, `docs/development.md` (fork/`piConfig`), `docs/sdk.md`
- [earendil-works/pi](https://github.com/earendil-works/pi) · [pi README env vars](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/README.md) · [issue #2390 (PI_CONFIG_DIR vs PI_CODING_AGENT_DIR)](https://github.com/earendil-works/pi/issues/2390)
- [pi-agent-sdk-starter](https://github.com/vanzan01/pi-agent-sdk-starter) · [pi-gui](https://github.com/minghinmatthewlam/pi-gui) · [pi-desktop](https://github.com/gustavonline/pi-desktop) · [OpenClaw agent framework write-up](https://nader.substack.com/p/how-to-build-a-custom-agent-framework)
- screenpipe code: `crates/screenpipe-core/src/agents/pi.rs`, `apps/screenpipe-app-tauri/src-tauri/src/pi.rs`, `apps/screenpipe-app-tauri/src-tauri/src/commands.rs` (`list_cache_files`)
