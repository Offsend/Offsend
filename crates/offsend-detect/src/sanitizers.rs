use crate::types::{EntityType, HighEntropySensitivity, SensitiveEntity};
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
/// Inner `TYPE:v1.<payload>` shape of a seal token (without `{{` / `}}`).
/// `apiKeyGeneric`'s `secret\s*[:=]\s*…` pattern matches `SECRET:v1.…` framing.
static SEAL_TOKEN_INNER: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)^[A-Z][A-Z0-9_]*:v1\.[A-Za-z0-9_-]+$").unwrap()
});

pub fn filter_false_positives(
    entities: Vec<SensitiveEntity>,
    sensitivity: HighEntropySensitivity,
) -> Vec<SensitiveEntity> {
    entities
        .into_iter()
        .filter(|e| match e.entity_type {
            EntityType::Money => !should_reject_money(&e.value),
            EntityType::Phone => !should_reject_phone(&e.value),
            EntityType::CreditCardLike => !should_reject_card(&e.value),
            EntityType::Iban => !should_reject_iban(&e.value),
            EntityType::Jwt => !should_reject_jwt(&e.value),
            EntityType::HighEntropyString => {
                !is_too_short(&e.value, sensitivity) && !should_reject_high_entropy(&e.value)
            }
            t if t.is_secret() => !is_placeholder(&e.value),
            _ => true,
        })
        .collect()
}

/// Seal payloads are ciphertext, not live secrets/PII. Drop findings fully inside
/// `{{TYPE:v1.…}}` except concrete secret detectors whose value is *not* the seal
/// framing itself (so a live key wrapped in a fake token still fires). High-entropy,
/// phone/email on base64url, and `apiKeyGeneric` on `SECRET:v1.…` are the common
/// false positives this removes.
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
            let inside = ranges
                .iter()
                .any(|&(start, end)| e.start >= start && e.end <= end);
            if !inside {
                return true;
            }
            // Keep critical secrets embedded in the payload (e.g. AKIA…), but drop
            // detectors that matched the TYPE:v1.… seal structure as a key=value pair.
            e.entity_type.counts_as_critical_secret() && !is_seal_token_structure(&e.value)
        })
        .collect()
}

fn is_seal_token_structure(value: &str) -> bool {
    SEAL_TOKEN_INNER.is_match(value).unwrap_or(false)
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

/// Thresholds measured on random hex/base36/base62/base64 vs identifiers and slugs:
/// random hex stays above 3.15 bits/char, other random alphabets above 3.9, and
/// random strings keep word coverage under 0.5 while names/slugs sit at 0.5+.
/// Real paths sit at 0.4+, while random base64 with `/` stays under 0.3.
const MIN_HEX_ENTROPY: f64 = 3.0;
const MIN_ENTROPY: f64 = 3.5;
const MAX_WORD_COVERAGE: f64 = 0.5;
const MAX_PATH_WORD_COVERAGE: f64 = 0.3;
/// Charset literals (`abc…xyzABC…0123…`) step by one code point almost everywhere.
const MAX_SEQUENTIAL_PAIRS: f64 = 0.5;

/// Standalone tokens with symbols (passwords): measured on generated passwords vs
/// every whole-line token of this repository (code, docs, vendored Python, plists).
const MIN_SYMBOL_ENTROPY: f64 = 3.0;
const MAX_SYMBOL_WORD_COVERAGE: f64 = 0.4;
const MIN_CLASS_TRANSITIONS: f64 = 0.45;

/// Letter runs that read like words: `user`, `Account`, `RELEASE`.
static WORD_RUN: Lazy<Regex> = Lazy::new(|| Regex::new(r"[A-Z]?[a-z]{4,}|[A-Z]{5,}").unwrap());

/// Shapes of code, markup and structured values that random passwords almost never contain.
static CODE_OR_STRUCTURED: Lazy<Vec<Regex>> = Lazy::new(|| {
    [
        // URL
        r"(?i)://|^www\.|^mailto:",
        // email
        r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}",
        // path
        r"^(?:~|\.{1,2})?/",
        // XML / HTML tag
        r"</?[A-Za-z][A-Za-z0-9]*>",
        // regex group or character range
        r"\(\?|\[[^\]]*[0-9a-zA-Z]-[0-9a-zA-Z][^\]]*\]",
        // call: `name_by_id(`, `Self(`
        r"(?<![A-Za-z0-9])[A-Za-z_][A-Za-z0-9_]{4,}\(|(?<![A-Za-z0-9])[A-Z][a-z]{2,}\(",
        // member access: `a.method`, `Type::item`, `ptr->field`
        r"[A-Za-z_][A-Za-z0-9_]*(?:\.|::|->)[A-Za-z_][A-Za-z0-9_]{3,}",
        // index / slice: `[0]`, `[2:-1]`
        r"\[-?\d*:?-?\d*\]",
        // date / time
        r"\d{4}-\d{2}-\d{2}|\d{1,2}:\d{2}:\d{2}",
        // version, IP, decimal
        r"\d+\.\d+",
        // snake_case / SCREAMING_CASE identifier
        r"[A-Za-z0-9]{2,}_[A-Za-z0-9]{2,}_[A-Za-z0-9]{2,}",
    ]
    .iter()
    .map(|p| Regex::new(p).unwrap())
    .collect()
});

