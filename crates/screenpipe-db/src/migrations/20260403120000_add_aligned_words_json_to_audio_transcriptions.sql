-- Token-/word-level diarization merge output (JSON array of {text, start_sec, end_sec, speaker_label}).
-- Nullable: legacy rows and batch reconciliation without token timestamps.
ALTER TABLE audio_transcriptions ADD COLUMN aligned_words_json TEXT;
