//! Claude Code `permissions.deny` from `ignore.patterns`.
//!
//! `.claudeignore` is not a Claude Code feature. `offsend sync` still writes
//! that file for other tools; Claude's real path lock is `permissions.deny`
//! in `.claude/settings.json`.

use crate::config::ToolId;
use serde_json::{json, Value};
use std::collections::HashSet;

pub const SETTINGS_RELATIVE: &str = ".claude/settings.json";
const MANAGED_DENY_KEY: &str = "_offsendClaudeDeny";

/// Whether this project's `ignore.tools` includes Claude (absent = all tools).
pub fn applies_to(tools: Option<&HashSet<ToolId>>) -> bool {
    tools.map(|t| t.contains(&ToolId::Claude)).unwrap_or(true)
}

/// `Read` / `Edit` / `Write` rules for one ignore pattern.
pub fn deny_rules_from_patterns(patterns: &[String]) -> Vec<String> {
    let mut rules = Vec::new();
    let mut seen = HashSet::new();
    for pattern in patterns {
        let Some(glob) = claude_path_glob(pattern) else {
            continue;
        };
        for tool in ["Read", "Edit", "Write"] {
            let rule = format!("{tool}({glob})");
            if seen.insert(rule.clone()) {
                rules.push(rule);
            }
        }
    }
    rules
}

