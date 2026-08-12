//! Built-in rules loaded from Swift-extracted base64 corpus
//! (`data/swift_rules.b64.json`) so plaintext patterns stay out of source.

use crate::types::{DetectionSource, EntityType};
use base64::engine::general_purpose::STANDARD;
use base64::Engine as _;
use once_cell::sync::Lazy;
use serde::Deserialize;

#[derive(Debug, Clone)]
pub struct Rule {
    pub entity_type: EntityType,
    pub source: DetectionSource,
    pub confidence: f64,
    pub pattern: String,
}

#[derive(Deserialize)]
struct RuleRow {
    #[serde(rename = "type")]
    type_name: String,
    source: String,
    confidence: f64,
    pattern_b64: String,
    #[serde(default = "default_case_insensitive")]
    case_insensitive: bool,
}

fn default_case_insensitive() -> bool {
    true
}

pub static BUILTIN_RULES: Lazy<Vec<Rule>> = Lazy::new(|| {
    // Base corpus extracted from Swift, plus additional high-precision provider
    // detectors kept in the same base64 form (out of plaintext source).
    let base = include_str!("../data/swift_rules.b64.json");
    let extra = include_str!("../data/extra_rules.b64.json");
    let mut rules = decode_rows(base, "swift_rules.b64.json");
    rules.extend(decode_rows(extra, "extra_rules.b64.json"));
    rules
});

fn decode_rows(raw: &str, source_name: &str) -> Vec<Rule> {
    let rows: Vec<RuleRow> =
        serde_json::from_str(raw).unwrap_or_else(|e| panic!("{source_name}: {e}"));
    rows.into_iter()
        .filter_map(|row| {
            let entity_type = EntityType::from_swift_name(&row.type_name)?;
            let source = DetectionSource::from_swift_name(&row.source)?;
            let bytes = STANDARD.decode(row.pattern_b64.as_bytes()).ok()?;
            let pattern = String::from_utf8(bytes).ok()?;
            let pattern = if row.case_insensitive && !pattern.starts_with("(?i)") {
                format!("(?i){pattern}")
            } else {
                pattern
            };
            Some(Rule {
                entity_type,
                source,
                confidence: row.confidence,
                pattern,
            })
        })
        .collect()
}
