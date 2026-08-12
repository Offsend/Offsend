//! Decode opaque base64 / hex blobs so secret-shaped plaintext hidden by
//! `| base64` / `xxd` still gets scanned (agent shell stdout → Read/MCP exfil).
//! Port of Swift `OpaqueEncodedBlobExtractor`.

use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use fancy_regex::Regex;
use once_cell::sync::Lazy;

/// Minimum base64 alphabet run length before a decode probe.
const MIN_BASE64_LEN: usize = 24;
/// Minimum hex run length before a decode probe.
const MIN_HEX_LEN: usize = 32;
/// CPU bounds. Crossing either bound is an enforcement event, not an allow:
/// callers must deny/withhold instead of letting decoys push a secret out.
const MAX_BLOBS_PER_TEXT: usize = 128;
const MAX_TOTAL_DECODED_BYTES: usize = 512_000;
/// Cap decoded byte size per blob.
const MAX_DECODED_BYTES: usize = 64_000;

#[derive(Debug, Clone)]
pub struct Blob {
    /// Byte range in the source text covering the encoded run.
    pub start: usize,
    pub end: usize,
    /// UTF-8 payload after decode (only when the bytes are valid UTF-8 text).
    pub decoded: String,
}

pub struct Extraction {
    pub blobs: Vec<Blob>,
    /// True when the bounded probe budget was exceeded; callers fail closed.
    pub budget_exceeded: bool,
}

static BASE64_RE: Lazy<Regex> = Lazy::new(|| {
    Regex::new(&format!(
        r"(?<![A-Za-z0-9+/=_-])[A-Za-z0-9+/_-]{{{MIN_BASE64_LEN},}}={{0,2}}(?![A-Za-z0-9+/=_-])"
    ))
    .expect("base64 blob pattern")
});

static WRAPPED_BASE64_RE: Lazy<Regex> = Lazy::new(|| {
    Regex::new(
        r"(?<![A-Za-z0-9+/=_-])(?:[A-Za-z0-9+/_-]{16,}[ \t\r\n]+){1,}[A-Za-z0-9+/_-]{4,}={0,2}(?![A-Za-z0-9+/=_-])",
    )
    .expect("wrapped base64 blob pattern")
});

static HEX_RE: Lazy<Regex> = Lazy::new(|| {
    let pairs = MIN_HEX_LEN / 2;
    Regex::new(&format!(
        r"(?<![0-9A-Fa-f])(?:[0-9A-Fa-f]{{2}}){{{pairs},}}(?![0-9A-Fa-f])"
    ))
    .expect("hex blob pattern")
});

/// Returns decodeable UTF-8 payloads. If the bounded probe budget is exceeded,
/// `budget_exceeded` is true and callers must fail closed.
pub fn extract(text: &str) -> Extraction {
    let mut blobs: Vec<Blob> = Vec::new();
    collect(text, &BASE64_RE, &mut blobs, |raw| {
        decode_base64(&strip_whitespace(raw))
    });
    collect(text, &WRAPPED_BASE64_RE, &mut blobs, |raw| {
        decode_base64(&strip_whitespace(raw))
    });
    collect(text, &HEX_RE, &mut blobs, decode_hex);

    // Prefer a complete wrapped payload over overlapping line fragments.
    blobs.sort_by(|a, b| (b.end - b.start).cmp(&(a.end - a.start)));
    let mut non_overlapping: Vec<Blob> = Vec::new();
    for blob in blobs {
        if !non_overlapping
            .iter()
            .any(|k| blob.start < k.end && k.start < blob.end)
        {
            non_overlapping.push(blob);
        }
    }
    non_overlapping.sort_by_key(|b| b.start);

    let mut accepted: Vec<Blob> = Vec::new();
    let mut decoded_bytes = 0usize;
    for blob in non_overlapping {
        let bytes = blob.decoded.len();
        if accepted.len() >= MAX_BLOBS_PER_TEXT
            || decoded_bytes > MAX_TOTAL_DECODED_BYTES - bytes.min(MAX_TOTAL_DECODED_BYTES)
        {
            return Extraction {
                blobs: accepted,
                budget_exceeded: true,
            };
        }
        decoded_bytes += bytes;
        accepted.push(blob);
    }
    Extraction {
        blobs: accepted,
        budget_exceeded: false,
    }
}

