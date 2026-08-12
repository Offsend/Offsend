//! `check` — scan files / stdin / staged + optional workspace policy.

use crate::git::{self, GitError};
use crate::io::{self, IoError};
use clap::Args;
use offsend_detect::{DetectionEngine, DetectionOptions, DetectionRequest, EntityType};
use offsend_policy::{
    default_audit_configuration, findings_for_files, AuditStatus, FixStrategy,
    IgnorePatternPathMatcher, OffsendProjectConfig, OffsendProjectDictionaryEntry,
    PathExcludeMatcher, PrivacyAuditor,
};
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use thiserror::Error;

#[derive(Debug, Args)]
pub struct CheckArgs {
    /// File or directory paths to scan.
    pub paths: Vec<String>,

    /// Scan only staged files in the current git repository.
    #[arg(long)]
    pub staged: bool,

    /// Read prompt/text from stdin instead of file paths.
    #[arg(long)]
    pub stdin: bool,

    /// Also run workspace policy checks on the repository root.
    #[arg(long)]
    pub policy: bool,

    /// Exit with failure when findings reach this level (block, warn, none).
    /// Defaults to `check.fail_on` from `.offsend.yml`, else `block`.
    #[arg(long)]
    pub fail_on: Option<String>,

    /// Output format (text, json).
    #[arg(long, default_value = "text")]
    pub format: String,

    #[arg(long)]
    pub working_directory: Option<String>,

    /// Only print findings (text mode).
    #[arg(long)]
    pub quiet: bool,

    /// Only report critical secret-shaped findings (excludes high-entropy).
    /// Secrets-only filtering is the default; this flag is accepted for
    /// backward compatibility and conflicts with `--no-secrets-only`.
    #[arg(long = "secrets-only", default_value_t = false, conflicts_with = "no_secrets_only")]
    pub secrets_only: bool,

    /// Include non-secret detectors (e.g. high-entropy).
    #[arg(long = "no-secrets-only", default_value_t = false)]
    pub no_secrets_only: bool,

    /// With --stdin: print secret-gate JSON instead of the risk report.
    #[arg(long = "gate-secrets", default_value_t = false)]
    pub gate_secrets: bool,

    /// List every finding individually (text mode).
    #[arg(long, default_value_t = false)]
    pub verbose: bool,

    /// AI-editor hook adapter (cursor, claude, windsurf, codex). Reads hook JSON on stdin.
    #[arg(long, hide = true)]
    pub adapter: Option<String>,

    /// Policy for AI-editor hooks (advise, soft-block, block).
    #[arg(long = "hook-policy", default_value = "soft-block", hide = true)]
    pub hook_policy: String,

    #[arg(long = "no-notify", default_value_t = false, hide = true)]
    pub no_notify: bool,

    /// With --adapter: write a sealed copy to a private temp file + clipboard.
    #[arg(long = "seal-copy", default_value_t = false, hide = true)]
    pub seal_copy: bool,

    /// Append adapter diagnostics to the hook debug log (no secret values).
    #[arg(long = "debug-hook", default_value_t = false, hide = true)]
    pub debug_hook: bool,

    /// Path to a seal key file (for --seal-copy / --hook-policy block).
    #[arg(long = "key-file", hide = true)]
    pub key_file: Option<String>,

    /// Named seal key in ~/.offsend/keys/NAME.key.
    #[arg(long = "key-name", hide = true)]
    pub key_name: Option<String>,

    #[arg(long = "read-gate", default_value_t = false, hide = true)]
    pub read_gate: bool,

    #[arg(long = "write-gate", default_value_t = false, hide = true)]
    pub write_gate: bool,

    #[arg(long = "shell-gate", default_value_t = false, hide = true)]
    pub shell_gate: bool,

    #[arg(long = "shell-audit", default_value_t = false, hide = true)]
    pub shell_audit: bool,

    #[arg(long = "mcp-gate", default_value_t = false, hide = true)]
    pub mcp_gate: bool,

    #[arg(long = "mcp-response-gate", default_value_t = false, hide = true)]
    pub mcp_response_gate: bool,

    #[arg(long = "subagent-gate", default_value_t = false, hide = true)]
    pub subagent_gate: bool,