fn is_base_alphabet(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '+' | '/' | '=' | '_' | '-')
}

fn is_too_short(value: &str, sensitivity: HighEntropySensitivity) -> bool {
    let min = if value.chars().all(is_base_alphabet) {
        sensitivity.min_base_length()
    } else {
        sensitivity.min_symbol_length()
    };
    value.chars().count() < min
}

fn should_reject_high_entropy(value: &str) -> bool {
    if !value.chars().all(is_base_alphabet) {
        return should_reject_symbol_secret(value);
    }
    let has_secret_signal = value
        .chars()
        .any(|c| c.is_ascii_digit() || c == '+' || c == '=');
    if !has_secret_signal {
        return true;
    }
    let min_entropy = if value.chars().all(|c| c.is_ascii_hexdigit()) {
        MIN_HEX_ENTROPY
    } else {
        MIN_ENTROPY
    };
    if shannon_entropy(value) < min_entropy || sequential_pair_ratio(value) >= MAX_SEQUENTIAL_PAIRS {
        return true;
    }
    let coverage = word_coverage(value);
    let path_like = value.contains('/') && !value.contains('+') && !value.contains('=');
    coverage >= MAX_WORD_COVERAGE || (path_like && coverage >= MAX_PATH_WORD_COVERAGE)
}

fn should_reject_symbol_secret(value: &str) -> bool {
    let has_letter = value.chars().any(|c| c.is_ascii_alphabetic());
    let has_digit = value.chars().any(|c| c.is_ascii_digit());
    if !has_letter || !has_digit {
        return true;
    }
    // Code lines end with `,` `;` `:`; backslashes are escapes or Windows paths.
    if value.ends_with([',', ';', ':']) || value.contains('\\') || has_single_delimiter(value) {
        return true;
    }
    if CODE_OR_STRUCTURED
        .iter()
        .any(|re| re.is_match(value).unwrap_or(true))
    {
        return true;
    }
    shannon_entropy(value) < MIN_SYMBOL_ENTROPY
        || word_coverage(value) >= MAX_SYMBOL_WORD_COVERAGE
        || class_transition_ratio(value) < MIN_CLASS_TRANSITIONS
}

/// `a:b:c:d`, `1-2-3-4`: every separator is the same character.
fn has_single_delimiter(value: &str) -> bool {
    let mut symbols = value.chars().filter(|c| !c.is_ascii_alphanumeric());
    let Some(first) = symbols.next() else {
        return false;
    };
    let mut count = 1;
    for c in symbols {
        if c != first {
            return false;
        }
        count += 1;
    }
    count >= 3
}

