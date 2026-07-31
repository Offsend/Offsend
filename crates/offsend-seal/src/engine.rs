use crate::error::SealError;
use crate::token::SealTokenDetector;
use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use rand::rngs::OsRng;
use rand::RngCore;

/// Result of sealing one or more spans in a text buffer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SealResult {
    pub sealed_text: String,
    pub sealed_count: usize,
}

/// A value span to seal. `start`/`end` are UTF-8 byte offsets into the source text;
/// `text[start..end]` must equal `value`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SealSpan {
    pub start: usize,
    pub end: usize,
    pub value: String,
    /// AES-GCM AAD and token type label (e.g. `EMAIL`, `SECRET`).
    pub type_label: String,
}

/// Authenticated reversible sealing — port of Swift `SealEngine`.
pub struct SealEngine {
    cipher: Aes256Gcm,
    max_plaintext_bytes: usize,
}

impl SealEngine {
    /// Default cap covers typical secrets without unbounded tokens.
    pub const DEFAULT_MAX_PLAINTEXT_BYTES: usize = 65_536;

    pub fn new(key: &[u8]) -> Result<Self, SealError> {
        Self::with_max_plaintext_bytes(key, Self::DEFAULT_MAX_PLAINTEXT_BYTES)
    }

    pub fn with_max_plaintext_bytes(
        key: &[u8],
        max_plaintext_bytes: usize,
    ) -> Result<Self, SealError> {
        if key.len() != 32 {
            return Err(SealError::InvalidKey(format!(
                "expected 32 bytes, got {}",
                key.len()
            )));
        }
        let cipher = Aes256Gcm::new_from_slice(key).map_err(|_| {
            SealError::InvalidKey("failed to construct AES-256-GCM cipher".into())
        })?;
        Ok(Self {
            cipher,
            max_plaintext_bytes,
        })
    }

    /// Encrypts a single value into `{{TYPE:v1.<base64url>}}`.
    pub fn seal_value(&self, plaintext: &str, type_label: &str) -> Result<String, SealError> {
        let plain = plaintext.as_bytes();
        if plain.len() > self.max_plaintext_bytes {
            return Err(SealError::PlaintextTooLarge {
                byte_count: plain.len(),
                limit: self.max_plaintext_bytes,
            });
        }

        let mut nonce_bytes = [0u8; 12];
        OsRng.fill_bytes(&mut nonce_bytes);
        let nonce = Nonce::from_slice(&nonce_bytes);

        let ciphertext = self
            .cipher
            .encrypt(
                nonce,
                Payload {
                    msg: plain,
                    aad: type_label.as_bytes(),
                },
            )
            .map_err(|_| SealError::EncryptionFailed)?;

        // CryptoKit SealedBox.combined = nonce || ciphertext || tag
        let mut combined = Vec::with_capacity(12 + ciphertext.len());
        combined.extend_from_slice(&nonce_bytes);
        combined.extend_from_slice(&ciphertext);

        Ok(format!(
            "{{{{{}:v1.{}}}}}",
            type_label,
            Self::base64url_encode(&combined)
        ))
    }

    /// Parses and decrypts a full token string.
    pub fn open(&self, token: &str) -> Result<(String, String), SealError> {
        let inner = token
            .strip_prefix("{{")
            .and_then(|s| s.strip_suffix("}}"))
            .ok_or(SealError::InvalidTokenFormat)?;

        let colon = inner.find(':').ok_or(SealError::InvalidTokenFormat)?;
        let type_label = &inner[..colon];
        let version_and_payload = &inner[colon + 1..];

        if !version_and_payload.starts_with("v1.") {
            let version = version_and_payload
                .split_once('.')
                .map(|(v, _)| v)
                .unwrap_or(version_and_payload);
            return Err(SealError::UnsupportedTokenVersion(version.to_string()));
        }

        let payload = &version_and_payload[3..];
        self.decrypt(type_label, payload)
    }