    #[arg(long = "artifact-audit", default_value_t = false, hide = true)]
    pub artifact_audit: bool,

    #[arg(long = "grep-gate", default_value_t = false, hide = true)]
    pub grep_gate: bool,
}

impl CheckArgs {
    /// Secrets-only filtering is on by default; `--no-secrets-only` disables it.
    fn secrets_only_enabled(&self) -> bool {
        !self.no_secrets_only
    }
}

#[derive(Debug, Error)]
pub enum CheckError {
    #[error("{0}")]
    Io(#[from] IoError),
    #[error("{0}")]
    Git(#[from] GitError),
    #[error("{0}")]
    Message(String),
}

#[derive(Debug, Clone, Serialize)]
struct ContentFinding {
    path: String,
    entity_type: String,
    value_preview: String,
    start: usize,
    end: usize,
    is_secret: bool,
    is_critical_secret: bool,
}

#[derive(Debug, Clone, Serialize)]
struct PolicyFindingOut {
    kind: String,
    id: String,
    severity: String,
    status: String,
    detail: String,
}

#[derive(Serialize)]
struct JsonReport {
    should_fail: bool,
    finding_count: usize,
    policy_finding_count: usize,
    findings: Vec<ContentFinding>,
    policy_findings: Vec<PolicyFindingOut>,
}

#[derive(Clone, Copy)]
enum FailOn {
    Block,
    Warn,
    None,
}

#[derive(Clone, Copy)]
enum Format {
    Text,
    Json,
}

pub fn run(args: CheckArgs) -> Result<ExitCode, CheckError> {
    let _ = args.no_notify; // notifications not ported yet
    let _ = args.debug_hook; // debug log not ported yet
    let cwd = io::working_dir(args.working_directory.as_deref());

    if args.seal_copy && args.adapter.is_none() {
        return Err(CheckError::Message(
            "--seal-copy requires --adapter.".into(),
        ));
    }
    if args.gate_secrets && !args.stdin {
        return Err(CheckError::Message(
            "--gate-secrets requires --stdin.".into(),
        ));
    }
    if args.gate_secrets && args.adapter.is_some() {
        return Err(CheckError::Message(
            "--gate-secrets cannot be combined with --adapter.".into(),
        ));
    }

    if let Some(adapter_raw) = args.adapter.as_deref() {
        let adapter = crate::adapter::Adapter::parse(adapter_raw).ok_or_else(|| {
            CheckError::Message(format!(
                "Invalid --adapter value: {adapter_raw}. Expected cursor, claude, windsurf, codex."
            ))
        })?;
        let Some(hook_policy) = crate::adapter::HookPolicy::parse(&args.hook_policy) else {
            // Invalid policy in a hook invocation must fail-open so editors are not wedged.
            return Ok(crate::adapter::fail_open(
                adapter,
                "invalid_hook_policy",
                crate::adapter::GateKind::Prompt,
            ));
        };
        let loaded = OffsendProjectConfig::find_and_load(&cwd).ok().flatten();
        let project_root = loaded
            .as_ref()
            .and_then(|(p, _)| p.parent().map(|d| d.to_path_buf()))
            .unwrap_or_else(|| {
                crate::hook_git::resolve_repo_root(&cwd).unwrap_or_else(|_| cwd.clone())
            });
        let ignore_exclude = loaded
            .as_ref()
            .and_then(|(_, c)| c.hooks.as_ref())
            .map(|h| h.ignores_check_exclude())
            .unwrap_or(false);
        let exclude_patterns = if ignore_exclude {
            Vec::new()
        } else {
            loaded
                .as_ref()
                .and_then(|(_, c)| c.check.as_ref())
                .and_then(|c| c.exclude.clone())
                .unwrap_or_default()
        };
        let ignore_patterns = loaded
            .as_ref()
            .and_then(|(_, c)| c.ignore.as_ref())
            .and_then(|i| i.patterns.clone())
            .unwrap_or_default();
        let context = loaded
            .as_ref()
            .and_then(|(_, cfg)| cfg.context.clone())
            .and_then(|yaml| serde_json::to_value(yaml).ok());
        let sandbox_required = loaded
            .as_ref()
            .map(|(_, cfg)| {
                crate::sandbox_sync::effective_sandbox_enabled(
                    Some(cfg),
                    crate::policy_trust::is_trusted(&project_root),
                )
            })
            .unwrap_or(false);
        return crate::adapter::run(crate::adapter::AdapterFlags {
            adapter,
            hook_policy,
            secrets_only: args.secrets_only_enabled(),
            seal_copy: args.seal_copy,
            key_file: args.key_file.clone(),
            key_name: args.key_name.clone(),
            read_gate: args.read_gate,
            write_gate: args.write_gate,
            shell_gate: args.shell_gate,
            shell_audit: args.shell_audit,
            mcp_gate: args.mcp_gate,
            mcp_response_gate: args.mcp_response_gate,
            subagent_gate: args.subagent_gate,
            artifact_audit: args.artifact_audit,
            grep_gate: args.grep_gate,
            context,
            exclude_patterns,
            ignore_patterns,
            project_root,
            sandbox_required,
        })
        .map_err(CheckError::Message);
    }

    let format = parse_format(&args.format)?;

    if args.stdin && args.staged {
        return Err(CheckError::Message(
            "--stdin/--adapter cannot be combined with --staged.".into(),
        ));
    }
    if args.stdin && args.policy {
        return Err(CheckError::Message(
            "--stdin/--adapter cannot be combined with --policy.".into(),
        ));
    }
    if args.stdin && !args.paths.is_empty() {
        return Err(CheckError::Message(
            "Pass either --stdin or file paths, not both.".into(),
        ));
    }
    if args.staged && !args.paths.is_empty() {
        return Err(CheckError::Message(
            "--staged cannot be combined with explicit paths.".into(),
        ));
    }

    // `check --policy DIR` must load DIR's `.offsend.yml`, not the caller's cwd —
    // otherwise fixture/CI checks silently evaluate the wrong project policy.
    let config_search_root = if args.policy {
        args.paths
            .iter()
            .map(PathBuf::from)
            .find(|p| p.is_dir())
            .unwrap_or_else(|| cwd.clone())
    } else {
        cwd.clone()
    };
    let (config_path, project_config) = match OffsendProjectConfig::find_and_load(&config_search_root)
    {
        Ok(Some((path, cfg))) => (Some(path), Some(cfg)),
        Ok(None) => (None, None),
        Err(e) => {
            return Err(CheckError::Message(format!(
                "Failed to load .offsend.yml: {e}"
            )))
        }
    };

    let fail_on = resolve_fail_on(args.fail_on.as_deref(), project_config.as_ref())?;
    let include_policy = if args.policy {
        true
    } else {
        project_config
            .as_ref()
            .and_then(|c| c.check.as_ref())
            .and_then(|c| c.policy)
            .unwrap_or(false)
    };
    let exclude: Vec<String> = project_config
        .as_ref()
        .and_then(|c| c.check.as_ref())
        .and_then(|c| c.exclude.clone())
        .unwrap_or_default();
    let detection_options = detection_options_from_config(project_config.as_ref());
    let dictionaries: Vec<OffsendProjectDictionaryEntry> = project_config
        .as_ref()
        .and_then(|c| c.check.as_ref())
        .and_then(|c| c.dictionaries.clone())
        .unwrap_or_default();

    let mut findings: Vec<ContentFinding> = Vec::new();
    let mut policy_findings: Vec<PolicyFindingOut> = Vec::new();
    let mut policy_root: Option<PathBuf> = None;

    if args.stdin {
        let text = io::read_input(None, &cwd)?;
        collect_findings(
            "stdin",
            &text,
            args.secrets_only_enabled(),
            &detection_options,
            &dictionaries,
            &mut findings,
        );
        if args.gate_secrets {
            let types: Vec<String> = findings
                .iter()
                .map(|f| f.entity_type.clone())
                .collect::<std::collections::BTreeSet<_>>()
                .into_iter()
                .collect();
            let has_secrets = !findings.is_empty();
            let user_message = if has_secrets {
                format!(
                    "Offsend found {} secret-shaped finding(s).",
                    findings.len()
                )
            } else {
                String::new()
            };
            println!(
                "{}",
                serde_json::json!({
                    "findingCount": findings.len(),
                    "findingTypes": types,
                    "userMessage": user_message,
                    "hasSecrets": has_secrets,
                })
            );
            return Ok(if has_secrets {
                ExitCode::from(1)
            } else {
                ExitCode::SUCCESS
            });
        }
    } else if args.staged {
        let repo = git::repository_root(&cwd)?;
        policy_root = Some(repo.clone());
        let staged = git::staged_paths(&repo)?;
        for rel in staged {
            if PathExcludeMatcher::is_excluded(&rel, &exclude) {
                continue;
            }
            if let Some(ext) = unsupported_document_extension(&rel) {
                if args.verbose {
                    eprintln!("skip {rel}: unsupported format (.{ext})");
                }
                continue;
            }
            let blob = git::staged_blob(&repo, &rel)?;
            if blob.len() > io::MAX_INPUT_BYTES {
                continue;
            }
            let Ok(text) = String::from_utf8(blob) else {
                continue;
            };
            collect_findings(
                &rel,
                &text,
                args.secrets_only_enabled(),
                &detection_options,
                &dictionaries,
                &mut findings,
            );
        }
    } else if !args.paths.is_empty() {
        let mut dirs = Vec::new();
        for raw in &args.paths {
            let path = io::resolve_path(raw, &cwd);
            if !path.exists() {
                return Err(CheckError::Message(format!(
                    "Path not found: {}",
                    path.display()
                )));
            }
            if path.is_dir() {
                dirs.push(path.clone());
                for entry in walkdir_files(&path, &exclude, &cwd)? {
                    scan_file(
                        &entry,
                        &cwd,
                        args.secrets_only_enabled(),
                        &detection_options,
                        &dictionaries,
                        args.verbose,
                        &mut findings,
                    )?;
                }
            } else {
                let rel = relative_label(&path, &cwd);
                if !PathExcludeMatcher::is_excluded(&rel, &exclude) {
                    scan_file(
                        &path,
                        &cwd,
                        args.secrets_only_enabled(),
                        &detection_options,
                        &dictionaries,
                        args.verbose,
                        &mut findings,
                    )?;
                }
            }
        }
        if include_policy {
            if dirs.len() > 1 {
                return Err(CheckError::Message(format!(
                    "--policy supports a single directory; got {}.",
                    dirs.len()
                )));
            }
            policy_root = Some(
                dirs.first()
                    .cloned()
                    .unwrap_or_else(|| git::repository_root(&cwd).unwrap_or_else(|_| cwd.clone())),
            );
        }
    } else if include_policy {
        policy_root = Some(git::repository_root(&cwd).unwrap_or_else(|_| cwd.clone()));
    } else {
        return Err(CheckError::Message(
            "Provide file paths, --staged, --policy, or --stdin.".into(),
        ));
    }

    if include_policy {
        let root = policy_root.unwrap_or_else(|| cwd.clone());
        let _ = config_path;
        let mut cfg = default_audit_configuration();
        if let Some(tools) = project_config
            .as_ref()
            .and_then(|c| c.ignore.as_ref())
            .and_then(|i| i.tool_ids())
        {
            cfg = cfg.filtered(Some(&tools));
        }
        // With `.offsend.yml` and `ignore.commit: false`, sync-managed files are
        // expected missing on fresh clones — not a policy failure.
        let skip_missing_managed = project_config.is_some()
            && !project_config
                .as_ref()
                .and_then(|c| c.ignore.as_ref())
                .map(|i| i.commits_ignore_files())
                .unwrap_or(false);

        let audit = PrivacyAuditor::audit_with(&root, &cfg);
        for err in &audit.errors {
            policy_findings.push(PolicyFindingOut {
                kind: "error".into(),
                id: err.id.clone(),
                severity: "required".into(),
                status: "fail".into(),
                detail: err.message.clone(),
            });
        }
        for f in &audit.rule_findings {
            if f.is_satisfied() {
                continue;
            }
            if skip_missing_managed && is_materialized_by_ignore_sync(f) {
                continue;
            }
            let status = match f.rule.severity {
                offsend_policy::RuleSeverity::Required => "fail",
                _ => "warning",
            };
            policy_findings.push(PolicyFindingOut {
                kind: "rule".into(),
                id: f.rule.id.clone(),
                severity: severity_name(f.rule.severity).into(),
                status: status.into(),
                detail: format!(
                    "Missing {} ignore file ({})",
                    f.rule.tool_name, f.rule.title
                ),
            });
        }
        for f in &audit.sensitive_pattern_findings {
            if f.exposed_relative_paths.is_empty() {
                continue;
            }
            let shown: Vec<_> = f.exposed_relative_paths.iter().take(3).cloned().collect();
            let suffix = if f.exposed_relative_paths.len() > 3 {
                ", …"
            } else {
                ""
            };
            policy_findings.push(PolicyFindingOut {
                kind: "sensitive_pattern".into(),
                id: f.pattern.id.clone(),
                severity: severity_name(f.pattern.severity).into(),
                status: "warning".into(),
                detail: format!("Exposed sensitive paths: {}{}", shown.join(", "), suffix),
            });
        }

        if let Some(patterns) = project_config
            .as_ref()
            .and_then(|c| c.ignore.as_ref())
            .and_then(|i| i.patterns.clone())
        {
            if !patterns.is_empty() {
                let mut ignore_files: Vec<(String, String)> = Vec::new();
                for f in &audit.rule_findings {
                    if !f.rule.scans_for_sensitive_patterns {
                        continue;
                    }
                    for path in &f.matched_relative_paths {
                        let full = root.join(path);
                        if let Ok(contents) = fs::read_to_string(&full) {
                            ignore_files.push((path.clone(), contents));
                        }
                    }
                }
                for drift in findings_for_files(&patterns, &ignore_files) {
                    policy_findings.push(PolicyFindingOut {
                        kind: "managed_drift".into(),
                        id: drift.relative_path.clone(),
                        severity: "required".into(),
                        status: "fail".into(),
                        detail: format!(
                            "Managed ignore drift in {}: missing {}. Run: offsend sync",
                            drift.relative_path,
                            drift.missing_patterns.join(", ")
                        ),
                    });
                }
                if let Ok(tracked) = git::tracked_paths(&root) {
                    let hits: Vec<_> = tracked
                        .into_iter()
                        .filter(|path| {
                            IgnorePatternPathMatcher::is_ignored(
                                path,
                                patterns.iter().map(|s| s.as_str()),
                            )
                        })
                        .collect();
                    if !hits.is_empty() {
                        let shown = hits.iter().take(8).cloned().collect::<Vec<_>>().join(", ");
                        let suffix = if hits.len() > 8 {
                            format!(" (+{} more)", hits.len() - 8)
                        } else {
                            String::new()
                        };
                        policy_findings.push(PolicyFindingOut {
                            kind: "tracked_ignore".into(),
                            id: "ignore.patterns".into(),
                            severity: "required".into(),
                            status: "fail".into(),
                            detail: format!(
                                "Git tracks paths covered by ignore.patterns: {shown}{suffix}."
                            ),
                        });
                    }
                }
            }
        }

        if crate::hook_policy::hooks_required(project_config.as_ref()) {
            for finding in crate::hook_policy::findings(&root, project_config.as_ref()) {
                policy_findings.push(PolicyFindingOut {
                    kind: "hooks".into(),
                    id: finding.id,
                    severity: if finding.is_failure {
                        "required".into()
                    } else {
                        "recommended".into()
                    },
                    status: if finding.is_failure {
                        "fail".into()
                    } else {
                        "warning".into()
                    },
                    detail: finding.message,
                });
            }
        }

        if crate::sandbox_sync::effective_sandbox_enabled(
            project_config.as_ref(),
            crate::policy_trust::is_trusted(&root),
        ) {
            for finding in crate::sandbox_policy::findings(&root, project_config.as_ref()) {
                policy_findings.push(PolicyFindingOut {
                    kind: "sandbox".into(),
                    id: "sandbox-policy".into(),
                    severity: if finding.is_failure {
                        "required".into()
                    } else {
                        "recommended".into()
                    },
                    status: if finding.is_failure {
                        "fail".into()
                    } else {
                        "warning".into()
                    },
                    detail: finding.message,
                });
            }
        }

        if policy_findings.is_empty() && !matches!(audit.status, AuditStatus::Pass) {
            let only_skipped = skip_missing_managed
                && audit
                    .rule_findings
                    .iter()
                    .all(|f| f.is_satisfied() || is_materialized_by_ignore_sync(f))
                && audit
                    .sensitive_pattern_findings
                    .iter()
                    .all(|f| f.is_satisfied());
            if !only_skipped {
                policy_findings.push(PolicyFindingOut {
                    kind: "audit".into(),
                    id: "workspace".into(),
                    severity: "recommended".into(),
                    status: match audit.status {
                        AuditStatus::Fail => "fail".into(),
                        _ => "warning".into(),
                    },
                    detail: format!("Workspace policy status: {:?}", audit.status).to_lowercase(),
                });
            }
        }
    }

    let should_fail = compute_should_fail(&findings, &policy_findings, fail_on);

    match format {
        Format::Text => {
            for f in &findings {
                println!(
                    "{}:{}-{} [{}] {}",
                    f.path, f.start, f.end, f.entity_type, f.value_preview
                );
            }
            for p in &policy_findings {
                println!("policy:{} [{}] {}", p.id, p.status, p.detail);
            }
            if !args.quiet {
                eprintln!(
                    "findings {} policy {}{}",
                    findings.len(),
                    policy_findings.len(),
                    if should_fail { " (fail)" } else { "" }
                );
            }
        }
        Format::Json => {
            let report = JsonReport {
                should_fail,
                finding_count: findings.len(),
                policy_finding_count: policy_findings.len(),
                findings,
                policy_findings,
            };
            println!(
                "{}",
                serde_json::to_string_pretty(&report)
                    .map_err(|e| CheckError::Message(e.to_string()))?
            );
        }
    }

    Ok(if should_fail {
        ExitCode::from(1)
    } else {
        ExitCode::SUCCESS
    })
}

fn resolve_fail_on(
    cli: Option<&str>,
    config: Option<&OffsendProjectConfig>,
) -> Result<FailOn, CheckError> {
    let raw = cli
        .map(str::to_string)
        .or_else(|| {
            config
                .and_then(|c| c.check.as_ref())
                .and_then(|c| c.fail_on.clone())
        })
        .unwrap_or_else(|| "block".into());
    parse_fail_on(&raw)
}

fn parse_fail_on(raw: &str) -> Result<FailOn, CheckError> {
    match raw {
        "block" => Ok(FailOn::Block),
        "warn" => Ok(FailOn::Warn),
        "none" => Ok(FailOn::None),
        _ => Err(CheckError::Message(format!(
            "Invalid --fail-on value: {raw}. Expected one of: block, warn, none."
        ))),
    }
}

fn parse_format(raw: &str) -> Result<Format, CheckError> {
    match raw {
        "text" => Ok(Format::Text),
        "json" => Ok(Format::Json),
        _ => Err(CheckError::Message(format!(
            "Invalid --format value: {raw}. Expected one of: text, json."
        ))),
    }
}

fn compute_should_fail(
    findings: &[ContentFinding],
    policy: &[PolicyFindingOut],
    fail_on: FailOn,
) -> bool {
    match fail_on {
        FailOn::None => false,
        FailOn::Block => {
            findings.iter().any(|f| f.is_critical_secret)
                || policy.iter().any(|p| p.status == "fail")
        }
        FailOn::Warn => {
            !findings.is_empty()
                || policy
                    .iter()
                    .any(|p| p.status == "fail" || p.status == "warning")
        }
    }
}

fn severity_name(s: offsend_policy::RuleSeverity) -> &'static str {
    match s {
        offsend_policy::RuleSeverity::Required => "required",
        offsend_policy::RuleSeverity::Recommended => "recommended",
        offsend_policy::RuleSeverity::Informational => "informational",
    }
}

fn is_materialized_by_ignore_sync(finding: &offsend_policy::RuleFinding) -> bool {
    let Some(fix) = &finding.rule.fix else {
        return false;
    };
    finding.rule.scans_for_sensitive_patterns || fix.strategy == FixStrategy::KeepManagedContent
}

fn walkdir_files(root: &Path, exclude: &[String], cwd: &Path) -> Result<Vec<PathBuf>, CheckError> {
    let mut out = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let rel_dir = relative_label(&dir, cwd);
        if PathExcludeMatcher::should_skip_directory(&rel_dir, exclude) {
            continue;
        }
        let entries = fs::read_dir(&dir).map_err(|e| CheckError::Message(e.to_string()))?;
        for entry in entries.flatten() {
            let path = entry.path();
            let Ok(meta) = entry.metadata() else { continue };
            let name = entry.file_name().to_string_lossy().to_string();
            if meta.is_dir() {
                if matches!(
                    name.as_str(),
                    ".git" | "node_modules" | ".build" | "target" | "DerivedData"
                ) {
                    continue;
                }
                stack.push(path);
            } else if meta.is_file() {
                let rel = relative_label(&path, cwd);
                if !PathExcludeMatcher::is_excluded(&rel, exclude) {
                    out.push(path);
                }
            }
        }
    }
    out.sort();
    Ok(out)
}