/// Share of adjacent pairs that switch between lowercase, uppercase, digit and symbol.
fn class_transition_ratio(value: &str) -> f64 {
    fn class(c: char) -> u8 {
        if c.is_ascii_lowercase() {
            0
        } else if c.is_ascii_uppercase() {
            1
        } else if c.is_ascii_digit() {
            2
        } else {
            3
        }
    }
    let classes: Vec<u8> = value.chars().map(class).collect();
    if classes.len() < 2 {
        return 0.0;
    }
    let switches = classes.windows(2).filter(|w| w[0] != w[1]).count();
    switches as f64 / (classes.len() - 1) as f64
}

/// Bits per byte.
fn shannon_entropy(value: &str) -> f64 {
    let mut counts = [0usize; 256];
    for b in value.bytes() {
        counts[b as usize] += 1;
    }
    let len = value.len() as f64;
    counts
        .iter()
        .filter(|&&c| c > 0)
        .map(|&c| {
            let p = c as f64 / len;
            -p * p.log2()
        })
        .sum()
}

fn sequential_pair_ratio(value: &str) -> f64 {
    let bytes = value.as_bytes();
    if bytes.len() < 2 {
        return 0.0;
    }
    let sequential = bytes.windows(2).filter(|w| w[1] == w[0].wrapping_add(1)).count();
    sequential as f64 / (bytes.len() - 1) as f64
}

