//! `history` — audit or redact sensitive values in local agent transcripts.

use clap::{Args, Subcommand};
use offsend_detect::{DetectionEngine, DetectionOptions, DetectionRequest};
use serde::Serialize;
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

const MAX_FILES: usize = 200;
const MAX_FILE_BYTES: u64 = 2 * 1024 * 1024;

#[derive(Debug, Args)]
pub struct HistoryArgs {
    #[command(subcommand)]
    command: HistoryCommand,
}

#[derive(Debug, Subcommand)]
enum HistoryCommand {
    /// Scan local Cursor/Claude agent transcripts for sensitive values.
    Audit(HistoryScanArgs),
    /// Redact sensitive values in local agent transcripts.
    Scrub(ScrubArgs),
}

#[derive(Debug, Args)]
struct HistoryScanArgs {
    #[command(flatten)]
    scope: ScopeArgs,
}

#[derive(Debug, Args)]
struct ScrubArgs {
    #[command(flatten)]
    scope: ScopeArgs,

    /// Write redactions to disk. Without this flag, only report what would change.
    #[arg(long)]
    apply: bool,
}

#[derive(Debug, Args)]
struct ScopeArgs {
    /// Project directory used to scope Cursor and Claude transcripts.
    #[arg(long)]
    path: Option<String>,

    /// Scan transcripts for every project under ~/.cursor and ~/.claude.
    #[arg(long)]
    all: bool,