    /// Replaces spans with sealed tokens. Fails closed if any value exceeds the size limit.
    /// Overlapping spans: earlier (lower start) wins; later overlaps are skipped.
    pub fn seal_spans(&self, text: &str, spans: &[SealSpan]) -> Result<SealResult, SealError> {
        let mut ordered: Vec<&SealSpan> = spans.iter().collect();
        ordered.sort_by_key(|s| s.start);

        let mut replacements: Vec<(usize, usize, String)> = Vec::new();
        let mut covered_end: Option<usize> = None;
        let mut sealed_count = 0usize;

        for span in ordered {
            if span.end > text.len() || span.start > span.end {
                continue;
            }
            if text.as_bytes().get(span.start..span.end) != Some(span.value.as_bytes()) {
                continue;
            }
            if let Some(end) = covered_end {
                if span.start < end {
                    continue;
                }
            }

            let token = self.seal_value(&span.value, &span.type_label)?;
            replacements.push((span.start, span.end, token));
            sealed_count += 1;
            covered_end = Some(covered_end.map_or(span.end, |e| e.max(span.end)));
        }

        let mut sealed_text = text.to_string();
        for (start, end, token) in replacements.into_iter().rev() {
            sealed_text.replace_range(start..end, &token);
        }

        Ok(SealResult {
            sealed_text,
            sealed_count,
        })
    }

    /// Decrypts all `{{TYPE:v1.…}}` tokens in `text`. Fails fast on a bad token.
    pub fn unseal(&self, text: &str) -> Result<String, SealError> {
        let matches: Vec<_> = SealTokenDetector::pattern()
            .captures_iter(text)
            .map(|c| {
                let full = c.get(0).expect("full match");
                let type_label = c.get(1).expect("type").as_str().to_string();
                let payload = c.get(2).expect("payload").as_str().to_string();
                (full.start(), full.end(), type_label, payload)
            })
            .collect();

        if matches.is_empty() {
            return Ok(text.to_string());
        }

        let mut result = text.to_string();
        for (start, end, type_label, payload) in matches.into_iter().rev() {
            let (opened_type, plaintext) = self.decrypt(&type_label, &payload)?;
            debug_assert_eq!(opened_type, type_label);
            result.replace_range(start..end, &plaintext);
        }
        Ok(result)
    }

    /// Keeps findings only when they are *not* fully contained in a token that
    /// authenticates under this engine's key.
    pub fn excluding_authenticated_token_spans(
        &self,
        text: &str,
        spans: &[(usize, usize)],
    ) -> Vec<(usize, usize)> {
        let authenticated: Vec<_> = SealTokenDetector::token_ranges(text)
            .into_iter()
            .filter(|r| self.open(&text[r.clone()]).is_ok())
            .collect();

        spans
            .iter()
            .copied()
            .filter(|(start, end)| {
                !authenticated
                    .iter()
                    .any(|r| *start >= r.start && *end <= r.end)
            })
            .collect()
    }

    fn decrypt(&self, type_label: &str, payload: &str) -> Result<(String, String), SealError> {
        let combined =
            Self::base64url_decode(payload).ok_or(SealError::InvalidTokenFormat)?;
        if combined.len() < 12 + 16 {
            return Err(SealError::InvalidTokenFormat);
        }

        let (nonce_bytes, ct_and_tag) = combined.split_at(12);
        let nonce = Nonce::from_slice(nonce_bytes);

        let plain = self
            .cipher
            .decrypt(
                nonce,
                Payload {
                    msg: ct_and_tag,
                    aad: type_label.as_bytes(),
                },
            )
            .map_err(|_| SealError::DecryptionFailed)?;

        let plaintext =
            String::from_utf8(plain).map_err(|_| SealError::DecryptionFailed)?;
        Ok((type_label.to_string(), plaintext))
    }

    fn base64url_encode(data: &[u8]) -> String {
        URL_SAFE_NO_PAD.encode(data)
    }

