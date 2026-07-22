# 05. MCP and extension parity across harnesses

Status: not started. See 09-http-mcp-endpoint.md for the transport change that should land first: serving MCP over HTTP from the engine removes the npm sidecar failure mode that causes the "sometimes curl" fallback.

## Current state (verified)
- ACP runtime registers exactly one MCP server at session/new: `bun x screenpipe-mcp@latest` (acp_runtime.rs mcp_servers, ~:1297). All adapters except two honor client-passed servers: cursor wants .cursor/mcp.json config files; pi-acp ACCEPTS but silently drops them (raw pi covers MCP via its mcp-bridge extension instead).
- codex-acp caveat: client-passed servers whose (sanitized) name collides with the user's codex config are DROPPED unless DISABLE_MCP_CONFIG_FILTERING=true; when any client servers survive, the injected mcp_servers key REPLACES an mcp_servers key in CODEX_CONFIG.
- claude-agent-acp merges client servers with SDK-side ones, client wins on name collision.
- Raw pi extensions (bundled .pi/extensions): web-search, mcp-bridge (user MCP servers via sp_mcp proxy + SCREENPIPE_MCP_SERVER_ALLOWLIST), save-artifact, connection-gate (drives connection-authorization cards over the extension_ui_request channel). None reach ACP harnesses.
- ACP permission/auth prompts already render as chat cards on every adapter (we reuse the extension_ui_request wire event, titles acp:permission:/acp:auth:).
- ACP has an extensibility surface we do not use: _meta everywhere + underscore-prefixed ExtRequest/ExtNotification methods (schema v1/ext.rs). Only pi-acp (ours) would ever emit a custom "_screenpipe/ui" method; third-party adapters never will.

## Change set
1. Forward the user's registered MCP servers (the /mcp-servers list the mcp-bridge extension serves) into NewSessionRequest.mcp_servers, applying the same allowlist. No protocol work needed. Mind the codex name-collision filter.
2. Re-express pi-only extensions as tools on the screenpipe MCP server so every harness gets them: web-search, save-artifact, connection-gate. The interactive confirm step becomes an ACP permission request (renders via the existing acp:permission card path) or MCP elicitation.
3. Surface the opencode limitation in the preset editor: opencode login over ACP is broken by design; acp_runtime.rs (~:1462-1465) hard-errors with a run-in-terminal message. Show the hint before users pick opencode.
4. Upstream: contribute mcpServers wiring to pi-acp (svkozak/pi-acp) so pi over ACP reaches parity; until then MCP-dependent features should keep the native pi backend.
