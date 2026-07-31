use crate::overlap;
use crate::rules::BUILTIN_RULES;
use crate::sanitizers;
use crate::types::{
    CustomDictionaryItem, CustomDictionaryKind, DetectionRequest, DetectionResult,
    DetectionSource, EntityType, SensitiveEntity,
};
use fancy_regex::Regex;
use once_cell::sync::Lazy;
use std::collections::HashSet;

const MAX_OVERLAP: usize = 8192;

struct RuleMeta {
    entity_type: EntityType,
    source: DetectionSource,
    confidence: f64,
}

static COMPILED: Lazy<Vec<(RuleMeta, Regex)>> = Lazy::new(|| {
    BUILTIN_RULES
        .iter()
        .filter_map(|rule| match Regex::new(&rule.pattern) {
            Ok(re) => Some((
                RuleMeta {
                    entity_type: rule.entity_type,
                    source: rule.source,
                    confidence: rule.confidence,
                },
                re,
            )),
            Err(err) => {
                eprintln!(
                    "offsend-detect: failed to compile {:?}: {err}",
                    rule.entity_type
                );
                None
            }
        })
        .collect()
});

pub struct DetectionEngine;

impl DetectionEngine {
    pub fn scan(request: &DetectionRequest) -> DetectionResult {
        let text = &request.text;
        let was_truncated = text.chars().count() > request.options.maximum_length;
        if text.is_empty() {
            return DetectionResult {
                entities: vec![],
                scanned_text: String::new(),
                was_truncated: false,
                scanned_character_count: 0,
            };
        }

        let window = request.options.maximum_length.max(1);
        let mut entities = scan_rules(text, window, &request.options.enabled_types);
        entities.extend(scan_custom_dictionaries(
            text,
            window,
            &request.options.enabled_types,
            &request.options.custom_dictionaries,
        ));
        entities = overlap::resolve(entities);
        for e in &mut entities {
            if e.end <= text.len() && e.start <= e.end && text.is_char_boundary(e.start) && text.is_char_boundary(e.end) {
                e.value = text[e.start..e.end].to_string();
            }
        }
        entities = sanitizers::filter_false_positives(entities);
        entities = sanitizers::filter_inside_seal_tokens(entities, text);
        if request.options.honor_inline_ignore {
            entities = filter_inline_ignored(entities, text);
        }

        DetectionResult {
            scanned_character_count: text.chars().count(),
            entities,
            scanned_text: text.clone(),
            was_truncated,
        }
    }
}

fn scan_rules(text: &str, window: usize, enabled: &HashSet<EntityType>) -> Vec<SensitiveEntity> {
    let rules: Vec<_> = COMPILED
        .iter()
        .filter(|(meta, _)| enabled.contains(&meta.entity_type))
        .collect();

    window_scan(text, window, |slice_start, slice| {
        let mut found = Vec::new();
        for (meta, re) in &rules {
            for m in re.find_iter(slice) {
                let Ok(m) = m else { continue };
                let start = slice_start + m.start();
                let end = slice_start + m.end();
                found.push(SensitiveEntity {
                    id: uuid::Uuid::new_v4(),
                    entity_type: meta.entity_type,
                    start,
                    end,
                    value: text.get(start..end).unwrap_or("").to_string(),
                    confidence: meta.confidence,
                    source: meta.source,
                });
            }
        }
        found
    })
}

fn scan_custom_dictionaries(
    text: &str,
    window: usize,
    enabled: &HashSet<EntityType>,
    dictionaries: &[CustomDictionaryItem],
) -> Vec<SensitiveEntity> {
    let compiled: Vec<(EntityType, Regex)> = dictionaries
        .iter()
        .filter(|item| enabled.contains(&item.kind.entity_type()))
        .filter_map(|item| compile_custom_dictionary(item).map(|re| (item.kind.entity_type(), re)))
        .collect();
    if compiled.is_empty() {
        return Vec::new();
    }

    window_scan(text, window, |slice_start, slice| {
        let mut found = Vec::new();
        for (entity_type, re) in &compiled {
            for m in re.find_iter(slice) {
                let Ok(m) = m else { continue };
                let start = slice_start + m.start();
                let end = slice_start + m.end();
                found.push(SensitiveEntity {
                    id: uuid::Uuid::new_v4(),
                    entity_type: *entity_type,
                    start,
                    end,
                    value: text.get(start..end).unwrap_or("").to_string(),
                    confidence: 0.95,
                    source: DetectionSource::CustomDictionary,
                });
            }
        }
        found
    })
}

