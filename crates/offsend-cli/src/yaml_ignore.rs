//! YAML ignore.patterns merge helpers.

use offsend_policy::{ManagedIgnoreBlock, DEFAULT_IGNORE_PATTERNS};
use std::fs;
use std::path::Path;

/// Merge patterns into `.offsend.yml` `ignore.patterns` (creates section if needed).
///
/// Edits the file line-by-line instead of re-serializing the parsed config:
/// a serde round-trip drops every comment, reorders keys, and silently deletes
/// unknown keys — destroying hand-maintained configs.
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

    let cfg: offsend_policy::OffsendProjectConfig =
        offsend_policy::OffsendProjectConfig::parse_yaml(&existing).map_err(|e| e.to_string())?;

    let current = cfg
        .ignore
        .as_ref()
        .and_then(|i| i.patterns.clone())
        .unwrap_or_default();
    let added: Vec<String> = normalized
        .into_iter()
        .filter(|p| !current.iter().any(|c| c == p))
        .collect();
    if added.is_empty() {
        return Ok(vec![]);
    }

    let out = insert_ignore_patterns(&existing, &current, &added)?;
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

/// Inserts `added` into the `ignore.patterns` list, touching as few lines as
/// possible so comments and formatting elsewhere survive.
fn insert_ignore_patterns(
    yaml: &str,
    current: &[String],
    added: &[String],
) -> Result<String, String> {
    let mut lines: Vec<String> = yaml.split('\n').map(str::to_string).collect();
    // `split` yields a trailing "" when the file ends with a newline.
    if lines.last().is_some_and(String::is_empty) {
        lines.pop();
    }

    let is_top_level_key = |l: &str| {
        !l.is_empty() && !l.starts_with(' ') && !l.starts_with('\t') && !l.starts_with('#')
    };

    let ignore_idx = lines
        .iter()
        .position(|l| is_top_level_key(l) && l.trim_end().starts_with("ignore:"));

    let Some(ii) = ignore_idx else {
        if lines.last().is_some_and(|l| !l.is_empty()) {
            lines.push(String::new());
        }
        lines.push("ignore:".into());
        lines.push("  patterns:".into());
        lines.extend(added.iter().map(|p| format!("    - {}", quote(p))));
        return Ok(finish(lines));
    };

    let remainder = lines[ii].trim()["ignore:".len()..].trim().to_string();
    if remainder == "{}" {
        lines[ii] = "ignore:".into();
    } else if !remainder.is_empty() && !remainder.starts_with('#') {
        return Err(
            "cannot merge patterns into an inline `ignore:` mapping; use block style".into(),
        );
    }

    let section_end = lines[ii + 1..]
        .iter()
        .position(|l| is_top_level_key(l))
        .map(|off| ii + 1 + off)
        .unwrap_or(lines.len());

    let pat_idx = (ii + 1..section_end).find(|&i| lines[i].trim_start().starts_with("patterns:"));

    let Some(pi) = pat_idx else {
        let mut insertion = vec!["  patterns:".to_string()];
        insertion.extend(added.iter().map(|p| format!("    - {}", quote(p))));
        lines.splice(ii + 1..ii + 1, insertion);
        return Ok(finish(lines));
    };

    let key_indent: String = lines[pi].chars().take_while(|c| *c == ' ').collect();
    let after = lines[pi].trim_start()["patterns:".len()..].trim().to_string();
    if !after.is_empty() && !after.starts_with('#') {
        // Flow list (`patterns: []` / `patterns: [a, b]`) — replace the single
        // line with a block list carrying current + added.
        let mut repl = vec![format!("{key_indent}patterns:")];
        repl.extend(
            current
                .iter()
                .chain(added.iter())
                .map(|p| format!("{key_indent}  - {}", quote(p))),
        );
        lines.splice(pi..pi + 1, repl);
        return Ok(finish(lines));
    }

    // Block list: append after the last existing item, matching its indent.
    let mut last_item: Option<usize> = None;
    let mut item_indent: Option<String> = None;
    for (i, line) in lines.iter().enumerate().take(section_end).skip(pi + 1) {
        let t = line.trim_start();
        if t.starts_with('-') {
            last_item = Some(i);
            if item_indent.is_none() {
                item_indent = Some(line.chars().take_while(|c| *c == ' ').collect());
            }
        } else if t.is_empty() || t.starts_with('#') {
            continue;
        } else {
            break;
        }
    }
    let indent = item_indent.unwrap_or_else(|| format!("{key_indent}  "));
    let at = last_item.map(|i| i + 1).unwrap_or(pi + 1);
    let insertion: Vec<String> = added
        .iter()
        .map(|p| format!("{indent}- {}", quote(p)))
        .collect();
    lines.splice(at..at, insertion);
    Ok(finish(lines))
}

