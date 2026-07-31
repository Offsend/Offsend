//! `show` — list sensitive paths not covered by editor ignore files.

use clap::Args;
use offsend_policy::{AuditStatus, OffsendProjectConfig, PrivacyAuditor, RuleSeverity};
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

#[derive(Debug, Args)]
#[command(about = "List sensitive files exposed to AI tools (not covered by ignore files).")]
pub struct ShowArgs {
    /// Directory to inspect. Defaults to the current directory.
    pub path: Option<String>,

    /// Output format (text, json). Ignored when `--report` is set (always JSON).
    #[arg(long, default_value = "text")]
    pub format: String,

    /// Emit an anonymized aggregated JSON report (no file paths).
    #[arg(long, default_value_t = false)]
    pub report: bool,

    /// Write `--report` JSON to this path instead of stdout.
    #[arg(long, value_name = "PATH")]
    pub out: Option<String>,

    /// Also content-scan local agent transcripts (file + finding counts).
    #[arg(long = "scan-history", default_value_t = false)]
    pub scan_history: bool,
}

#[derive(Serialize)]
struct ShowReport {
    exposed_paths: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    history: Option<HistorySection>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AnonymizedReport {
    version: u32,
    exposed_pattern_count: usize,
    required_exposure_count: usize,
    recommended_exposure_count: usize,
    missing_rule_count: usize,
    error_count: usize,
    status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    history: Option<HistorySection>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct HistorySection {
    files_scanned: usize,
    finding_count: usize,
}

pub fn run(args: ShowArgs) -> Result<ExitCode, String> {
    if args.out.is_some() && !args.report {
        return Err("--out requires --report".into());
    }

    let root = args
        .path
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
    let audit = PrivacyAuditor::audit(&root);

    let config = OffsendProjectConfig::find_and_load(&root)
        .ok()
        .flatten()
        .map(|(_, cfg)| cfg);
    let scan_history = args.scan_history
        || config
            .as_ref()
            .map(OffsendProjectConfig::history_scan_in_show)
            .unwrap_or(false);
    let history = if scan_history {
        let summary = crate::history_cmd::scan_transcripts(Some(&root), false);
        Some(HistorySection {
            files_scanned: summary.files_scanned,
            finding_count: summary.finding_count,
        })
    } else {
        None
    };

    if args.report {
        let report = build_anonymized(&audit, history);
        let json = serde_json::to_string_pretty(&report).map_err(|error| error.to_string())?;
        write_report_output(&json, args.out.as_deref())?;
        return Ok(if audit.errors.is_empty() {
            ExitCode::SUCCESS
        } else {
            ExitCode::from(2)
        });
    }

    let mut paths = audit
        .sensitive_pattern_findings
        .iter()
        .flat_map(|finding| finding.exposed_relative_paths.iter().cloned())
        .collect::<Vec<_>>();
    paths.sort();
    paths.dedup();

    match args.format.as_str() {
        "text" => {
            for path in &paths {
                println!("{path}");
            }
            if let Some(history) = &history {
                println!(
                    "history: {} file(s), {} finding(s)",
                    history.files_scanned, history.finding_count
                );
            }
        }
        "json" => println!(
            "{}",
            serde_json::to_string_pretty(&ShowReport {
                exposed_paths: paths,
                history,
            })
            .map_err(|error| error.to_string())?
        ),
        other => {
            return Err(format!(
                "Invalid --format value: {other}. Expected text or json."
            ))
        }
    }
    Ok(if audit.errors.is_empty() {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(2)
    })
}

fn build_anonymized(
    audit: &offsend_policy::AuditResult,
    history: Option<HistorySection>,
) -> AnonymizedReport {
    let exposed_pattern_count = audit
        .sensitive_pattern_findings
        .iter()
        .filter(|f| !f.is_satisfied())
        .count();
    let required_exposure_count = audit
        .sensitive_pattern_findings
        .iter()
        .filter(|f| !f.is_satisfied() && f.pattern.severity == RuleSeverity::Required)
        .count();
    let recommended_exposure_count = audit
        .sensitive_pattern_findings
        .iter()
        .filter(|f| !f.is_satisfied() && f.pattern.severity == RuleSeverity::Recommended)
        .count();
    let missing_rule_count = audit
        .rule_findings
        .iter()
        .filter(|f| !f.is_satisfied())
        .count();
    AnonymizedReport {
        version: 1,
        exposed_pattern_count,
        required_exposure_count,
        recommended_exposure_count,
        missing_rule_count,
        error_count: audit.errors.len(),
        status: match audit.status {
            AuditStatus::Pass => "pass",
            AuditStatus::Warning => "warning",
            AuditStatus::Fail => "fail",
        }
        .into(),
        history,
    }
}

fn write_report_output(json: &str, out: Option<&str>) -> Result<(), String> {
    match out {
        Some(path) => {
            let path = Path::new(path);
            if let Some(parent) = path.parent() {
                if !parent.as_os_str().is_empty() {
                    fs::create_dir_all(parent).map_err(|e| e.to_string())?;
                }
            }
            fs::write(path, format!("{json}\n")).map_err(|e| e.to_string())
        }
        None => {
            println!("{json}");
            Ok(())
        }
    }
}