fn scan_file(
    path: &Path,
    cwd: &Path,
    secrets_only: bool,
    options: &DetectionOptions,
    dictionaries: &[OffsendProjectDictionaryEntry],
    verbose: bool,
    findings: &mut Vec<ContentFinding>,
) -> Result<(), CheckError> {
    let label = relative_label(path, cwd);
    if let Some(ext) = unsupported_document_extension(&label) {
        if verbose {
            eprintln!("skip {label}: unsupported format (.{ext})");
        }
        return Ok(());
    }
    let data = fs::read(path)
        .map_err(|e| CheckError::Message(format!("Failed to read {}: {e}", path.display())))?;
    if data.len() > io::MAX_INPUT_BYTES {
        return Ok(());
    }
    let Ok(text) = String::from_utf8(data) else {
        return Ok(());
    };
    collect_findings(&label, &text, secrets_only, options, dictionaries, findings);
    Ok(())
}

/// Document types the Swift app scans via DocumentCore/PDFKit.
/// Rust CLI is text-only for now — skip quietly (warn with --verbose).
fn unsupported_document_extension(path: &str) -> Option<&'static str> {
    let lower = path.to_ascii_lowercase();
    const EXTS: &[&str] = &["pdf", "docx", "xlsx", "pptx", "odt", "rtf"];
    for ext in EXTS {
        if lower.ends_with(&format!(".{ext}")) {
            return Some(ext);
        }
    }
    None
}

