use crate::types::{EntityType, SensitiveEntity};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use fancy_regex::Regex;
use once_cell::sync::Lazy;

static MONEY_SINGLE_DIGIT: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\$\d$").unwrap());
static ISO_DATE_DASH: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\d{4}-\d{2}-\d{2}$").unwrap());
static ISO_DATE_DOTS: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\d{4}\.\d{2}\.\d{2}$").unwrap());
static CLOCK_DOTS: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"^(?:[01]?\d|2[0-3])\.[0-5]\d\.[0-5]\d$").unwrap());
static ZIP_PLUS_4: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\d{5}-\d{4}$").unwrap());
static IPV4: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"^(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)$")
        .unwrap()
});
/// US SSN shape — middle group is 2 digits; NANP phones use 3.
static SSN_LIKE: Lazy<Regex> = Lazy::new(|| Regex::new(r"^\d{3}-\d{2}-\d{4}$").unwrap());
/// Lat/long pair accidentally matched as one phone span.
static COORD_PAIR: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"^\d{1,3}\.\d+\s+\d{1,3}\.\d+$").unwrap());
/// Same framing as `offsend_seal::SealTokenDetector` / Swift `SealTokenDetector.pattern`.
static SEAL_TOKEN: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"\{\{([A-Z][A-Z0-9_]*):v1\.([A-Za-z0-9_-]+)\}\}").unwrap()
});

pub fn filter_false_positives(entities: Vec<SensitiveEntity>) -> Vec<SensitiveEntity> {
    entities
        .into_iter()
        .filter(|e| match e.entity_type {
            EntityType::Money => !should_reject_money(&e.value),
            EntityType::Phone => !should_reject_phone(&e.value),
            EntityType::CreditCardLike => !should_reject_card(&e.value),
            EntityType::Iban => !should_reject_iban(&e.value),
            EntityType::Jwt => !should_reject_jwt(&e.value),
            EntityType::HighEntropyString => !should_reject_high_entropy(&e.value),
            t if t.is_secret() => !is_placeholder(&e.value),
            _ => true,
        })
        .collect()
}

/// Seal payloads are ciphertext, not live secrets/PII. Drop findings fully inside
/// `{{TYPE:v1.…}}` except concrete secret detectors (so a live key wrapped in a fake
/// token still fires). High-entropy and phone/email matches on base64url are the
/// common false positives this removes.
pub fn filter_inside_seal_tokens(
    entities: Vec<SensitiveEntity>,
    text: &str,
) -> Vec<SensitiveEntity> {
    if entities.is_empty() || !text.contains("{{") {
        return entities;
    }
    let ranges: Vec<(usize, usize)> = SEAL_TOKEN
        .find_iter(text)
        .filter_map(|m| m.ok().map(|m| (m.start(), m.end())))
        .collect();
    if ranges.is_empty() {
        return entities;
    }
    entities
        .into_iter()
        .filter(|e| {
            if e.entity_type.counts_as_critical_secret() {
                return true;
            }
            !ranges
                .iter()
                .any(|&(start, end)| e.start >= start && e.end <= end)
        })
        .collect()
}

fn should_reject_money(value: &str) -> bool {
    MONEY_SINGLE_DIGIT.is_match(value).unwrap_or(false)
}

