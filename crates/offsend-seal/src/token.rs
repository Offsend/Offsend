use regex::Regex;
use std::sync::OnceLock;

/// Detects embed seal tokens without a key (for restore routing / scanners).
pub struct SealTokenDetector;

impl SealTokenDetector {
    /// Same pattern as Swift `SealTokenDetector.pattern`.
    pub fn pattern() -> &'static Regex {
        static PATTERN: OnceLock<Regex> = OnceLock::new();
        PATTERN.get_or_init(|| {
            Regex::new(r"\{\{([A-Z][A-Z0-9_]*):v1\.([A-Za-z0-9_-]+)\}\}")
                .expect("seal token regex")
        })
    }

    pub fn contains_seal_tokens(text: &str) -> bool {
        Self::pattern().is_match(text)
    }

    pub fn token_count(text: &str) -> usize {
        Self::pattern().find_iter(text).count()
    }

    /// Byte ranges of full `{{TYPE:v1.…}}` tokens in `text`.
    pub fn token_ranges(text: &str) -> Vec<std::ops::Range<usize>> {
        Self::pattern()
            .find_iter(text)
            .map(|m| m.start()..m.end())
            .collect()
    }

    /// Payload (base64url) byte ranges only — used to suppress entropy findings.
    pub fn payload_ranges(text: &str) -> Vec<std::ops::Range<usize>> {
        Self::pattern()
            .captures_iter(text)
            .filter_map(|c| c.get(2).map(|m| m.start()..m.end()))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_v1_tokens_not_placeholders() {
        let token = "{{EMAIL:v1.ay0pF8pgS30I1UA9cZxHpe-EDanFkPg3ybpjGzk-L3jor00}}";
        assert!(SealTokenDetector::contains_seal_tokens(&format!("hi {token}")));
        assert!(!SealTokenDetector::contains_seal_tokens("hi {{EMAIL_1}}"));
        assert_eq!(SealTokenDetector::token_count(&format!("{token} {token}")), 2);
    }
}
