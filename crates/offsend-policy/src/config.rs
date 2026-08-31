//! `.offsend.yml` schema — port of Swift `OffsendProjectConfig` (v1).

use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use thiserror::Error;

pub const CONFIG_FILENAME: &str = ".offsend.yml";
pub const SUPPORTED_VERSION: i32 = 1;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ConfigError {
    #[error("unreadable config at {path}")]
    Unreadable { path: String },
    #[error("invalid YAML at {path}: {message}")]
    InvalidYaml { path: String, message: String },
    #[error("unsupported config version: {0}")]
    UnsupportedVersion(i32),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct OffsendProjectConfig {
    pub version: i32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub check: Option<OffsendProjectCheckConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ignore: Option<OffsendProjectIgnoreConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hooks: Option<OffsendProjectHooksConfig>,
    /// Reserved for later gate/sandbox ports; accepted and preserved loosely.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context: Option<serde_yaml::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sandbox: Option<serde_yaml::Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct OffsendProjectCheckConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fail_on: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub policy: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub exclude: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub detectors: Option<OffsendProjectDetectorsConfig>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dictionaries: Option<Vec<OffsendProjectDictionaryEntry>>,
    /// When true, `offsend check` honors `offsend:ignore` / `offsend:ignore-next-line`.
    /// Editor hooks and the clipboard guard ignore this key.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub honor_inline_ignore: Option<bool>,
}

impl OffsendProjectCheckConfig {
    pub fn fail_on_or_default(&self) -> &str {
        self.fail_on.as_deref().unwrap_or("block")
    }

    pub fn policy_or_default(&self) -> bool {
        self.policy.unwrap_or(false)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct OffsendProjectIgnoreConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub commit: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tools: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub patterns: Option<Vec<String>>,
}

impl OffsendProjectIgnoreConfig {
    /// Absent means do not commit ignore files.
    pub fn commits_ignore_files(&self) -> bool {
        self.commit.unwrap_or(false)
    }

    pub fn patterns_or_empty(&self) -> &[String] {
        self.patterns.as_deref().unwrap_or(&[])
    }

    /// `None` means every supported tool (no narrowing).
    pub fn tool_ids(&self) -> Option<HashSet<ToolId>> {
        let tools = self.tools.as_ref()?;
        let ids: HashSet<_> = tools
            .iter()
            .filter_map(|s| ToolId::parse(s))
            .collect();
        if ids.is_empty() {
            None
        } else {
            Some(ids)
        }
    }

    pub fn unknown_tool_slugs(&self) -> Vec<String> {
        self.tools
            .as_ref()
            .map(|tools| {
                tools
                    .iter()
                    .filter(|s| ToolId::parse(s).is_none())
                    .cloned()
                    .collect()
            })
            .unwrap_or_default()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct OffsendProjectDetectorsConfig {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub disable: Option<Vec<String>>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OffsendProjectDictionaryEntry {
    pub kind: String,
    pub value: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct OffsendProjectHooksConfig {
    /// When true (default), the project expects git hooks (and `sync` may
    /// install AI-editor hooks). `doctor` fails if declared git hooks are
    /// missing. `check --policy` does not require git hooks on the CI runner.
    /// Project AI-editor files are not required in CI.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enabled: Option<bool>,
    /// Git hook names to install, e.g. `[pre-commit, post-merge]`.
    /// Default when unset (and no legacy `type`): `[pre-commit]`.
    /// Empty list → no git hooks (AI-editor hooks still follow `enabled`).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub git: Option<Vec<String>>,
    /// Deprecated alias for a single git hook. Prefer `git: [pre-commit]`.
    #[serde(default, rename = "type", skip_serializing_if = "Option::is_none")]
    pub r#type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fail_on: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub policy: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub publish: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ignore_exclude: Option<bool>,
}

/// Supported values for `hooks.git`.
pub const SUPPORTED_GIT_HOOKS: &[&str] = &["pre-commit", "post-merge"];

impl OffsendProjectHooksConfig {
    pub fn is_enabled(&self) -> bool {
        self.enabled.unwrap_or(true)
    }

    /// Resolved git hook names from `git`, else legacy `type`, else `[pre-commit]`.
    pub fn git_hooks(&self) -> Vec<String> {
        if let Some(git) = &self.git {
            return git
                .iter()
                .map(|s| s.trim().to_ascii_lowercase())
                .filter(|s| !s.is_empty())
                .collect();
        }
        if let Some(legacy) = &self.r#type {
            let t = legacy.trim().to_ascii_lowercase();
            if !t.is_empty() {
                return vec![t];
            }
        }
        vec!["pre-commit".into()]
    }

    pub fn unknown_git_hooks(&self) -> Vec<String> {
        self.git_hooks()
            .into_iter()
            .filter(|name| !SUPPORTED_GIT_HOOKS.contains(&name.as_str()))
            .collect()
    }

    pub fn publishes_hooks(&self) -> bool {
        self.publish.unwrap_or(false)
    }

    pub fn ignores_check_exclude(&self) -> bool {
        self.ignore_exclude.unwrap_or(false)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ToolId {
    Cursor,
    Claude,
    Copilot,
    Continue,
    Windsurf,
    Gemini,
    Llm,
    Aider,
    Cline,
    Roo,
    Zed,
    Cody,
    Codex,
}

impl ToolId {
    pub fn parse(raw: &str) -> Option<Self> {
        match raw.trim().to_ascii_lowercase().as_str() {
            "cursor" => Some(Self::Cursor),
            "claude" => Some(Self::Claude),
            "copilot" => Some(Self::Copilot),
            "continue" => Some(Self::Continue),
            "windsurf" => Some(Self::Windsurf),
            "gemini" => Some(Self::Gemini),
            "llm" => Some(Self::Llm),
            "aider" => Some(Self::Aider),
            "cline" => Some(Self::Cline),
            "roo" => Some(Self::Roo),
            "zed" => Some(Self::Zed),
            "cody" => Some(Self::Cody),
            "codex" => Some(Self::Codex),
            _ => None,
        }
    }
}

impl OffsendProjectConfig {
    /// Project expects hooks. Default `true` when unset / no `hooks` section.
    pub fn hooks_enabled(&self) -> bool {
        self.hooks
            .as_ref()
            .map(OffsendProjectHooksConfig::is_enabled)
            .unwrap_or(true)
    }

    /// Git hooks to install. Default `[pre-commit]` when no `hooks` section.
    pub fn git_hooks(&self) -> Vec<String> {
        self.hooks
            .as_ref()
            .map(OffsendProjectHooksConfig::git_hooks)
            .unwrap_or_else(|| vec!["pre-commit".into()])
    }

    /// `context.history.scrub_on_protect` — when true, `offsend protect` also scrubs transcripts.
    pub fn history_scrub_on_protect(&self) -> bool {
        self.context
            .as_ref()
            .and_then(|c| c.get("history"))
            .and_then(|h| h.get("scrub_on_protect"))
            .and_then(|v| v.as_bool())
            == Some(true)
    }

    /// `context.history.scan_in_show` — when true, `offsend show` content-scans transcripts.
    pub fn history_scan_in_show(&self) -> bool {
        self.context
            .as_ref()
            .and_then(|c| c.get("history"))
            .and_then(|h| h.get("scan_in_show"))
            .and_then(|v| v.as_bool())
            == Some(true)
    }

    pub fn parse_yaml(contents: &str) -> Result<Self, ConfigError> {
        let config: Self = serde_yaml::from_str(contents).map_err(|e| ConfigError::InvalidYaml {
            path: CONFIG_FILENAME.into(),
            message: e.to_string(),
        })?;
        if config.version != SUPPORTED_VERSION {
            return Err(ConfigError::UnsupportedVersion(config.version));
        }
        Ok(config)
    }

    pub fn load_from_path(path: &std::path::Path) -> Result<Option<Self>, ConfigError> {
        if !path.exists() {
            return Ok(None);
        }
        let contents = std::fs::read_to_string(path).map_err(|_| ConfigError::Unreadable {
            path: path.display().to_string(),
        })?;
        Self::parse_yaml(&contents).map(Some)
    }

    /// Walk parents looking for `.offsend.yml` (git-root approximation for MVP).
    pub fn find_and_load(start: &std::path::Path) -> Result<Option<(std::path::PathBuf, Self)>, ConfigError> {
        let mut dir = start.to_path_buf();
        loop {
            let candidate = dir.join(CONFIG_FILENAME);
            if candidate.is_file() {
                let config = Self::load_from_path(&candidate)?.expect("file exists");
                return Ok(Some((candidate, config)));
            }
            if !dir.pop() {
                return Ok(None);
            }
        }
    }
}

const TOP_LEVEL_KEYS: &[&str] = &["version", "check", "ignore", "hooks", "context", "sandbox"];
const CHECK_KEYS: &[&str] = &[
    "fail_on",
    "policy",
    "exclude",
    "detectors",
    "dictionaries",
    "honor_inline_ignore",
];
const DETECTORS_KEYS: &[&str] = &["disable"];
const IGNORE_KEYS: &[&str] = &["commit", "tools", "patterns"];
const HOOKS_KEYS: &[&str] = &[
    "enabled",
    "git",
    "type",
    "fail_on",
    "policy",
    "publish",
    "ignore_exclude",
];

/// Lints `.offsend.yml` for unknown (likely misspelled) keys. serde silently
/// ignores unknown fields, so a typo like `fail-on:` disables the setting with
/// no signal at all; `doctor` surfaces these findings as warnings.
/// `context` / `sandbox` subtrees are consumed loosely and are not linted.
pub fn lint_unknown_keys(contents: &str) -> Vec<String> {
    let Ok(root) = serde_yaml::from_str::<serde_yaml::Value>(contents) else {
        return vec![];
    };
    let mut findings = Vec::new();
    lint_mapping(&root, "", TOP_LEVEL_KEYS, &mut findings);
    if let Some(check) = root.get("check") {
        lint_mapping(check, "check.", CHECK_KEYS, &mut findings);
        if let Some(detectors) = check.get("detectors") {
            lint_mapping(detectors, "check.detectors.", DETECTORS_KEYS, &mut findings);
        }
    }
    if let Some(ignore) = root.get("ignore") {
        lint_mapping(ignore, "ignore.", IGNORE_KEYS, &mut findings);
    }
    if let Some(hooks) = root.get("hooks") {
        lint_mapping(hooks, "hooks.", HOOKS_KEYS, &mut findings);
    }
    findings
}

fn lint_mapping(
    value: &serde_yaml::Value,
    prefix: &str,
    known: &[&str],
    findings: &mut Vec<String>,
) {
    let Some(map) = value.as_mapping() else {
        return;
    };
    for key in map.keys() {
        let Some(name) = key.as_str() else { continue };
        if known.contains(&name) {
            continue;
        }
        let hint = known
            .iter()
            .min_by_key(|k| levenshtein(name, k))
            .filter(|k| levenshtein(name, k) <= 2);
        match hint {
            Some(k) => findings.push(format!(
                "{prefix}{name}: unknown key — did you mean `{k}`?"
            )),
            None => findings.push(format!("{prefix}{name}: unknown key (ignored)")),
        }
    }
}

fn levenshtein(a: &str, b: &str) -> usize {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    let mut prev: Vec<usize> = (0..=b.len()).collect();
    for (i, ca) in a.iter().enumerate() {
        let mut cur = vec![i + 1];
        for (j, cb) in b.iter().enumerate() {
            let cost = usize::from(ca != cb);
            cur.push((prev[j] + cost).min(prev[j + 1] + 1).min(cur[j] + 1));
        }
        prev = cur;
    }
    prev[b.len()]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_minimal_v1() {
        let yaml = r#"
version: 1
ignore:
  commit: false
  patterns:
    - .env
    - "*.pem"
check:
  fail_on: warn
  policy: true
  exclude:
    - target/**
"#;
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        assert_eq!(cfg.version, 1);
        let ignore = cfg.ignore.unwrap();
        assert!(!ignore.commits_ignore_files());
        assert_eq!(ignore.patterns_or_empty(), &[".env".to_string(), "*.pem".to_string()]);
        let check = cfg.check.unwrap();
        assert_eq!(check.fail_on_or_default(), "warn");
        assert!(check.policy_or_default());
        assert_eq!(check.honor_inline_ignore, None);
    }

    #[test]
    fn parses_honor_inline_ignore() {
        let yaml = "version: 1\ncheck:\n  honor_inline_ignore: true\n";
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        assert_eq!(cfg.check.unwrap().honor_inline_ignore, Some(true));
    }

    #[test]
    fn rejects_bad_version() {
        let yaml = "version: 2\n";
        assert_eq!(
            OffsendProjectConfig::parse_yaml(yaml),
            Err(ConfigError::UnsupportedVersion(2))
        );
    }

    #[test]
    fn tool_ids_and_unknowns() {
        let yaml = r#"
version: 1
ignore:
  tools: [cursor, nope, Claude]
"#;
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        let ignore = cfg.ignore.unwrap();
        let ids = ignore.tool_ids().unwrap();
        assert!(ids.contains(&ToolId::Cursor));
        assert!(ids.contains(&ToolId::Claude));
        assert_eq!(ignore.unknown_tool_slugs(), vec!["nope".to_string()]);
    }

    #[test]
    fn history_context_flags() {
        let yaml = r#"
version: 1
context:
  history:
    scrub_on_protect: true
    scan_in_show: true
"#;
        let cfg = OffsendProjectConfig::parse_yaml(yaml).unwrap();
        assert!(cfg.history_scrub_on_protect());
        assert!(cfg.history_scan_in_show());
        let bare = OffsendProjectConfig::parse_yaml("version: 1\n").unwrap();
        assert!(!bare.history_scrub_on_protect());
        assert!(!bare.history_scan_in_show());
    }

    #[test]
    fn hooks_enabled_defaults_true() {
        let bare = OffsendProjectConfig::parse_yaml("version: 1\n").unwrap();
        assert!(bare.hooks_enabled());

        let explicit_true = OffsendProjectConfig::parse_yaml(
            "version: 1\nhooks:\n  enabled: true\n  publish: false\n",
        )
        .unwrap();
        assert!(explicit_true.hooks_enabled());

        let disabled = OffsendProjectConfig::parse_yaml(
            "version: 1\nhooks:\n  enabled: false\n  publish: false\n",
        )
        .unwrap();
        assert!(!disabled.hooks_enabled());

        let section_without_key =
            OffsendProjectConfig::parse_yaml("version: 1\nhooks:\n  publish: false\n").unwrap();
        assert!(section_without_key.hooks_enabled());
    }

    #[test]
    fn lint_flags_typos_with_suggestions() {
        let yaml = "version: 1\ncheck:\n  fail-on: block\nignore:\n  paterns:\n    - .env\nhooks:\n  enable: true\n";
        let findings = lint_unknown_keys(yaml);
        assert!(findings
            .iter()
            .any(|f| f.contains("check.fail-on") && f.contains("`fail_on`")));
        assert!(findings
            .iter()
            .any(|f| f.contains("ignore.paterns") && f.contains("`patterns`")));
        assert!(findings
            .iter()
            .any(|f| f.contains("hooks.enable") && f.contains("`enabled`")));
    }

    #[test]
    fn lint_is_silent_on_valid_config_and_skips_context() {
        let yaml = "version: 1\ncheck:\n  fail_on: block\n  detectors:\n    disable: [email]\nignore:\n  patterns: [.env]\ncontext:\n  read:\n    on_secret: seal\nhooks:\n  enabled: true\n";
        assert!(lint_unknown_keys(yaml).is_empty());
    }

    #[test]
    fn lint_flags_unknown_top_level_key() {
        let findings = lint_unknown_keys("version: 1\nchekc: {}\n");
        assert_eq!(findings.len(), 1);
        assert!(findings[0].contains("chekc"));
        assert!(findings[0].contains("`check`"));
    }

    #[test]
    fn hooks_git_list_and_legacy_type() {
        let bare = OffsendProjectConfig::parse_yaml("version: 1\n").unwrap();
        assert_eq!(bare.git_hooks(), vec!["pre-commit".to_string()]);

        let list = OffsendProjectConfig::parse_yaml(
            "version: 1\nhooks:\n  git: [pre-commit, post-merge]\n",
        )
        .unwrap();
        assert_eq!(
            list.git_hooks(),
            vec!["pre-commit".to_string(), "post-merge".to_string()]
        );

        let legacy =
            OffsendProjectConfig::parse_yaml("version: 1\nhooks:\n  type: pre-commit\n").unwrap();
        assert_eq!(legacy.git_hooks(), vec!["pre-commit".to_string()]);

        let empty = OffsendProjectConfig::parse_yaml("version: 1\nhooks:\n  git: []\n").unwrap();
        assert!(empty.git_hooks().is_empty());

        let unknown =
            OffsendProjectConfig::parse_yaml("version: 1\nhooks:\n  git: [pre-push]\n").unwrap();
        assert_eq!(unknown.hooks.unwrap().unknown_git_hooks(), vec!["pre-push"]);
    }
}