    /// Output format (text, json).
    #[arg(long, default_value = "text")]
    format: String,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FindingOut {
    path: String,
    source: String,
    entity_types: BTreeMap<String, usize>,
    finding_count: usize,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AuditOut {
    files_scanned: usize,
    files_with_findings: usize,
    findings: Vec<FindingOut>,
    errors: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ScrubOut {
    dry_run: bool,
    files_touched: Vec<String>,
    redaction_count: usize,
    findings: Vec<FindingOut>,
    errors: Vec<String>,
}

struct Transcript {
    path: PathBuf,
    source: &'static str,
}

/// Summary of a transcript content scan (reusable by `show` / `protect` / `doctor`).
#[derive(Debug, Clone)]
pub struct HistoryScanSummary {
    pub files_scanned: usize,
    pub finding_count: usize,
    pub findings: Vec<FindingOut>,
    pub errors: Vec<String>,
}

/// Summary of a transcript scrub pass.
#[derive(Debug, Clone)]
pub struct HistoryScrubSummary {
    pub dry_run: bool,
    pub files_touched: Vec<String>,
    pub redaction_count: usize,
    pub findings: Vec<FindingOut>,
    pub errors: Vec<String>,
}

pub fn run(args: HistoryArgs) -> Result<ExitCode, String> {
    match args.command {
        HistoryCommand::Audit(args) => audit(args.scope),
        HistoryCommand::Scrub(args) => scrub(args.scope, args.apply),
    }
}

/// Content-scan local agent transcripts for the given project root.
pub fn scan_transcripts(path: Option<&Path>, all: bool) -> HistoryScanSummary {
    let scope = ScopeArgs {
        path: path.map(|p| p.display().to_string()),
        all,
        format: "text".into(),
    };
    scan_scope(&scope)
}

/// Scrub (or dry-run scrub) local agent transcripts for the given project root.
pub fn scrub_transcripts(path: Option<&Path>, all: bool, apply: bool) -> HistoryScrubSummary {
    let scope = ScopeArgs {
        path: path.map(|p| p.display().to_string()),
        all,
        format: "text".into(),
    };
    scrub_scope(&scope, apply)
}

fn audit(args: ScopeArgs) -> Result<ExitCode, String> {
    let summary = scan_scope(&args);
    render_audit(
        &args.format,
        summary.files_scanned,
        &summary.findings,
        &summary.errors,
    )?;
    Ok(if summary.findings.is_empty() && summary.errors.is_empty() {
        ExitCode::SUCCESS
    } else if !summary.errors.is_empty() {
        ExitCode::from(2)
    } else {
        ExitCode::from(1)
    })
}

fn scrub(args: ScopeArgs, apply: bool) -> Result<ExitCode, String> {
    let summary = scrub_scope(&args, apply);
    let has_errors = !summary.errors.is_empty();
    match args.format.as_str() {
        "text" => {
            println!(
                "{}: {} redaction(s) across {} file(s).",
                if apply { "Applied" } else { "Dry-run" },
                summary.redaction_count,
                summary.files_touched.len()
            );
            for path in &summary.files_touched {
                println!("  - {path}");
            }
            for error in &summary.errors {
                eprintln!("error: {error}");
            }
        }
        "json" => println!(
            "{}",
            serde_json::to_string_pretty(&ScrubOut {
                dry_run: summary.dry_run,
                files_touched: summary.files_touched,
                redaction_count: summary.redaction_count,
                findings: summary.findings,
                errors: summary.errors,
            })
            .map_err(|error| error.to_string())?
        ),
        other => {
            return Err(format!(
                "Invalid --format value: {other}. Expected text or json."
            ))
        }
    }
    Ok(if !has_errors {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(2)
    })
}

fn scan_scope(args: &ScopeArgs) -> HistoryScanSummary {
    let (files, mut errors) = discover(args);
    let mut findings = Vec::new();
    for file in &files {
        match read_bounded(&file.path) {
            Ok(Some(text)) => {
                let entities = sensitive_entities(&text);
                if !entities.is_empty() {
                    findings.push(finding(file, &entities));
                }
            }
            Ok(None) => {}
            Err(error) => errors.push(format!("{}: {error}", file.path.display())),
        }
    }
    findings.sort_by(|a, b| a.path.cmp(&b.path));
    let finding_count = findings.iter().map(|f| f.finding_count).sum();
    HistoryScanSummary {
        files_scanned: files.len(),
        finding_count,
        findings,
        errors,
    }
}

fn scrub_scope(args: &ScopeArgs, apply: bool) -> HistoryScrubSummary {
    let (files, mut errors) = discover(args);
    let mut findings = Vec::new();
    let mut touched = Vec::new();
    let mut redaction_count = 0;
    for file in &files {
        match read_bounded(&file.path) {
            Ok(Some(text)) => {
                let entities = sensitive_entities(&text);
                if entities.is_empty() {
                    continue;
                }
                findings.push(finding(file, &entities));
                if fs::metadata(&file.path)
                    .map(|meta| meta.len() > MAX_FILE_BYTES)
                    .unwrap_or(true)
                {
                    errors.push(format!(
                        "{}: skipped scrub — file exceeds the 2 MB scan limit; redact manually",
                        file.path.display()
                    ));
                    continue;
                }
                let (redacted, count) = redact(&text, &entities);
                if count == 0 {
                    continue;
                }
                if apply {
                    if let Err(error) = fs::write(&file.path, redacted) {
                        errors.push(format!("{}: {error}", file.path.display()));
                        continue;
                    }
                }
                redaction_count += count;
                touched.push(file.path.display().to_string());
            }
            Ok(None) => {}
            Err(error) => errors.push(format!("{}: {error}", file.path.display())),
        }
    }
    findings.sort_by(|a, b| a.path.cmp(&b.path));
    touched.sort();
    HistoryScrubSummary {
        dry_run: !apply,
        files_touched: touched,
        redaction_count,
        findings,
        errors,
    }
}

fn render_audit(
    format: &str,
    files_scanned: usize,
    findings: &[FindingOut],
    errors: &[String],
) -> Result<(), String> {
    match format {
        "text" => {
            println!("Scanned {files_scanned} agent transcript file(s).");
            for finding in findings {
                let types = finding
                    .entity_types
                    .iter()
                    .map(|(name, count)| format!("{name}: {count}"))
                    .collect::<Vec<_>>()
                    .join(", ");
                println!(
                    "{} [{}] ({}: {types})",
                    finding.path, finding.source, finding.finding_count
                );
            }
            for error in errors {
                eprintln!("error: {error}");
            }
        }
        "json" => println!(
            "{}",
            serde_json::to_string_pretty(&AuditOut {
                files_scanned,
                files_with_findings: findings.len(),
                findings: findings.to_vec(),
                errors: errors.to_vec(),
            })
            .map_err(|error| error.to_string())?
        ),
        other => {
            return Err(format!(
                "Invalid --format value: {other}. Expected text or json."
            ))
        }
    }
    Ok(())
}

fn discover(args: &ScopeArgs) -> (Vec<Transcript>, Vec<String>) {
    let root = args.path.as_ref().map(PathBuf::from).unwrap_or_else(cwd);
    let home = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/"));
    let mut files = Vec::new();
    let mut errors = Vec::new();
    let cursor_root = home.join(".cursor/projects");
    if args.all {
        collect(
            &cursor_root,
            "cursor-transcript",
            None,
            &mut files,
            &mut errors,
        );
    } else {
        collect(
            &cursor_root
                .join(cursor_project_slug(&root))
                .join("agent-transcripts"),
            "cursor-transcript",
            None,
            &mut files,
            &mut errors,
        );
    }
    let claude_root = home.join(".claude/projects");
    if args.all {
        collect(
            &claude_root,
            "claude-transcript",
            None,
            &mut files,
            &mut errors,
        );
    } else {
        let component = claude_project_dir(&root);
        collect(
            &claude_root,
            "claude-transcript",
            Some(&component),
            &mut files,
            &mut errors,
        );
    }
    collect(
        &root.join(".cursor"),
        "cursor-project-local",
        None,
        &mut files,
        &mut errors,
    );
    files.sort_by(|a, b| a.path.cmp(&b.path));
    files.dedup_by(|a, b| a.path == b.path);
    files.truncate(MAX_FILES);
    (files, errors)
}

fn collect(
    root: &Path,
    source: &'static str,
    required_component: Option<&str>,
    files: &mut Vec<Transcript>,
    errors: &mut Vec<String>,
) {
    if files.len() >= MAX_FILES || !root.is_dir() {
        return;
    }
    let Ok(entries) = fs::read_dir(root) else {
        errors.push(format!(
            "{}: could not read transcript directory",
            root.display()
        ));
        return;
    };
    for entry in entries.flatten() {
        if files.len() >= MAX_FILES {
            break;
        }
        let path = entry.path();
        if path.is_dir() {
            collect(&path, source, required_component, files, errors);
            continue;
        }
        let extension = path.extension().and_then(|ext| ext.to_str());
        if !matches!(extension, Some("jsonl" | "txt")) {
            continue;
        }
        if let Some(component) = required_component {
            if !path.components().any(|part| part.as_os_str() == component) {
                continue;
            }
        }
        files.push(Transcript { path, source });
    }
}

fn read_bounded(path: &Path) -> Result<Option<String>, String> {
    let meta = fs::metadata(path).map_err(|error| error.to_string())?;
    if meta.len() == 0 {
        return Ok(None);
    }
    let bytes = fs::read(path).map_err(|error| error.to_string())?;
    let bounded = &bytes[..bytes.len().min(MAX_FILE_BYTES as usize)];
    Ok(String::from_utf8(bounded.to_vec()).ok())
}

fn sensitive_entities(text: &str) -> Vec<offsend_detect::SensitiveEntity> {
    DetectionEngine::scan(&DetectionRequest {
        text: text.to_string(),
        options: DetectionOptions::default(),
    })
    .entities
    .into_iter()
    .filter(|entity| entity.entity_type.is_secret())
    .collect()
}

fn finding(file: &Transcript, entities: &[offsend_detect::SensitiveEntity]) -> FindingOut {
    let mut entity_types = BTreeMap::new();
    for entity in entities {
        *entity_types
            .entry(entity.entity_type.swift_name().to_string())
            .or_insert(0) += 1;
    }
    FindingOut {
        path: file.path.display().to_string(),
        source: file.source.into(),
        entity_types,
        finding_count: entities.len(),
    }
}

fn redact(text: &str, entities: &[offsend_detect::SensitiveEntity]) -> (String, usize) {
    let mut spans = entities.iter().collect::<Vec<_>>();
    spans.sort_by_key(|entity| entity.start);
    let mut accepted = Vec::new();
    let mut end = 0;
    for entity in spans {
        if entity.start >= end
            && entity.end <= text.len()
            && text.is_char_boundary(entity.start)
            && text.is_char_boundary(entity.end)
        {
            end = entity.end;
            accepted.push(entity);
        }
    }
    let mut output = text.to_string();
    for entity in accepted.iter().rev() {
        output.replace_range(
            entity.start..entity.end,
            &format!("OFFSEND_REDACTED_{}", redaction_type(entity.entity_type)),
        );
    }
    (output, accepted.len())
}

fn redaction_type(entity_type: offsend_detect::EntityType) -> &'static str {
    use offsend_detect::EntityType::*;
    match entity_type {
        Email => "EMAIL",
        Phone => "PHONE",
        Money => "MONEY",
        Url => "URL",
        IpAddress => "IP_ADDRESS",
        InternalDomain => "INTERNAL_DOMAIN",
        ContractId => "CONTRACT_ID",
        InvoiceId => "INVOICE_ID",
        OrderId => "ORDER_ID",
        ApiKeyGeneric => "API_KEY_GENERIC",
        OpenAIAPIKey => "OPEN_AI_API_KEY",
        AwsAccessKeyId => "AWS_ACCESS_KEY_ID",
        GithubToken => "GITHUB_TOKEN",
        SlackToken => "SLACK_TOKEN",
        StripeKey => "STRIPE_KEY",
        Jwt => "JWT",
        PrivateKey => "PRIVATE_KEY",
        SshPrivateKey => "SSH_PRIVATE_KEY",
        DatabaseUrlWithPassword => "DATABASE_URL_WITH_PASSWORD",
        BearerToken => "BEARER_TOKEN",
        HighEntropyString => "HIGH_ENTROPY_STRING",
        CreditCardLike => "CREDIT_CARD_LIKE",
        Iban => "IBAN",
        CustomClient => "CUSTOM_CLIENT",
        CustomCompany => "CUSTOM_COMPANY",
        CustomProject => "CUSTOM_PROJECT",
        CustomSensitiveTerm => "CUSTOM_SENSITIVE_TERM",
        CustomInternalDomain => "CUSTOM_INTERNAL_DOMAIN",
        PersonName => "PERSON_NAME",
        StreetAddress => "STREET_ADDRESS",
        GovernmentId => "GOVERNMENT_ID",
    }
}

fn cursor_project_slug(root: &Path) -> String {
    root.to_string_lossy()
        .trim_start_matches('/')
        .replace(['/', ' '], "-")
}

fn claude_project_dir(root: &Path) -> String {
    root.to_string_lossy()
        .chars()
        .map(|character| {
            if character.is_alphanumeric() {
                character
            } else {
                '-'
            }
        })
        .collect()
}

fn cwd() -> PathBuf {
    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redaction_type_is_stable_and_uppercase() {
        assert_eq!(
            redaction_type(offsend_detect::EntityType::OpenAIAPIKey),
            "OPEN_AI_API_KEY"
        );
        assert_eq!(
            redaction_type(offsend_detect::EntityType::DatabaseUrlWithPassword),
            "DATABASE_URL_WITH_PASSWORD"
        );
    }
}
