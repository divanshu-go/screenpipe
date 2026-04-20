# Fix: Stuck-on-Stopped Vision Bug (allowlist-reconcile on wake)

## Context

When persisted `monitorIds` in settings use resolution-locked stable IDs (e.g. `Display 3_3440x1440_0,0`) that no longer match the connected monitors (office transition, different resolutions), `VisionManager::start()` filters every monitor out and returns `Ok(())` silently with zero tasks spawned. Because `CaptureSession::start` fires VisionManager inside a detached `tokio::spawn`, the `Ok(Self)` is returned before that spawn even runs — so `state.capture` gets `Some(dead_session)`. All subsequent tray clicks hit the `is_some()` short-circuit in `start_capture` and no-op. Tray shows "Stopped — click to record" forever.

**Fix:** D1 from the previous plan — make `VisionManager::start()` fail when no monitor tasks launched, and await it inline (not detached) so the error propagates back through `CaptureSession::start` → `start_capture`. `state.capture` stays `None`, enabling retries.

## Bug flow

```
Tray click
  → start_capture (recording.rs:231)
      → state.capture.is_some()? ──YES──→ return Ok(()) [STUCK]
      │
      NO (first click only)
      → CaptureSession::start (capture_session.rs:49)
          → tokio::spawn { vm.start().await }   ← detached, returns immediately
          → Ok(Self { … })                       ← dead session stored
      → state.capture = Some(dead_session)       ← NOW stuck forever
```

**After fix:**

```
Tray click
  → start_capture
      → state.capture.is_some()? NO
      → CaptureSession::start
          → vm.start().await (inline, awaited)
              → no monitors matched → Err("no monitors matched")
          → propagates as Err(String)
      → state.capture stays None               ← retries work
```

## Files to change

### 1. `crates/screenpipe-engine/src/vision_manager/manager.rs`

In `VisionManager::start()`, after the monitor loop (currently line ~169), add a guard before `Ok(())`:

```rust
// After the for-monitor loop, before return Ok(()):
let task_count = self.recording_tasks.len();
if task_count == 0 {
    warn!("VisionManager: no monitors matched the allowed list");
    *self.status.write().await = VisionManagerStatus::Stopped;
    return Err(anyhow::anyhow!(
        "no monitors matched the allowed list (monitorIds may be stale)"
    ));
}
info!("VisionManager started with {} monitor(s)", task_count);
Ok(())
```

