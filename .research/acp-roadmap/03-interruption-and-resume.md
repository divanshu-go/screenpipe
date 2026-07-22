# 03. Honest interruption + real session resume

Status: not started.

## Problem
On app quit mid-turn, the process tree is torn down cleanly, but on relaunch the conversation is restored from disk with still-running tools persisted as isRunning:false, so they masquerade as completed. The turn is silently lost. We never resume the agent session; we glue a <conversation_history> text block into the next prompt instead.

## Verified facts
- All six adapters advertise loadSession (claude src/acp-agent.ts:1331; codex CodexAcpServer.ts:222 mapping to app-server thread/resume + thread/read includeTurns:true; gemini acpRpcDispatcher.ts:92; opencode service.ts:113; cursor documents session/load; pi-acp reattaches via session-map.json).
- Our pinned SDK 1.2.0 already has client-side session/load (full history replay), session/resume (NO replay, lighter), and session/list (requests.rs:15-41). No upgrade needed.
- LoadSessionRequest needs sessionId + cwd + mcpServers re-supplied.
- Spec: LoadSessionResponse restores only modes + configOptions + replayed history; in-flight turns cannot be resumed (schema v1/agent.rs:1248-1273). v2 REMOVES session/load (resume + replayFrom cursor instead), so abstract "load" behind a helper.
- Quit path today: RunEvent::Exit -> cleanup_pi -> PiManager::stop drops queue-owned stdin (runtime cancels turn, closes session, shuts terminals), waits 2s, group-kills (pi.rs; acp_runtime process groups / Windows Jobs).
- Persistence: pi-event-router.ts persistBackgroundSession (~:823) and flushPendingSaves (~:796) write on agent_end, termination, and window close; interrupted tools currently stamped isRunning:false (:906-916).

## Change set
1. Truthful interruption: when persisting while status is streaming/thinking/tool, mark still-running tool blocks isError:true, result "interrupted, app quit", and stamp the last assistant message interruptedByQuit:true + workDurationMs. Render an interrupted banner.
2. Persist per chat: acpSessionId, project_dir (cwd), and the agent identity whenever acp_ready/new_session succeeds (new runtime event field or reuse acp_session_config; store in chat-storage conversation file).
3. Runtime: accept a "load_session" command {sessionId} that calls LoadSessionRequest (fallback to ResumeSessionRequest when only sessionCapabilities.resume). Replayed history arrives as session/update stream; the desktop already renders those. Decide dedupe: since chat-storage already has the transcript, prefer session/resume (no replay) when available and fall back to load with replay suppressed client-side (ignore replayed updates until load response, or diff by message count).
4. pi.rs: on chat reopen with a persisted acpSessionId for the same preset signature, send load_session instead of new_session; on failure fall back to new_session + transcript glue (current behavior).
5. UI: "Resume" affordance on the interrupted banner; automatic resume on next prompt is acceptable v1.

## Risks
- Session ids may expire agent-side; treat load failure as normal and fall back silently.
- Replay double-render: guard before enabling replay path.
