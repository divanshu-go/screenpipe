# E2E Audio Tests — Prerequisites & How to Run

These tests require real or virtual audio hardware that is not available in CI.
They are marked `#[ignore]` and must be opted into explicitly.

---

## Test inventory

| Test file | Test name | What it proves | Hardware needed |
|---|---|---|---|
| `e2e_ghost_word_silent_room.rs` | `silent_room_no_ghost_words` | Bluetooth gap handling eliminates Whisper hallucinations end-to-end | BlackHole 2ch (virtual) |
| `e2e_ghost_word_silent_room.rs` | `blackhole_device_enumerable` | CPAL sees BlackHole in the device list | BlackHole 2ch (virtual) |
| `bluetooth_gap_hallucination_test.rs` | `silero_rejects_silence` | Silero VAD rejects 0.0 silence | Silero VAD model (auto-downloaded) |
| `bluetooth_gap_hallucination_test.rs` | `whisper_hallucination_before_after` | Crackle → `" you"`, silence → `""` | Whisper tiny model (auto-downloaded) |

---

## Prerequisites

### 1. BlackHole 2ch — virtual audio loopback (macOS)

BlackHole is a free, open-source virtual audio device. It is the macOS equivalent
of a hardware loopback cable: audio sent to the BlackHole output device appears
on the BlackHole input device.

**Install:**
```bash
brew install blackhole-2ch
```
or download the installer from https://existential.audio/blackhole/

**Verify:**
```bash
system_profiler SPAudioDataType | grep -i blackhole
# Expected: "BlackHole 2ch:" appears in the output
```

After installation, log out and back in (or reboot) so macOS registers the new
audio device.

**Why it is needed:**

The `silent_room_no_ghost_words` test uses `AudioStream::from_sender_for_test`
to inject audio directly into the pipeline with controlled timing gaps, bypassing
CPAL entirely. BlackHole is checked as a prerequisite to confirm the system's
audio stack is wired up correctly. The `blackhole_device_enumerable` test
verifies screenpipe's own CPAL enumeration can see BlackHole, which is a
necessary condition before testing with real Bluetooth hardware.

> **Note:** BlackHole delivers audio at a fixed hardware rate, so it cannot
> simulate Bluetooth timing gaps on its own. The gap simulation in
> `silent_room_no_ghost_words` is done by the test itself — it pushes audio
> chunks with deliberate 200ms pauses into the injected sender. No audio
> actually flows through BlackHole during this test.

---

### 2. Whisper tiny model (~75 MB)

The model is downloaded automatically by screenpipe on first run. If you have
not run screenpipe before:

```bash
# Run screenpipe for a few seconds to trigger the model download, then Ctrl+C
cargo run -p screenpipe-app-tauri -- --help
```

Or download manually via the Hugging Face CLI:
```bash
pip install huggingface_hub
python3 -c "from huggingface_hub import hf_hub_download; hf_hub_download('ggerganov/whisper.cpp', 'ggml-tiny.bin')"
```

**Verify:**
```bash
ls ~/.cache/huggingface/hub/models--ggerganov--whisper.cpp/snapshots/*/ggml-tiny.bin
```

---

### 3. Silero VAD model (~2 MB)

Downloaded automatically by screenpipe on first run to:
```
~/Library/Caches/screenpipe/vad/silero_vad_v5.onnx
```

If not present, the test that needs it will attempt to download it automatically.

---

## Running the tests

All hardware-dependent tests are `#[ignore]`. Pass `-- --ignored` to opt in.

### Run all e2e tests (requires all prerequisites above)

```bash
cargo test -p screenpipe-audio \
  --test e2e_ghost_word_silent_room \
  --features test-utils \
  -- --ignored --nocapture
```

### Run only the ghost-word hallucination test (no BlackHole needed for this one)

```bash
cargo test -p screenpipe-audio \
  --test bluetooth_gap_hallucination_test \
  -- --ignored --nocapture
```

### Run all ignored tests across the audio crate

```bash
cargo test -p screenpipe-audio \
  --features test-utils \
  -- --ignored --nocapture
```

### Run a specific test by name

```bash
cargo test -p screenpipe-audio \
  --test e2e_ghost_word_silent_room \
  --features test-utils \
  -- --ignored --nocapture \
  silent_room_no_ghost_words
```

---

## What the e2e test does (step by step)

```
[Test thread]
  │
  ├─ Checks BlackHole installed + Whisper tiny cached
  │
  ├─ Creates fake "AirPods Pro (Simulated)" device
  │   └─ name matches device_detection.rs Tier 1 → classified as Bluetooth
  │
  ├─ Builds AudioStream with injected broadcast sender
  │
  ├─ Starts record_and_transcribe() in background task
  │   └─ SourceBuffer is active inside the pipeline
  │
  ├─ Injects 320-sample chunks (20ms) at 20ms intervals
  │   └─ Every 50 chunks (≈1 second): sleeps 200ms before sending chunk
  │       → SourceBuffer sees elapsed=200ms >> expected=20ms
  │       → Detects gap, inserts 180ms of 0.0 silence
  │       → Crackle chunk follows the silence, not the gap
  │
  ├─ After 1.5 segments: signals is_running=false, waits for flush
  │
  ├─ Transcribes all flushed AudioInput segments with Whisper tiny
  │
  └─ Asserts: no ghost words found in any transcript
      Ghost words list: "thank you", "thanks for watching", "please subscribe",
                        "bye-bye", "so let's", " you", "you.", "you!"
```

**Expected output (with BlackHole + Whisper tiny):**
```
─────────────────────────────────────────────────────────────
Segments received : 1
Transcripts       :
  [0] <empty — silence correctly filtered>
Hallucinations    : 0
─────────────────────────────────────────────────────────────
test silent_room_no_ghost_words ... ok
```

**Expected output without BlackHole (graceful skip):**
```
SKIP: BlackHole 2ch not found. Install it and re-run.
      https://existential.audio/blackhole/
test silent_room_no_ghost_words ... ok
```

---

## Testing with real Bluetooth hardware

The "Silent Room" test can also be done manually with a real Bluetooth device
using the screenpipe desktop app:

1. Connect a Bluetooth headset (AirPods, Sony WH-series, etc.).
2. Open screenpipe. Let it run for 10 minutes in a **quiet room** — do not speak.
3. Open the screenpipe search UI.
4. Search for each ghost word: `"thank you"`, `"you"`, `"bye"`, `"so let's"`.
5. Filter results to the 10-minute silent window.

**Pass:** Zero results in the silent window.  
**Fail:** Any result with a timestamp during the silence = confirmed hallucination.

Cross-reference with the screenpipe logs:
```
[DEBUG screenpipe_audio::core::source_buffer] [AirPods Pro] bluetooth gap: 187.3ms elapsed → inserting 167ms silence
```
If a gap log entry and a ghost-word search result share the same timestamp, the
fix has a regression at that specific gap size.

---

## Adding new hardware-dependent tests

1. Place the test file in `crates/screenpipe-audio/tests/`.
2. Mark it `#[cfg(target_os = "macos")]` (or the appropriate platform).
3. Mark each test `#[ignore = "requires <prerequisite> — see tests/E2E_TESTING.md"]`.
4. Add a prerequisite guard at the top of the test that prints `SKIP:` and
   returns early instead of panicking — so `-- --ignored` never breaks CI
   when run on a machine that lacks the hardware.
5. Add the test to the table at the top of this file.
6. If the test needs `AudioStream::from_sender_for_test`, add
   `required-features = ["test-utils"]` to its `[[test]]` entry in `Cargo.toml`.