fn should_reject_phone(value: &str) -> bool {
    let trimmed = value.trim();
    if ISO_DATE_DASH.is_match(trimmed).unwrap_or(false) {
        return true;
    }
    if ISO_DATE_DOTS.is_match(trimmed).unwrap_or(false) {
        return true;
    }
    if CLOCK_DOTS.is_match(trimmed).unwrap_or(false) {
        return true;
    }
    if ZIP_PLUS_4.is_match(trimmed).unwrap_or(false) {
        return true;
    }
    if IPV4.is_match(trimmed).unwrap_or(false) {
        return true;
    }
    if SSN_LIKE.is_match(trimmed).unwrap_or(false) {
        return true;
    }
    if COORD_PAIR.is_match(trimmed).unwrap_or(false) {
        return true;
    }

    let digit_count = trimmed.chars().filter(|c| c.is_ascii_digit()).count();
    // ITU E.164 significant digits are typically 8–15; shorter runs are IDs/issues.
    if !(8..=15).contains(&digit_count) {
        return true;
    }

    let dot_count = trimmed.chars().filter(|&c| c == '.').count();
    // Version / IP-like dotted quads; phones rarely need 3+ dots.
    if dot_count >= 3 {
        return true;
    }

    // Bare digit runs are almost always order/issue IDs, not phone numbers.
    // Formatted or `+`-prefixed numbers are required after the regex tighten.
    if trimmed.chars().all(|c| c.is_ascii_digit()) {
        return true;
    }

    false
}

fn should_reject_card(value: &str) -> bool {
    let digits: Vec<u32> = value.chars().filter_map(|c| c.to_digit(10)).collect();
    if !(13..=19).contains(&digits.len()) {
        return true;
    }
    let mut sum = 0u32;
    for (offset, digit) in digits.into_iter().rev().enumerate() {
        if offset % 2 == 0 {
            sum += digit;
        } else {
            let doubled = digit * 2;
            sum += if doubled > 9 { doubled - 9 } else { doubled };
        }
    }
    sum % 10 != 0
}

fn should_reject_iban(value: &str) -> bool {
    let normalized: String = value
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .map(|c| c.to_ascii_uppercase())
        .collect();
    if !(15..=34).contains(&normalized.len()) {
        return true;
    }
    let rearranged = format!("{}{}", &normalized[4..], &normalized[..4]);
    let mut remainder = 0u32;
    for ch in rearranged.chars() {
        let digits: Vec<u32> = if ch.is_ascii_digit() {
            vec![ch.to_digit(10).unwrap()]
        } else {
            let mapped = u32::from(ch) - 55;
            vec![mapped / 10, mapped % 10]
        };
        for d in digits {
            remainder = (remainder * 10 + d) % 97;
        }
    }
    remainder != 1
}

fn should_reject_jwt(value: &str) -> bool {
    let segments: Vec<&str> = value.split('.').collect();
    if segments.len() != 3 {
        return true;
    }
    let Ok(header) = URL_SAFE_NO_PAD.decode(segments[0].as_bytes()) else {
        return true;
    };
    let Ok(json) = serde_json::from_slice::<serde_json::Value>(&header) else {
        return true;
    };
    json.get("alg").is_none()
}

fn should_reject_high_entropy(value: &str) -> bool {
    if is_likely_source_identifier(value) {
        return true;
    }
    if value.contains('/') && !value.contains('+') && !value.contains('=') {
        return true;
    }
    let has_secret_signal = value
        .chars()
        .any(|c| c.is_ascii_digit() || c == '+' || c == '=');
    !has_secret_signal
}

fn is_likely_source_identifier(value: &str) -> bool {
    let Some(first) = value.chars().next() else {
        return false;
    };
    if !(first.is_ascii_alphabetic() || first == '_') {
        return false;
    }
    value
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_')
}

fn is_placeholder(value: &str) -> bool {
    const MARKERS: &[&str] = &[
        "your",
        "example",
        "placeholder",
        "changeme",
        "change_me",
        "redacted",
        "dummy",
        "insert",
        "todo",
        "fixme",
        "xxxx",
        "yyyy",
        "notarealkey",
    ];
    if value.contains('<') || value.contains('>') {
        return true;
    }
    if value.contains("{{") || value.contains("${") || value.contains("%(") {
        return true;
    }
    if value.contains("****") || value.contains("....") {
        return true;
    }
    let lower = value.to_ascii_lowercase();
    MARKERS.iter().any(|m| lower.contains(m))
}