fn quote(pattern: &str) -> String {
    format!("\"{}\"", pattern.replace('"', "\\\""))
}

fn finish(lines: Vec<String>) -> String {
    let mut s = lines.join("\n");
    if !s.ends_with('\n') {
        s.push('\n');
    }
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    fn merged(yaml: &str, added: &[&str]) -> String {
        let cfg = offsend_policy::OffsendProjectConfig::parse_yaml(yaml).unwrap();
        let current = cfg
            .ignore
            .as_ref()
            .and_then(|i| i.patterns.clone())
            .unwrap_or_default();
        let added: Vec<String> = added.iter().map(|s| (*s).to_string()).collect();
        insert_ignore_patterns(yaml, &current, &added).unwrap()
    }

    #[test]
    fn preserves_comments_and_appends_to_block_list() {
        let yaml = "version: 1\n\n# custom header comment\ncheck:\n  fail_on: block\n  # detector note\n  detectors:\n    disable: [email]\n\nignore:\n  commit: false\n  patterns:\n    - \".env*\"\n    # keep keys out\n    - \"*.pem\"\n\nhooks:\n  enabled: true\n";
        let out = merged(yaml, &["*.key"]);
        assert!(out.contains("# custom header comment"));
        assert!(out.contains("# detector note"));
        assert!(out.contains("# keep keys out"));
        // new pattern appended after the last item, same indent
        let pem = out.find("- \"*.pem\"").unwrap();
        let key = out.find("- \"*.key\"").unwrap();
        assert!(key > pem);
        // still valid YAML with the pattern present
        let cfg = offsend_policy::OffsendProjectConfig::parse_yaml(&out).unwrap();
        let patterns = cfg.ignore.unwrap().patterns.unwrap();
        assert!(patterns.contains(&"*.key".to_string()));
        assert!(patterns.contains(&".env*".to_string()));
    }

    #[test]
    fn creates_ignore_section_when_missing() {
        let yaml = "version: 1\ncheck:\n  fail_on: block\n";
        let out = merged(yaml, &["*.pem"]);
        let cfg = offsend_policy::OffsendProjectConfig::parse_yaml(&out).unwrap();
        assert_eq!(cfg.ignore.unwrap().patterns.unwrap(), vec!["*.pem"]);
        assert!(out.contains("check:\n  fail_on: block"));
    }

    #[test]
    fn adds_patterns_key_inside_existing_section() {
        let yaml = "version: 1\nignore:\n  commit: true\nhooks:\n  enabled: true\n";
        let out = merged(yaml, &["*.pem"]);
        let cfg = offsend_policy::OffsendProjectConfig::parse_yaml(&out).unwrap();
        let ignore = cfg.ignore.unwrap();
        assert_eq!(ignore.patterns.unwrap(), vec!["*.pem"]);
        assert_eq!(ignore.commit, Some(true));
    }

    #[test]
    fn converts_inline_flow_list() {
        let yaml = "version: 1\nignore:\n  patterns: [\".env\"]\n";
        let out = merged(yaml, &["*.pem"]);
        let cfg = offsend_policy::OffsendProjectConfig::parse_yaml(&out).unwrap();
        assert_eq!(cfg.ignore.unwrap().patterns.unwrap(), vec![".env", "*.pem"]);
    }

    #[test]
    fn merge_is_noop_when_pattern_present() {
        let dir = std::env::temp_dir().join(format!("offsend-yamlmerge-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join(".offsend.yml");
        let yaml = "version: 1\n# comment\nignore:\n  patterns:\n    - \".env\"\n";
        std::fs::write(&path, yaml).unwrap();
        let added = merge_ignore_patterns(&path, &[".env".into()]).unwrap();
        assert!(added.is_empty());
        assert_eq!(std::fs::read_to_string(&path).unwrap(), yaml);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