fn relative_label(path: &Path, cwd: &Path) -> String {
    path.strip_prefix(cwd)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")
}

fn detection_options_from_config(config: Option<&OffsendProjectConfig>) -> DetectionOptions {
    let mut options = DetectionOptions::default();
    let Some(disable) = config
        .and_then(|c| c.check.as_ref())
        .and_then(|c| c.detectors.as_ref())
        .and_then(|d| d.disable.as_ref())
    else {
        return options;
    };
    for name in disable {
        if let Some(t) = EntityType::from_swift_name(name) {
            options.enabled_types.remove(&t);
        }
    }
    options
}

fn collect_findings(
    path: &str,
    text: &str,
    secrets_only: bool,
    options: &DetectionOptions,
    dictionaries: &[OffsendProjectDictionaryEntry],
    findings: &mut Vec<ContentFinding>,
) {
    let request = DetectionRequest {
        text: text.to_string(),
        options: options.clone(),
    };
    let result = DetectionEngine::scan(&request);
    // Engine already drops non-critical hits inside {{TYPE:v1.…}}; keep the same
    // rule for any residual / dictionary matches below.
    let seal_ranges = offsend_seal::SealTokenDetector::token_ranges(text);
    for e in result.entities {
        let is_critical = e.entity_type.counts_as_critical_secret();
        if !is_critical
            && seal_ranges
                .iter()
                .any(|r| e.start >= r.start && e.end <= r.end)
        {
            continue;
        }
        let is_secret = e.entity_type.is_secret();
        if secrets_only && !is_critical {
            continue;
        }
        findings.push(ContentFinding {
            path: path.to_string(),
            entity_type: entity_type_name(e.entity_type).to_string(),
            value_preview: preview(&e.value),
            start: e.start,
            end: e.end,
            is_secret,
            is_critical_secret: is_critical,
        });
    }
    for entry in dictionaries {
        let Some(entity_type) = dictionary_entity_type(&entry.kind) else {
            continue;
        };
        if secrets_only {
            continue;
        }
        if !options.enabled_types.contains(&entity_type) {
            continue;
        }
        let needle = entry.value.as_str();
        if needle.is_empty() {
            continue;
        }
        let lower_text = text.to_ascii_lowercase();
        let lower_needle = needle.to_ascii_lowercase();
        let mut search_from = 0;
        while let Some(rel) = lower_text[search_from..].find(&lower_needle) {
            let start = search_from + rel;
            let end = start + needle.len();
            if seal_ranges
                .iter()
                .any(|r| start >= r.start && end <= r.end)
            {
                search_from = end;
                if search_from >= lower_text.len() {
                    break;
                }
                continue;
            }
            // Map back using byte offsets from lowercase search — OK for ASCII terms.
            findings.push(ContentFinding {
                path: path.to_string(),
                entity_type: entity_type_name(entity_type).to_string(),
                value_preview: preview(needle),
                start,
                end,
                is_secret: false,
                is_critical_secret: false,
            });
            search_from = end;
            if search_from >= lower_text.len() {
                break;
            }
        }
    }
}

