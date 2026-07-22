# 01. Subagent UI: grouping, heartbeats, live output

Status: in progress (this session). Branch: feat/acp-agent-harness.

## Problem
A Claude Code Task subagent running 30 minutes renders as one pulsing row with zero interior progress, and its child tool calls clutter the transcript as flat siblings. Codex long tool calls look frozen until completion. All the data needed to fix this already arrives; our runtime drops `_meta`.

## Verified wire facts (source: external/acp/claude-agent-acp, codex-acp clones)
- claude-agent-acp emits the parent Task as tool_call kind "think", title = task description, initial content = the subagent prompt (src/tools.ts:137-153).
- Child tool calls of a subagent arrive as FLAT top-level tool_call/tool_call_update stamped `_meta.claudeCode.parentToolUseId` = the Task's toolCallId (src/acp-agent.ts:716-726, 6905-6914). Grouping is the client's job.
- Live heartbeats: tool_call_update status in_progress on the Task row with `_meta.claudeCode.toolResponse` = { elapsedTimeSeconds, subagentType, subagentRetry } (rate-limit retry info "so clients can show why a spawn looks stalled").
- Subagent prose/thinking is deliberately dropped by the adapter; render progress from child tool calls, not thoughts (src/acp-agent.ts:3459-3466).
- Subagent permission requests attribute to the parent Task row (ensureToolCallEmitted eagerly emits the child call first).
- A prompt turn stays pending until all spawned subagents settle: long-pending session/prompt is normal, not hung.
- codex-acp: subagent rows kind "other" with `_meta.codex.subagent` {threadId, path, activity}; live command output rides tool_call_update `_meta.terminal_output_delta` {data, terminal_id}; MCP progress rides `_meta.mcp_output_delta` {data}. No inner turn streaming.

## Our current pipeline
- apps/screenpipe-app-tauri/src-tauri/src/acp_runtime.rs handle_update: "tool_call" emits tool_execution_start {toolCallId, toolName, args}; "tool_call_update" merges into active_tools and only emits tool_execution_end at completed/failed. In-progress updates are dropped. `_meta` never read.
- lib/stores/pi-event-router.ts: tool_execution_start appends {type:"tool", toolCall:{id, toolName, args, isRunning, startedAtMs}}; tool_execution_end patches result/isError/endedAtMs.
- components/chat/standalone/message-content.tsx: ToolCallGroup renders consecutive tool blocks; ToolCallRailItem shows a pulsing dot while isRunning.

## Design (implemented)
1. Runtime: emit a third event `tool_execution_progress` {toolCallId, title?, elapsedSeconds?, subagentType?, retry?, outputDelta?} from in-progress tool_call_update carrying any of: claudeCode.toolResponse, terminal_output_delta, mcp_output_delta, or a changed title. Include `parentToolCallId` (from `_meta.claudeCode.parentToolUseId`) on tool_execution_start.
2. Router: tool_execution_start stores parentToolCallId; tool_execution_progress patches the tool block in place (elapsedSeconds/subagentType/retry, appends outputDelta to a capped live `progress` buffer, updates toolName on title change).
3. Rendering: children indent under their parent Task within the group; group header gets "n/m done" while running; running rows show elapsed (server elapsedSeconds preferred, else startedAtMs tick), subagentType chip, retry note, and last lines of live output.
4. Tests: runtime mapping unit tests; router tests for progress patching and parent linkage.

## Non-goals
- Rendering subagent thoughts (adapter drops them).
- Per-tool-call cancellation (protocol is per-turn only in v1).
- Nested trees deeper than one level (parentToolUseId is one hop).