    fn base64url_decode(string: &str) -> Option<Vec<u8>> {
        URL_SAFE_NO_PAD.decode(string.as_bytes()).ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key_0_31() -> [u8; 32] {
        let mut key = [0u8; 32];
        for (i, b) in key.iter_mut().enumerate() {
            *b = i as u8;
        }
        key
    }

    #[test]
    fn opens_swift_legacy_golden_vector() {
        let engine = SealEngine::new(&key_0_31()).unwrap();
        let token = "{{EMAIL:v1.ay0pF8pgS30I1UA9cZxHpe-EDanFkPg3ybpjGzk-L3jor00}}";
        let (ty, plain) = engine.open(token).unwrap();
        assert_eq!(ty, "EMAIL");
        assert_eq!(plain, "a@b.com");
    }

    #[test]
    fn roundtrip_and_fresh_nonce() {
        let engine = SealEngine::new(&key_0_31()).unwrap();
        let a = engine.seal_value("a@b.com", "EMAIL").unwrap();
        let b = engine.seal_value("a@b.com", "EMAIL").unwrap();
        assert_ne!(a, b);
        assert!(a.starts_with("{{EMAIL:v1."));
        assert!(a.ends_with("}}"));
        assert_eq!(engine.open(&a).unwrap().1, "a@b.com");
        assert_eq!(engine.open(&b).unwrap().1, "a@b.com");
    }

    #[test]
    fn type_is_aad() {
        let engine = SealEngine::new(&key_0_31()).unwrap();
        let token = engine.seal_value("same", "EMAIL").unwrap();
        let tampered = token.replacen("{{EMAIL:", "{{SECRET:", 1);
        assert_eq!(engine.open(&tampered), Err(SealError::DecryptionFailed));
    }

    #[test]
    fn wrong_key_fails() {
        let engine = SealEngine::new(&key_0_31()).unwrap();
        let token = engine.seal_value("a@b.com", "EMAIL").unwrap();
        let other = SealEngine::new(&[9u8; 32]).unwrap();
        assert_eq!(other.open(&token), Err(SealError::DecryptionFailed));
    }

    #[test]
    fn plaintext_limit() {
        let engine = SealEngine::with_max_plaintext_bytes(&key_0_31(), 256).unwrap();
        let large = "a".repeat(257);
        assert_eq!(
            engine.seal_value(&large, "SECRET"),
            Err(SealError::PlaintextTooLarge {
                byte_count: 257,
                limit: 256
            })
        );
        let exact = "a".repeat(256);
        assert!(engine.seal_value(&exact, "SECRET").is_ok());
    }

    #[test]
    fn utf8_byte_limit_not_char_count() {
        let engine = SealEngine::with_max_plaintext_bytes(&key_0_31(), 10).unwrap();
        // "я" is 2 bytes in UTF-8; 6 chars = 12 bytes > 10
        let cyrillic = "я".repeat(6);
        assert_eq!(
            engine.seal_value(&cyrillic, "SECRET"),
            Err(SealError::PlaintextTooLarge {
                byte_count: 12,
                limit: 10
            })
        );
    }

    #[test]
    fn unsupported_version() {
        let engine = SealEngine::new(&key_0_31()).unwrap();
        let token = engine.seal_value("a@b.com", "EMAIL").unwrap();
        let broken = token.replacen(":v1.", ":v2.", 1);
        assert_eq!(
            engine.open(&broken),
            Err(SealError::UnsupportedTokenVersion("v2".into()))
        );
    }

    #[test]
    fn invalid_key_length() {
        assert!(matches!(
            SealEngine::new(&[1u8; 16]),
            Err(SealError::InvalidKey(_))
        ));
    }

    #[test]
    fn unseal_multiple_right_to_left() {
        let engine = SealEngine::new(&key_0_31()).unwrap();
        let email = engine.seal_value("a@b.com", "EMAIL").unwrap();
        let phone = engine.seal_value("+10000000000", "PHONE").unwrap();
        let text = format!("mail {email} call {phone} done");
        assert_eq!(
            engine.unseal(&text).unwrap(),
            "mail a@b.com call +10000000000 done"
        );
    }

    #[test]
    fn unseal_fails_fast_on_bad_token() {
        let engine = SealEngine::new(&key_0_31()).unwrap();
        let good = engine.seal_value("a@b.com", "EMAIL").unwrap();
        let text = format!("before {good} {{{{EMAIL:v1.not-valid-payload}}}} after");
        assert!(engine.unseal(&text).is_err());
    }

    #[test]
    fn seal_spans_overlap_and_replace() {
        let engine = SealEngine::new(&key_0_31()).unwrap();
        let text = "hello a@b.com world";
        let start = text.find("a@b.com").unwrap();
        let end = start + "a@b.com".len();
        let result = engine
            .seal_spans(
                text,
                &[SealSpan {
                    start,
                    end,
                    value: "a@b.com".into(),
                    type_label: "EMAIL".into(),
                }],
            )
            .unwrap();
        assert_eq!(result.sealed_count, 1);
        assert_eq!(engine.unseal(&result.sealed_text).unwrap(), text);
    }

    #[test]
    fn invalid_token_formats() {
        let engine = SealEngine::new(&key_0_31()).unwrap();
        for token in [
            "{{EMAIL:v1.}}",
            "{{EMAIL:v1.!!!}}",
            "{{EMAIL:v1}}",
            "EMAIL:v1.abc",
            "{{:v1.abc}}",
        ] {
            assert!(
                engine.open(token).is_err(),
                "expected error for {token}"
            );
        }
    }
}
