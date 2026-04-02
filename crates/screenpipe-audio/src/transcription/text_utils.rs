/// Detects Whisper hallucination loops: returns true when the same sentence
/// (or a very similar one) repeats more than `max_repeats` times.
///
/// Whisper produces these when audio is near-silent or acoustically degraded —
/// the model gets stuck and loops on a plausible phrase. The `entropy_thold`
/// param should catch this but is unreliable across whisper-rs versions.
///
/// Strategy: split on sentence boundaries, count exact+near-duplicate repeats,
/// return true if any sentence appears more than `max_repeats` times.
pub fn is_repetition_hallucination(text: &str, max_repeats: usize) -> bool {
    let text = text.trim();
    if text.is_empty() {
        return false;
    }
    // Split on sentence-ending punctuation or newlines
    let sentences: Vec<&str> = text
        .split(|c| c == '.' || c == '!' || c == '?' || c == '\n')
        .map(|s| s.trim())
        .filter(|s| s.split_whitespace().count() >= 4)
        .collect();

    if sentences.len() < max_repeats {
        return false;
    }

    // Count occurrences of each normalised sentence
    let mut counts: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
    for s in &sentences {
        // Normalise: lowercase, strip punctuation
        let key: String = s
            .chars()
            .filter(|c| c.is_alphanumeric() || c.is_whitespace())
            .flat_map(|c| c.to_lowercase())
            .collect();
        let key = key.split_whitespace().collect::<Vec<_>>().join(" ");
        if key.is_empty() {
            continue;
        }
        *counts.entry(key).or_insert(0) += 1;
        if counts.values().any(|&n| n > max_repeats) {
            return true;
        }
    }
    false
}

/// Returns (start_idx_s1, start_idx_s2, match_length) for the longest common word substring.
/// This allows callers to properly handle overlap removal by skipping past the matched portion.
pub fn longest_common_word_substring(s1: &str, s2: &str) -> Option<(usize, usize, usize)> {
    let s1 = s1.to_lowercase();
    let s2 = s2.to_lowercase();

    let s1 = s1.replace(|c| char::is_ascii_punctuation(&c), "");
    let s2 = s2.replace(|c| char::is_ascii_punctuation(&c), "");

    let s1_words: Vec<&str> = s1.split_whitespace().collect();
    let s2_words: Vec<&str> = s2.split_whitespace().collect();

    let s1_len = s1_words.len();
    let s2_len = s2_words.len();

    // Table to store lengths of longest common suffixes of word substrings
    let mut dp = vec![vec![0; s2_len + 1]; s1_len + 1];

    let mut max_len = 0;
    let mut max_index_s1 = None; // Store the starting word index of the longest substring in s1
    let mut max_index_s2 = None; // Store the starting word index of the longest substring in s2

    for i in 1..=s1_len {
        for j in 1..=s2_len {
            if s1_words[i - 1] == s2_words[j - 1] {
                dp[i][j] = dp[i - 1][j - 1] + 1;
                if dp[i][j] > max_len {
                    max_len = dp[i][j];
                    max_index_s1 = Some(i - max_len); // The start index of the match in s1
                    max_index_s2 = Some(j - max_len); // The start index of the match in s2
                }
            }
        }
    }

    match (max_index_s1, max_index_s2) {
        (Some(idx1), Some(idx2)) if max_len > 0 => Some((idx1, idx2, max_len)),
        _ => None,
    }
}