**Audit:** The `disable_vision=true` path skips `VisionManager::start()` entirely (it's never constructed when disabled) — safe.

### 2. `apps/screenpipe-app-tauri/src-tauri/src/capture_session.rs`

Pull `vm_clone.start().await` out of the `tokio::spawn` so the error propagates to `CaptureSession::start` caller. Current structure (lines 81–103):

```rust
tokio::spawn(async move {
    if let Err(e) = vm_clone.start().await { error!(…); return; }
    start_monitor_watcher(…).await;
    shutdown_rx.recv().await;
    stop_monitor_watcher().await;
    vm_clone.shutdown().await;
});
```

Replace with:

```rust
// Await inline — error propagates to start_capture so state.capture stays None
vision_manager
    .start()
    .await
    .map_err(|e| format!("VisionManager failed to start: {e}"))?;
info!("VisionManager started successfully");

// Spawn only the long-running parts (monitor watcher + shutdown handler)
let vm_spawn = vision_manager.clone();
tokio::spawn(async move {
    let mut shutdown_rx = shutdown_rx;
    if let Err(e) = start_monitor_watcher(vm_spawn.clone(), audio_manager_for_drm).await {
        error!("Failed to start monitor watcher: {:?}", e);
    }
    info!("Monitor watcher started");
    let _ = shutdown_rx.recv().await;
    info!("Received shutdown signal for VisionManager");
    let _ = stop_monitor_watcher().await;
    if let Err(e) = vm_spawn.shutdown().await {
        error!("Error shutting down VisionManager: {:?}", e);
    }
});
```

Note: `vm_clone` was a clone of `vision_manager` used inside the spawn. After the restructure, use `vision_manager` directly for the inline `.start()` call (it's already `Arc<VisionManager>`) and clone it for the spawn.

## What this achieves

- **Stuck state broken:** On failure, `state.capture` remains `None` so every subsequent tray click retries `start_capture` cleanly.  
- **Wake/office recovery:** When the user wakes at the office (correct monitors now connected), clicking the tray starts a fresh `VisionManager` that finds allowed monitors and succeeds.
- **No silent dead sessions:** The log will show `VisionManager failed to start: no monitors matched` instead of the misleading `Capture session started successfully`.

## Rust onboarding woven into the fix — Jeremy Howard SIWC method

I'm learning Rust *by scratching my own itch* on this bug, not as a side tutorial. Follow Jeremy Howard's fast.ai pedagogy: **top-down, whole-game first, on the real code I'm touching**. No toy examples disconnected from the diff.

### Whole-game framing (read this before any code)

One paragraph of the full state flow so I see the shape before we touch pieces:

> Tray click → `deeplink-handler.tsx` routes the event → Tauri IPC calls `recording.rs::start_capture` → it reads `RecordingState` (an `Arc<Mutex<…>>`) and if `state.capture` is `None`, builds a `CaptureSession::start(...)` → that constructs an `Arc<VisionManager>`, calls `vm.start().await` (post-fix: inline; pre-fix: detached in `tokio::spawn`) → `VisionManager::start` enumerates monitors, filters by the persisted allowlist, and for each match spawns a per-monitor recording task that pushes frames into the DB. The bug: when the allowlist matches nothing, `start()` returns `Ok(())` with zero tasks; the outer detached spawn swallows that; `CaptureSession::start` returns `Ok(Self)` anyway; `state.capture = Some(dead)`; every future click short-circuits.

### Read-before-edit micro-sessions

Before each of the file edits below, a 5-minute guided read of the existing function. For each, note:

- the function signature — what's `&self` vs `&mut self` vs owned
- what types flow in/out (hover every one in rust-analyzer)
- where `.await` points are, and why they're there
- what's `Arc`'d vs cloned vs moved

**Order:** (1) `recording.rs::start_capture` → (2) `capture_session.rs::CaptureSession::start` → (3) `manager.rs::VisionManager::start` → (4) `manager.rs::is_monitor_allowed`. Drill into each with "Go to definition" before editing.

### Inline concept callouts (anchored to each edit site)

These are the Rust concepts that actually appear in the diff. Each one is explained *in terms of what this specific line does in this specific bug* — no abstract definitions.

- **`Arc<VisionManager>`** — shared ownership across tasks; `.clone()` is a cheap refcount bump, not a deep copy. The spawn needs its own `Arc` ref so the VM stays alive after `CaptureSession::start` returns; without the clone, the spawn would outlive its borrow.
  - *Question after edit:* why do we `.clone()` the Arc for the spawn but use the original for the inline `.start().await`?
- **`Result<(), anyhow::Error>` + `?`** — `?` unwraps `Ok` or early-returns `Err`. `.map_err(|e| format!(…))?` converts the anyhow error to the `String` error type `CaptureSession::start` returns, then propagates. This is the single character (`?`) that fixes the bug — it stops the error from disappearing.
  - *Question:* before the fix, where exactly did the error "disappear"?
- **`tokio::spawn`** — hands a future to the executor and returns a `JoinHandle` immediately. Detached = the caller cannot `.await` the result. Moving `.start()` *out* of the spawn is the structural fix: we need its result.
  - *Question:* what would break if we just added `.await` on the `JoinHandle` instead of pulling `.start()` out?
- **`RwLock<VisionManagerStatus>` + `.write().await`** — exclusive write guard, released on drop. The pre-existing `drop(status)` before the monitor loop in `start()` releases it early so `start_monitor` inside the loop can re-acquire it. Important: understand why this isn't a deadlock before touching `status` in the new error path.
  - *Question:* why is there a `drop(status)` mid-function instead of just letting it drop at end-of-scope?
- **`&mut self` vs `&self`** — `VisionManager::start(&mut self)` requires exclusive borrow; `Arc<VisionManager>` can't give that out. Notice how the code uses interior mutability (`RwLock`/`Mutex` inside) so methods take `&self` — the "outside" is shared, the "inside" is locked.

### Running glossary

Commit as **`docs/rust-for-screenpipe.md`** in the same PR. Rules:

- Only terms that appear in this diff
- Each entry anchors to a file:line in the PR
- One sentence in "what it does here," one sentence in "why this specific choice"

### Verify-as-I-learn checkpoints

After each file edit, I answer the question above before moving to the next file. If I can't, we stop and re-explain from the real code — not from generic Rust docs.

**Kept surgical:** The fix itself is still D1 — these Rust-onboarding layers live *on top of* the diffs in comments, PR description, and the glossary doc. No extra code.

## Observability gaps surfaced during diagnosis

Captured while live-comparing `mcp__screenpipe__list-monitors` + `/health` + per-monitor DB counts against `system_profiler SPDisplaysDataType` on the actual 4-monitor setup (1× DELL UP3216Q 5K main, 1× MacBook built-in Retina, 2× DELL U27xx QHD). Each one is a follow-up opportunity, not a blocker for D1 — but each belongs in the PR description.

### G1 — Pixel-loss on HiDPI/Retina captures is invisible to the user

- DELL UP3216Q native is **5120×2880**; screenpipe captures at **2560×1440** (logical / "UI looks like" size). 4× pixel loss.
- MacBook built-in native **3456×2234 Retina**; captured at **1728×1117**. Same 4× loss.
- The 2× non-Retina DELLs (2560×1440 native = logical) have no loss.
- `sck-rs` / ScreenCaptureKit returns the logical resolution and we pass it through unchanged. For OCR/accessibility that's fine. For "I want to re-watch what I saw," it's lossy and silent.
- **Surface:** log native vs logical at monitor enumeration; optionally expose a "capture scale" setting. Cheap win, huge UX clarity.

### G2 — Scale-factor changes produce the same stuck state as an office transition

- Persisted allowlist stable_id format is `Display N_WIDTHxHEIGHT_X,Y` — the WIDTH/HEIGHT are logical, not native.
- If the user drags the "Larger Text / More Space" slider in System Settings → Displays, the "UI looks like" resolution changes → the stable_id changes → allowlist mismatches all monitors → same silent `Ok(())` with zero tasks.
- **Second, easier repro path for the PR:** no need to carry a laptop between locations — just change the scale slider and click the tray.
- D1 fixes the symptom. Longer-term: either (a) use a truly stable id (vendor/model/serial via IOKit) or (b) match on display UUID instead of resolution. Out of scope for this PR; file as follow-up.

### G3 — Per-monitor recording state is not observable via the public API

- `/health.monitors` lists what ScreenCaptureKit *enumerates*, which is the superset of what's actually recorded.
- Ground truth is `SELECT device_name, COUNT(*), MAX(timestamp) FROM frames GROUP BY device_name` — which requires SQLite access and is undocumented.
- `monitor_2` and `monitor_5` both showed `2560×1440` in health but mapped to two different physical Dells (U2717D vs U2715H). User cannot tell which is which without opening the DB.
- **Surface:** extend `/health` to return per-monitor objects: `{id, label, native_res, logical_res, last_frame_at, frames_last_5m, status}`. This is the exact contract the stuck-state bug needed — and would have caught G2 at enumeration time.
- The `Plans/diagnostic-check-what-is-recording.sh` script in this repo is a workaround for this gap; the ultimate fix is to push that data into `/health`.

**How these relate to D1:** D1 alone makes startup *fail loudly* when the allowlist matches nothing. G1/G2/G3 make the *running state* legible so users can diagnose drift without reading logs. Ship D1 first; reference the gaps in the PR and open a tracking issue for each.

## Verification

1. **Reproduce the bug:**  
   Edit `~/Library/Application Support/screenpipe/settings.json` → set `monitorIds` to `["Display 999_9999x9999_0,0"]`. Launch binary, click tray — expect log: `VisionManager failed to start: no monitors matched`. `state.capture` should stay `None`. Clicking again retries.

2. **Fix monitorIds → click tray** — expect normal startup, frames appearing in DB.

3. **Unit test (new):**  
   `cargo test -p screenpipe-engine vision_manager::tests::start_with_no_allowed_monitors`  
   Test: create `VisionManagerConfig` with `monitor_ids = ["Display 999_…"]`, call `.start()`, assert `Err`.

4. **Regression:** `cargo test -p screenpipe-engine` + normal start/stop cycle with real monitors.

## Non-goals (from previous plan)

- No wake-event hook for vision (the monitor_watcher's poll loop + display_reconfig_callback already handles reconnect; the fix just unblocks retries)
- No changes to audio pipeline, frontend, or stable_id scheme
- No new features