fn collect(text: &str, re: &Regex, out: &mut Vec<Blob>, decode: impl Fn(&str) -> Option<Vec<u8>>) {
    for m in re.find_iter(text) {
        let Ok(m) = m else { continue };
        let raw = &text[m.start()..m.end()];
        let Some(data) = decode(raw) else { continue };
        if data.is_empty() || data.len() > MAX_DECODED_BYTES {
            continue;
        }
        let Ok(decoded) = String::from_utf8(data) else {
            continue;
        };
        if !is_mostly_printable(&decoded) {
            continue;
        }
        out.push(Blob {
            start: m.start(),
            end: m.end(),
            decoded,
        });
    }
}

fn strip_whitespace(raw: &str) -> String {
    raw.chars().filter(|c| !c.is_whitespace()).collect()
}

/// Reject binary-looking UTF-8 (NUL / heavy controls) so a package of random
/// bytes does not become a decode probe.
fn is_mostly_printable(s: &str) -> bool {
    let total = s.chars().count();
    if total == 0 {
        return false;
    }
    let mut printable = 0usize;
    for c in s.chars() {
        if c == '\n' || c == '\r' || c == '\t' {
            printable += 1;
        } else if c.is_control() {
            continue;
        } else {
            printable += 1;
        }
    }
    printable * 4 >= total * 3 && s.chars().any(|c| !c.is_whitespace())
}

fn decode_base64(raw: &str) -> Option<Vec<u8>> {
    let mut normalized: String = raw.replace('-', "+").replace('_', "/");
    let padding = normalized.len() % 4;
    if padding == 1 {
        // Not a valid base64 length even after padding.
        return None;
    }
    if padding > 0 {
        normalized.push_str(&"=".repeat(4 - padding));
    }
    STANDARD.decode(normalized.as_bytes()).ok()
}

fn decode_hex(raw: &str) -> Option<Vec<u8>> {
    if !raw.len().is_multiple_of(2) {
        return None;
    }
    let bytes = raw.as_bytes();
    let mut out = Vec::with_capacity(raw.len() / 2);
    let mut i = 0;
    while i < bytes.len() {
        let hi = (bytes[i] as char).to_digit(16)?;
        let lo = (bytes[i + 1] as char).to_digit(16)?;
        out.push((hi * 16 + lo) as u8);
        i += 2;
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_base64_payload() {
        let secret = "sk_live_0123456789abcdefghijklmn";
        let encoded = STANDARD.encode(secret.as_bytes());
        let text = format!("here is data: {encoded} end");
        let extraction = extract(&text);
        assert!(!extraction.budget_exceeded);
        assert!(
            extraction.blobs.iter().any(|b| b.decoded == secret),
            "blobs: {:?}",
            extraction.blobs
        );
    }

    #[test]
    fn decodes_hex_payload() {
        let secret = "AKIAIOSFODNN7EXAMPLE";
        let encoded: String = secret.bytes().map(|b| format!("{b:02x}")).collect();
        let text = format!("blob {encoded} done");
        let extraction = extract(&text);
        assert!(
            extraction.blobs.iter().any(|b| b.decoded == secret),
            "blobs: {:?}",
            extraction.blobs
        );
    }

    #[test]
    fn ignores_short_runs() {
        let text = "short YWJj tokens only";
        assert!(extract(text).blobs.is_empty());
    }

    #[test]
    fn rejects_binary_payload() {
        // 24+ base64 chars decoding to non-printable bytes must not become a blob.
        let encoded = STANDARD.encode([0u8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]);
        let text = format!("data {encoded} x");
        assert!(extract(&text).blobs.iter().all(|b| b.decoded != "\0"));
    }
}
