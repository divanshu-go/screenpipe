# 09. Serve MCP over HTTP from the engine (kill the npm sidecar)

Status: not started. Supersedes the "pin screenpipe-mcp" mitigation in 06; complements 05.

## Problem this solves
Every ACP session currently gets its screenpipe tools from a stdio MCP sidecar: `bun x screenpipe-mcp@latest`, spawned per session at session/new (acp_runtime.rs mcp_servers, ~:1297). Failure modes observed in practice:
- npm fetch at session start: cold cache, registry hiccup, or offline means the MCP server silently fails; ACP surfaces no failure signal, so the session simply has no mcp__screenpipe tools.
- unpinned @latest drift, bun cold start latency, one extra child process per session.
- When tools are missing, agents fall back to the curl recipes in the workspace skill (~/.screenpipe/pi-chat/.pi/skills/screenpipe-api/SKILL.md), which is the main source of "sometimes MCP, sometimes curl" nondeterminism.

## Design
Nothing about MCP requires the sidecar: MCP has an HTTP transport (streamable HTTP, plus legacy SSE), and ACP's mcpServers declaration supports HTTP servers with headers, not just stdio commands.

1. Implement `/mcp` in the engine's existing axum server at localhost:3030. The MCP tools call the same internal handlers the REST routes already use; it is a protocol shim, not new functionality. Options: the official Rust MCP SDK (rmcp) has axum integration, or hand-roll JSON-RPC over POST plus an event stream. Auth rides the existing local API key as a bearer header (ACP's HTTP MCP declaration carries headers).
2. Change one function in the ACP runtime: mcp_servers() in acp_runtime.rs stops building McpServerStdio("bun x screenpipe-mcp@latest") and instead declares an HTTP server pointing at http://localhost:3030/mcp with the Authorization header (key already flows via SCREENPIPE_LOCAL_API_KEY; URL via SCREENPIPE_LOCAL_API_URL/PORT, set at spawn in pi.rs ~:2305).

## What it buys
- No npm fetch at session start: the silent-failure mode disappears.
- No @latest drift, no bun cold start, one fewer child process per session.
- The MCP surface is up whenever screenpipe itself is up, which directly attacks the curl fallback problem.

## Adapter support (source-verified 2026-07-20, external/acp clones)
- claude-agent-acp: advertises mcpCapabilities http+sse; client servers merged with SDK-side, client wins (src/acp-agent.ts:4928-4952, 5046).
- codex-acp: wires stdio AND http; note the name-collision filter vs user codex config (DISABLE_MCP_CONFIG_FILTERING). Codex benefits MOST: its sandbox blocks localhost shell network so curl can never work there; a harness-made HTTP MCP connection is its clean path.
- gemini-cli: maps http/sse entries in session/new and session/load.
- opencode: registers client-passed servers per session.
- cursor: ignores client-passed servers, wants .cursor/mcp.json; an HTTP entry can be written there as easily as a stdio one.
- pi-acp: drops client-passed mcpServers entirely (verified); this change does not help pi-over-ACP until fixed upstream. Raw Pi keeps its mcp-bridge path regardless.

## Follow-ups bundled with this
- Keep the standalone screenpipe-mcp npm package for external consumers (Claude Desktop configs etc.); only the app's own agent sessions stop depending on npm.
- The curl skill docs stay for pipes/scripts and as fallback; to stop agents reaching for curl when tools exist, also slim the agent-visible skill so the recipes stop competing with the tools.
- Optional: surface "MCP server unavailable this session" in chat if the HTTP endpoint is down (engine not running), instead of silent degradation.

## Size
Contained, moderate Rust change: tool logic already exists behind the REST routes; the shim + one-function runtime change + tests.
