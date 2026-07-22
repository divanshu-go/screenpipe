# 06. Housekeeping: registry, SDK bump, small papercuts

Status: not started.

## Registry adoption
- https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json is the official machine-readable agent catalog: one agent.json per agent, auth-curated (only Agent Auth or Terminal Auth agents listed), CI-verified via a real ACP handshake checking authMethods, plus quarantine.json listing broken agents (8 as of 2026-07-20).
- Our four hardcoded pins in builtin_agent (acp_runtime.rs:204-218) matched the registry exactly on 2026-07-20 (pi-acp@0.0.31, codex-acp@1.1.4, claude-agent-acp@0.59.0, gemini-cli@0.51.0); cursor is listed as a binary dist (2026.07.16), opencode as a binary archive with sha256.
- The registry auto-bumps versions via hourly cron, so DO NOT consume it live; vendor a snapshot and bump deliberately.
- acpr (github.com/agentclientprotocol/acpr) is a registry-driven launcher LIBRARY (Rust) usable from the Tauri backend: registry fetch + binary download/extract/cache + spawn, with_command_wrapper() hook for sandboxing (bubblewrap suggested), with_registry_file for offline/test fixtures. Reference or dependency if we adopt binary-dist agents.
- Product angle: power the "Another ACP agent" picker from the vendored registry (minus quarantined agents) instead of a free-text command field.

## SDK bump
- Pinned agent-client-protocol 1.2.0 has the EOF hang (#261, fixed upstream unreleased). We shipped a runtime-level guard (commit 03a1f5006: stdout EOF signal raced in the main select). When the fixed release lands: bump, keep the guard (defense in depth is cheap here), and adopt the new on_close/incoming_closed APIs if useful.
- unstable_session_fork exists (adapter must advertise sessionCapabilities.fork); potentially useful for title-generation on a forked session without polluting history. Leave off until needed. unstable_protocol_v2 is a versioning experiment; not useful, we speak V1 only.

## Small papercuts
- screenpipe-mcp pinning is superseded by 09-http-mcp-endpoint.md (serve MCP over HTTP from the engine; the sidecar disappears for app sessions). Pin only if 09 is deferred.
- e2e spec asserts the settings adapter list by data-acp-agent-option values; keep in sync when adapters change.
- Windows: verify native select rendering of the new composer/preset dropdowns (native controls, should be fine; the portal issue does not apply).
- mock-acp-agent.ts could gain scenarios for _meta subagent traffic (parentToolUseId, toolResponse heartbeats, terminal_output_delta) to lock the subagent UI contract in e2e.
- symposium-acp's sacp-trace-viewer (swimlane per component, request/response correlation) is handy for debugging ACP traffic during development; sacp-conductor --trace records NDJSON.