fn compile_custom_dictionary(item: &CustomDictionaryItem) -> Option<Regex> {
    let trimmed = item.value.trim();
    if trimmed.is_empty() {
        return None;
    }
    let pattern = match item.kind {
        CustomDictionaryKind::Regex => {
            // Case-insensitive, matching NSRegularExpression [.caseInsensitive].
            format!("(?i){trimmed}")
        }
        CustomDictionaryKind::InternalDomain => {
            let escaped = escape_regex_literal(trimmed);
            format!(r"(?<![A-Za-z0-9.-]){escaped}(?![A-Za-z0-9.-])")
        }
        _ => {
            let escaped = escape_regex_literal(trimmed);
            format!(r"\b{escaped}\b")
        }
    };
    Regex::new(&pattern).ok()
}

fn escape_regex_literal(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for ch in value.chars() {
        match ch {
            '\\' | '.' | '+' | '*' | '?' | '(' | ')' | '[' | ']' | '{' | '}' | '|' | '^' | '$' => {
                out.push('\\');
                out.push(ch);
            }
            _ => out.push(ch),
        }
    }
    out
}

/// Honors inline opt-outs:
///   `… secret …   # offsend:ignore`            suppresses findings on that line
///   `# offsend:ignore-next-line`                suppresses findings on the following line
fn filter_inline_ignored(entities: Vec<SensitiveEntity>, text: &str) -> Vec<SensitiveEntity> {
    const TOKEN: &str = "offsend:ignore";
    const NEXT_LINE_TOKEN: &str = "offsend:ignore-next-line";
    if !text.contains(TOKEN) {
        return entities;
    }
    let lines: Vec<&str> = text.split('\n').collect();
    entities
        .into_iter()
        .filter(|entity| {
            let line_index = line_index_at(text, entity.start);
            let line = lines.get(line_index).copied().unwrap_or("");
            if line.contains(TOKEN) && !line.contains(NEXT_LINE_TOKEN) {
                return false;
            }
            if line_index > 0 && lines[line_index - 1].contains(NEXT_LINE_TOKEN) {
                return false;
            }
            true
        })
        .collect()
}

fn line_index_at(text: &str, byte_offset: usize) -> usize {
    let end = byte_offset.min(text.len());
    text[..end].bytes().filter(|&b| b == b'\n').count()
}

fn window_scan(
    text: &str,
    window: usize,
    mut body: impl FnMut(usize, &str) -> Vec<SensitiveEntity>,
) -> Vec<SensitiveEntity> {
    let length = text.len();
    let window_size = window.max(1);
    if length <= window_size {
        return body(0, text);
    }

    let overlap = MAX_OVERLAP.min((window_size / 2).max(1));
    let step = (window_size - overlap).max(1);
    let mut results = Vec::new();
    let mut seen = HashSet::new();
    let mut start = 0;
    while start < length {
        let end = (start + window_size).min(length);
        let start_ch = floor_char_boundary(text, start);
        let end_ch = ceil_char_boundary(text, end);
        let slice = &text[start_ch..end_ch];
        for entity in body(start_ch, slice) {
            let key = format!(
                "{}:{}:{:?}:{:?}",
                entity.start, entity.end, entity.entity_type, entity.source
            );
            if seen.insert(key) {
                results.push(entity);
            }
        }
        if end >= length {
            break;
        }
        start += step;
    }
    results
}

fn floor_char_boundary(s: &str, i: usize) -> usize {
    if i >= s.len() {
        return s.len();
    }
    let mut i = i;
    while i > 0 && !s.is_char_boundary(i) {
        i -= 1;
    }
    i
}

fn ceil_char_boundary(s: &str, i: usize) -> usize {
    if i >= s.len() {
        return s.len();
    }
    let mut i = i;
    while i < s.len() && !s.is_char_boundary(i) {
        i += 1;
    }
    i
}