/// Share of `value` covered by word-like letter runs. A run counts only with a
/// natural-language vowel ratio, so random lowercase stretches are not words.
fn word_coverage(value: &str) -> f64 {
    if value.is_empty() {
        return 0.0;
    }
    let covered: usize = WORD_RUN
        .find_iter(value)
        .filter_map(|m| m.ok())
        .map(|m| m.as_str())
        .filter(|run| {
            let vowels = run
                .chars()
                .filter(|c| matches!(c.to_ascii_lowercase(), 'a' | 'e' | 'i' | 'o' | 'u' | 'y'))
                .count();
            let ratio = vowels as f64 / run.len() as f64;
            (0.25..=0.65).contains(&ratio)
        })
        .map(str::len)
        .sum();
    covered as f64 / value.len() as f64
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn entropy_of_uniform_and_constant_strings() {
        assert_eq!(shannon_entropy("aaaaaaaa"), 0.0);
        assert!((shannon_entropy("0123456789abcdef") - 4.0).abs() < 1e-9);
        assert!((shannon_entropy("abab") - 1.0).abs() < 1e-9);
    }

    #[test]
    fn word_coverage_counts_only_pronounceable_runs() {
        assert!((word_coverage("release") - 1.0).abs() < 1e-9);
        assert!((word_coverage("UsersAccount") - 1.0).abs() < 1e-9);
        assert!((word_coverage("RELEASE") - 1.0).abs() < 1e-9);
        // Random lowercase runs without a natural vowel ratio are not words.
        assert_eq!(word_coverage("gjmwwftvxbmfqbqgd"), 0.0);
        // Runs shorter than five letters are ignored.
        assert_eq!(word_coverage("ab1cd2ef3"), 0.0);
        assert_eq!(word_coverage(""), 0.0);
    }

    #[test]
    fn rejects_by_shape_not_first_character() {
        // offsend:ignore-next-line
        let secret = "Zq8Lm3Xv7Rt2Yb9Kp4Wn6Hc1Jd5Fs0GaQe8UiO3Mx7Vz2NbT6";
        assert!(!should_reject_high_entropy(secret));
        assert!(!should_reject_high_entropy(&format!("8{secret}")));
        assert!(!should_reject_high_entropy(&format!("_{secret}")));
    }

    #[test]
    fn hex_uses_lower_entropy_floor() {
        // 3.0..3.5 bits: kept for hex, rejected for other alphabets.
        // offsend:ignore-next-line
        let hex = "0371526403715264037152640371526403715264";
        assert!(shannon_entropy(hex) >= MIN_HEX_ENTROPY && shannon_entropy(hex) < MIN_ENTROPY);
        assert!(!should_reject_high_entropy(hex));
        let not_hex = "0371526g0371526g0371526g0371526g0371526g";
        assert!(should_reject_high_entropy(not_hex));
    }

    #[test]
    fn rejects_charset_literals() {
        assert!(should_reject_high_entropy(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        ));
        assert!(should_reject_high_entropy(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz+/"
        ));
        // offsend:ignore-next-line
        assert!(sequential_pair_ratio("Zq8Lm3Xv7Rt2Yb9Kp4Wn6Hc1Jd5Fs0GaQe8UiO3Mx7Vz2NbT6") < 0.1);
    }

    #[test]
    fn symbol_secret_accepts_generated_passwords() {
        let passwords = [
            "Zq8$Lm3!Xv7#Rt2@Yb9%Kp4^Wn6&Hc1*Jd5(Fs0)Ga",
            "Zq8$Lm3!Xv7#Rt2@",
            "x7#Kp2!vQ9&mL4^z",
            "N3v3r$h@r3-Th1s!",
            "R5&tY8*uI1(oP3)a",
            "aB3$dE5^fG7&hI9*",
            "4hT!9qZ%2mW^7xK&8",
            "Gq7}k2~Vb9|Lx4<Nz",
            "p@55W0rd!Zx81#Qm",
        ];
        for p in passwords {
            assert!(!should_reject_high_entropy(p), "expected secret: {p}");
        }
    }

    #[test]
    fn symbol_secret_requires_letters_and_digits() {
        assert!(should_reject_high_entropy("Zq$Lm!Xv#Rt@Yb%Kp^Wn&"));
        assert!(should_reject_high_entropy("12$34!56#78@90%12^34&"));
    }

    #[test]
    fn symbol_secret_rejects_code_markup_and_structured_values() {
        let samples = [
            "https://google.com/search?q=teszt1",
            "user@example.com:22",
            "~/Library/Caches/offsend-1.2",
            "C:\\Users\\me\\offsend2.exe",
            "<key>77FAE1A8-B98D-4B60-B1A8-B7CF93A8AAD9</key>",
            "(?P<dev_n>[0-9]+)?",
            "[a-zA-Z0-9_-]{20,}",
            "ExitCode::from(1)",
            "Self(kVK_ANSI_Keypad0)",
            "perms.set_mode(0o755)",
            "items[0].price*qty2",
            "$XDG_DATA_DIRS[0]",
            "2026-11-07T10:23:00Z",
            "192.168.0.1:8080/health",
            "v1.2.3-beta.4+build.5",
            "solaris-2.6-sun4u!",
            "45:14:0b:32:47:eb:9c:c8:c5:b4:f0:d7",
            "Node(UInt16.max),",
            "type[BaseExcT_1]:",
            "#[derive(Debug,Clone)]2",
            "certifi==2021.05.30",
            "Summer2024!Vacation#",
        ];
        for s in samples {
            assert!(should_reject_high_entropy(s), "unexpected secret: {s}");
        }
    }

    #[test]
    fn class_transitions_and_delimiters() {
        assert_eq!(class_transition_ratio("aaaa"), 0.0);
        assert!((class_transition_ratio("a1B$") - 1.0).abs() < 1e-9);
        assert!(has_single_delimiter("ab:cd:ef:01"));
        assert!(!has_single_delimiter("ab:cd-ef:01"));
        assert!(!has_single_delimiter("ab:cd"));
    }

    #[test]
    fn rejects_low_entropy_repetition() {
        assert!(should_reject_high_entropy("0000000000000000000000000000000000000000"));
        assert!(should_reject_high_entropy("abcdefabcdefabcdefabcdefabcdefabcdefabcdef12"));
        assert!(should_reject_high_entropy("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1"));
    }
}