/// Map a gitignore-style pattern to a Claude permission glob.
pub fn claude_path_glob(pattern: &str) -> Option<String> {
    let trimmed = pattern.trim();
    if trimmed.is_empty() || trimmed.starts_with('!') {
        return None;
    }
    if matches!(trimmed, "*" | "**" | "**/*" | "/**") {
        return None;
    }

    let mut glob = trimmed.strip_prefix('/').unwrap_or(trimmed).to_string();
    let is_dir = glob.ends_with('/');
    if is_dir {
        glob.pop();
        if glob.is_empty() {
            return None;
        }
    }

    if !glob.starts_with("**/") {
        glob = format!("**/{glob}");
    }
    if is_dir {
        glob.push_str("/**");
    }
    Some(glob)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ClaudeDenyUpsert {
    /// Serialized settings.json (pretty JSON + trailing newline).
    Written(String),
    Unchanged,
}

/// Merge managed deny rules into existing `.claude/settings.json` text.
///
/// Removes previously managed rules (listed in `_offsendClaudeDeny`), keeps
/// foreign entries such as `Bash(rm)`, then appends rules for `patterns`.
pub fn upsert(existing: Option<&str>, patterns: &[String]) -> Result<ClaudeDenyUpsert, String> {
    let rules = deny_rules_from_patterns(patterns);
    if existing.is_none() && rules.is_empty() {
        return Ok(ClaudeDenyUpsert::Unchanged);
    }

    let mut root: Value = match existing {
        Some(text) if !text.trim().is_empty() => {
            serde_json::from_str(text).map_err(|e| format!("invalid {SETTINGS_RELATIVE}: {e}"))?
        }
        _ => json!({}),
    };
    if !root.is_object() {
        root = json!({});
    }
    if root.get("permissions").is_some() && !root["permissions"].is_object() {
        return Err("permissions must be a JSON object".into());
    }
    if root
        .pointer("/permissions/deny")
        .is_some_and(|v| !v.is_array())
    {
        return Err("permissions.deny must be a JSON array".into());
    }

    let previous: HashSet<String> = root
        .get(MANAGED_DENY_KEY)
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default();

    let mut kept: Vec<Value> = root
        .pointer("/permissions/deny")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter(|v| v.as_str().map(|s| !previous.contains(s)).unwrap_or(true))
        .collect();
    let mut kept_strings: HashSet<String> = kept
        .iter()
        .filter_map(|v| v.as_str().map(str::to_string))
        .collect();
    for rule in &rules {
        if kept_strings.insert(rule.clone()) {
            kept.push(Value::String(rule.clone()));
        }
    }

    let obj = root
        .as_object_mut()
        .ok_or_else(|| format!("{SETTINGS_RELATIVE} must be a JSON object"))?;

    if rules.is_empty() {
        obj.remove(MANAGED_DENY_KEY);
        if kept.is_empty() {
            let drop_permissions = match obj.get_mut("permissions") {
                Some(Value::Object(perm)) => {
                    perm.remove("deny");
                    perm.is_empty()
                }
                _ => false,
            };
            if drop_permissions {
                obj.remove("permissions");
            }
        } else {
            set_deny_array(obj, kept)?;
        }
    } else {
        obj.insert(MANAGED_DENY_KEY.into(), json!(rules));
        set_deny_array(obj, kept)?;
    }

    if obj.is_empty() {
        if existing.is_none() {
            return Ok(ClaudeDenyUpsert::Unchanged);
        }
        // File existed; managed rules gone and nothing else left — leave a
        // minimal object rather than deleting the file (hooks may own it).
        root = json!({});
    }

    let mut text = serde_json::to_string_pretty(&root)
        .map_err(|e| format!("serialize {SETTINGS_RELATIVE}: {e}"))?;
    text.push('\n');
    if existing.is_some_and(|current| current == text) {
        return Ok(ClaudeDenyUpsert::Unchanged);
    }
    Ok(ClaudeDenyUpsert::Written(text))
}

fn set_deny_array(
    obj: &mut serde_json::Map<String, Value>,
    kept: Vec<Value>,
) -> Result<(), String> {
    let permissions = obj
        .entry("permissions".to_string())
        .or_insert_with(|| json!({}));
    let perm_obj = permissions
        .as_object_mut()
        .ok_or_else(|| "permissions must be a JSON object".to_string())?;
    perm_obj.insert("deny".into(), Value::Array(kept));
    Ok(())
}

/// Missing managed deny rules in an existing settings.json (empty if file absent).
pub fn missing_managed_rules(existing: Option<&str>, patterns: &[String]) -> Vec<String> {
    let expected = deny_rules_from_patterns(patterns);
    if expected.is_empty() {
        return Vec::new();
    }
    let Some(text) = existing else {
        return expected;
    };
    let Ok(root) = serde_json::from_str::<Value>(text) else {
        return expected;
    };
    let present: HashSet<String> = root
        .pointer("/permissions/deny")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|v| v.as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default();
    expected
        .into_iter()
        .filter(|r| !present.contains(r))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn env_star_maps_to_recursive_read_edit_write() {
        let rules = deny_rules_from_patterns(&[".env*".into()]);
        assert_eq!(
            rules,
            vec![
                "Read(**/.env*)".to_string(),
                "Edit(**/.env*)".to_string(),
                "Write(**/.env*)".to_string(),
            ]
        );
    }

    #[test]
    fn pem_and_ssh_dir() {
        assert_eq!(claude_path_glob("*.pem").as_deref(), Some("**/*.pem"));
        assert_eq!(claude_path_glob(".ssh/").as_deref(), Some("**/.ssh/**"));
        assert_eq!(
            claude_path_glob(".cargo/credentials*").as_deref(),
            Some("**/.cargo/credentials*")
        );
    }

    #[test]
    fn skips_negation_and_repo_wide_stars() {
        assert!(claude_path_glob("!keep.env").is_none());
        assert!(claude_path_glob("*").is_none());
        assert!(claude_path_glob("**").is_none());
    }

    #[test]
    fn upsert_preserves_foreign_bash_deny() {
        let existing = r#"{
  "permissions": {
    "deny": ["Bash(rm)", "Bash(rm -rf *)"]
  }
}
"#;
        let ClaudeDenyUpsert::Written(out) = upsert(Some(existing), &[".env*".into()]).unwrap()
        else {
            panic!("expected write");
        };
        let v: Value = serde_json::from_str(&out).unwrap();
        let deny: Vec<&str> = v
            .pointer("/permissions/deny")
            .and_then(|a| a.as_array())
            .unwrap()
            .iter()
            .filter_map(|x| x.as_str())
            .collect();
        assert!(deny.contains(&"Bash(rm)"));
        assert!(deny.contains(&"Bash(rm -rf *)"));
        assert!(deny.contains(&"Read(**/.env*)"));
        assert!(deny.contains(&"Edit(**/.env*)"));
        assert!(deny.contains(&"Write(**/.env*)"));
    }

    #[test]
    fn upsert_replaces_stale_managed_rules() {
        let first = match upsert(None, &[".env*".into()]).unwrap() {
            ClaudeDenyUpsert::Written(s) => s,
            ClaudeDenyUpsert::Unchanged => panic!("expected create"),
        };
        let second = match upsert(Some(&first), &["*.pem".into()]).unwrap() {
            ClaudeDenyUpsert::Written(s) => s,
            ClaudeDenyUpsert::Unchanged => panic!("expected update"),
        };
        let v: Value = serde_json::from_str(&second).unwrap();
        let deny: Vec<&str> = v
            .pointer("/permissions/deny")
            .and_then(|a| a.as_array())
            .unwrap()
            .iter()
            .filter_map(|x| x.as_str())
            .collect();
        assert!(!deny.iter().any(|r| r.contains(".env")));
        assert!(deny.contains(&"Read(**/*.pem)"));
    }

    #[test]
    fn upsert_empty_patterns_without_file_is_noop() {
        assert_eq!(upsert(None, &[]).unwrap(), ClaudeDenyUpsert::Unchanged);
    }

    #[test]
    fn missing_managed_rules_when_file_absent() {
        let missing = missing_managed_rules(None, &[".env*".into()]);
        assert_eq!(missing.len(), 3);
    }

    #[test]
    fn tools_filter() {
        let mut only_cursor = HashSet::new();
        only_cursor.insert(ToolId::Cursor);
        assert!(!applies_to(Some(&only_cursor)));
        let mut with_claude = HashSet::new();
        with_claude.insert(ToolId::Claude);
        assert!(applies_to(Some(&with_claude)));
        assert!(applies_to(None));
    }
}
