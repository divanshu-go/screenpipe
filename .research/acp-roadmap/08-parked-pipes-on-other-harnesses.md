# 08. Parked: pipes on non-pi harnesses

Status: parked deliberately. Revisit only with real demand.

## Why parked
Pipes (headless automations) are locked to raw pi at three layers: frontend preset picker filters provider!=="acp", the headless preset resolver, and preset listing (store.rs sanitize + crates/screenpipe-core pipes runtime + pipes server). The lock is correct today because:
1. The ACP runtime lives ONLY in the Tauri desktop binary (re-entered via the hidden --screenpipe-acp-runtime arg); screenpipe-core has zero ACP support. Headless pipes run without the desktop app.
2. ACP session/request_permission needs an answerer; pipes have no UI. Needs a headless auto-responder policy (deny-by-default or preset-configured).
3. Pipe sandboxing is enforced via pi-only extensions (permissions, MCP allowlist); other harnesses would need the server-side sp_pipe_ token enforcement instead (already harness-agnostic) plus equivalent guardrails.

## If revived, the work is
1. Extract the ACP client runtime into a crate reachable from screenpipe-core (today acp_runtime.rs is app-crate only).
2. Headless permission policy + auth handling (no interactive login; require pre-authenticated adapters).
3. Replace pi-extension-based sandboxing with token/allowlist enforcement.
4. Extend the pipes scheduler to supervise adapter process trees the way the desktop does (process groups, Windows Jobs).

## Notes
- The e2e mock ACP agent could serve as the test harness for headless permission policies.
- Cloud JWT ban applies doubly here: pipes run unattended.