fn dictionary_entity_type(kind: &str) -> Option<EntityType> {
    match kind {
        "client" => Some(EntityType::CustomClient),
        "company" => Some(EntityType::CustomCompany),
        "project" => Some(EntityType::CustomProject),
        "sensitiveTerm" | "sensitive_term" => Some(EntityType::CustomSensitiveTerm),
        "internalDomain" | "internal_domain" => Some(EntityType::CustomInternalDomain),
        _ => EntityType::from_swift_name(kind),
    }
}

fn entity_type_name(t: EntityType) -> &'static str {
    use EntityType::*;
    match t {
        Email => "email",
        Phone => "phone",
        Money => "money",
        Url => "url",
        IpAddress => "ipAddress",
        InternalDomain => "internalDomain",
        ContractId => "contractId",
        InvoiceId => "invoiceId",
        OrderId => "orderId",
        ApiKeyGeneric => "apiKeyGeneric",
        OpenAIAPIKey => "openAIAPIKey",
        AwsAccessKeyId => "awsAccessKeyId",
        GithubToken => "githubToken",
        SlackToken => "slackToken",
        StripeKey => "stripeKey",
        Jwt => "jwt",
        PrivateKey => "privateKey",
        SshPrivateKey => "sshPrivateKey",
        DatabaseUrlWithPassword => "databaseURLWithPassword",
        BearerToken => "bearerToken",
        HighEntropyString => "highEntropyString",
        CreditCardLike => "creditCardLike",
        Iban => "iban",
        CustomClient => "customClient",
        CustomCompany => "customCompany",
        CustomProject => "customProject",
        CustomSensitiveTerm => "customSensitiveTerm",
        CustomInternalDomain => "customInternalDomain",
        PersonName => "personName",
        StreetAddress => "streetAddress",
        GovernmentId => "governmentId",
    }
}

fn preview(value: &str) -> String {
    const MAX: usize = 48;
    let mut chars: String = value.chars().take(MAX).collect();
    if value.chars().count() > MAX {
        chars.push('…');
    }
    chars
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;

    #[derive(Debug, Parser)]
    #[command(name = "check")]
    struct Wrap {
        #[command(flatten)]
        args: CheckArgs,
    }

    #[test]
    fn secrets_only_flag_parses_both_forms() {
        let default = Wrap::try_parse_from(["check"]).unwrap();
        assert!(default.args.secrets_only_enabled());

        let on = Wrap::try_parse_from(["check", "--secrets-only"]).unwrap();
        assert!(on.args.secrets_only_enabled());
        assert!(on.args.secrets_only);

        let off = Wrap::try_parse_from(["check", "--no-secrets-only"]).unwrap();
        assert!(!off.args.secrets_only_enabled());
    }
}
