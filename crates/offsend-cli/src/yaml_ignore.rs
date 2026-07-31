//! YAML ignore.patterns merge helpers.

use offsend_policy::{ManagedIgnoreBlock, DEFAULT_IGNORE_PATTERNS};
use std::fs;
use std::path::Path;

/// Merge patterns into `.offsend.yml` `ignore.patterns` (creates section if needed).
pub fn merge_ignore_patterns(
    config_path: &Path,
    patterns: &[String],
) -> Result<Vec<String>, String> {
    let normalized = ManagedIgnoreBlock::normalize_patterns(patterns);
    if normalized.is_empty() {
        return Ok(vec![]);
    }
    let existing = if config_path.is_file() {
        fs::read_to_string(config_path).map_err(|e| e.to_string())?
    } else {
        return Err(format!(
            "No .offsend.yml at {}. Run `offsend init` first.",
            config_path.display()
        ));
    };

    let mut cfg: offsend_policy::OffsendProjectConfig =
        offsend_policy::OffsendProjectConfig::parse_yaml(&existing).map_err(|e| e.to_string())?;

    let mut current = cfg
        .ignore
        .as_ref()
        .and_then(|i| i.patterns.clone())
        .unwrap_or_default();
    let mut added = Vec::new();
    for p in normalized {
        if !current.iter().any(|c| c == &p) {
            current.push(p.clone());
            added.push(p);
        }
    }
    if added.is_empty() {
        return Ok(vec![]);
    }

    let mut ignore = cfg.ignore.unwrap_or_default();
    ignore.patterns = Some(current);
    cfg.ignore = Some(ignore);

    let yaml = serde_yaml::to_string(&cfg).map_err(|e| e.to_string())?;
    // Prefer preserving header comment if present.
    let out = if existing.trim_start().starts_with('#') {
        let header: String = existing
            .lines()
            .take_while(|l| l.trim().is_empty() || l.trim_start().starts_with('#'))
            .map(|l| format!("{l}\n"))
            .collect();
        format!("{header}{yaml}")
    } else {
        yaml
    };
    fs::write(config_path, out).map_err(|e| e.to_string())?;
    Ok(added)
}

pub fn merge_default_ignore_patterns(config_path: &Path) -> Result<Vec<String>, String> {
    let defaults: Vec<String> = DEFAULT_IGNORE_PATTERNS
        .iter()
        .map(|s| (*s).to_string())
        .collect();
    merge_ignore_patterns(config_path, &defaults)
}
