# 04. Command queue fixes for long turns

Status: not started.

## Problems (verified)
1. Queued-prompt loss on long turns: pi_command_queue.rs (~:790-812) force-proceeds a QUEUED follow-up prompt after a 300s idle-wait; the ACP loop then rejects it ("ACP agent is already processing a prompt") and the message is lost. A 30-minute subagent turn makes this common. The 300s watchdog predates ACP; raw pi turns rarely ran that long.
2. Mid-turn config changes cannot reach the runtime: the queue serializes WaitDone commands behind the active prompt, so a model/mode change sits queued until agent_end. The runtime now accepts set_config_option/set_mode mid-turn (spec-correct, commit 03a1f5006) and resolves them via callback, but the desktop never delivers them mid-turn. The composer disables its selects while streaming because of this.

## Constraints and prior art
- There are NO protocol turn timeouts and none should be added; any watchdog must key on tool_call_update traffic, not wall clock (30-minute turns are legitimate).
- The queue already has bypass mechanics: abort and steer are delivered while a prompt is active (abort_cmd fast path ~:602; steer_in_flight logic). Lifecycle responses correlate by request id (register_response) regardless of delivery order.
- Repo rule: fix races by dedupe/single-path, not suppression flags.

## Change set
1. Replace the 300s idle-wait force-proceed with activity-aware waiting: reset the deadline whenever any event arrives for the session (tool_execution_start/progress/end, message_update). Only force-proceed after N minutes of TOTAL silence (no events at all), which indicates a wedged agent rather than a long turn.
2. Add a delivery class for session-config commands (set_config_option, set_mode, set_model): deliver immediately like abort/steer instead of FIFO-behind-prompt. They are safe mid-turn now that the runtime handles them without blocking its loop.
3. Frontend: re-enable composer selects during streaming once (2) lands; keep the per-option pending spinner.

## Tests
- pi_command_queue tests already cover steer/abort mid-turn semantics (test_steer_in_flight_blocks_drain_loop_until_cleared etc.); mirror those for the new delivery class and the activity-aware deadline (fake clock).
