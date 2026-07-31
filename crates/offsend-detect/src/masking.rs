//! Placeholder masking — port of Swift `MaskingEngine` (ranges + mapping only; TTL stays in the host).

use crate::types::EntityType;
use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MaskSpan {
    pub start: usize,
    pub end: usize,
    pub value: String,
    pub entity_type: EntityType,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MaskResult {
    pub masked_text: String,
    /// placeholder → original value
    pub mapping: HashMap<String, String>,
}

pub fn mask_text(text: &str, spans: &[MaskSpan]) -> MaskResult {
    let mut ordered: Vec<&MaskSpan> = spans.iter().collect();
    ordered.sort_by_key(|s| s.start);

    let mut counters: HashMap<&'static str, usize> = HashMap::new();
    let mut placeholder_by_value: HashMap<String, String> = HashMap::new();
    let mut replacements: Vec<(usize, usize, String)> = Vec::new();
    let mut covered_end: Option<usize> = None;

    for span in ordered {
        if span.start > span.end || span.end > text.len() {
            continue;
        }
        if !text.is_char_boundary(span.start) || !text.is_char_boundary(span.end) {
            continue;
        }
        if &text[span.start..span.end] != span.value {
            continue;
        }
        if let Some(end) = covered_end {
            if span.start < end {
                continue;
            }
        }

        let placeholder = if let Some(existing) = placeholder_by_value.get(&span.value) {
            existing.clone()
        } else {
            let prefix = span.entity_type.placeholder_prefix();
            let next = counters.get(prefix).copied().unwrap_or(0) + 1;
            counters.insert(prefix, next);
            let ph = format!("{{{{{prefix}_{next}}}}}");
            placeholder_by_value.insert(span.value.clone(), ph.clone());
            ph
        };
        replacements.push((span.start, span.end, placeholder));
        covered_end = Some(covered_end.map(|e| e.max(span.end)).unwrap_or(span.end));
    }

    let mut masked = text.to_string();
    for (start, end, placeholder) in replacements.into_iter().rev() {
        masked.replace_range(start..end, &placeholder);
    }

    let mapping = placeholder_by_value
        .into_iter()
        .map(|(value, placeholder)| (placeholder, value))
        .collect();

    MaskResult {
        masked_text: masked,
        mapping,
    }
}

pub fn restore_text(text: &str, mapping: &HashMap<String, String>) -> String {
    let mut restored = text.to_string();
    for (placeholder, value) in mapping {
        restored = restored.replace(placeholder, value);
    }
    restored
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::EntityType;

    #[test]
    fn masks_and_restores_email() {
        let text = "hi user@example.com bye";
        let start = text.find("user@example.com").unwrap();
        let end = start + "user@example.com".len();
        let result = mask_text(
            text,
            &[MaskSpan {
                start,
                end,
                value: "user@example.com".into(),
                entity_type: EntityType::Email,
            }],
        );
        assert!(result.masked_text.contains("{{EMAIL_1}}"));
        assert!(!result.masked_text.contains("user@example.com"));
        let restored = restore_text(&result.masked_text, &result.mapping);
        assert_eq!(restored, text);
    }
}
