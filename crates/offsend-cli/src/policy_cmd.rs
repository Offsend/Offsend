//! `policy trust|status|forget`

use clap::{Args, Subcommand};
use std::io::{self, BufRead, IsTerminal, Write};
use std::path::PathBuf;
use std::process::ExitCode;

#[derive(Debug, Subcommand)]
pub enum PolicyCmd {
    /// Trust the current `.offsend.yml` for adapter fail-closed drift checks.
    Trust(TrustArgs),
    /// Show trust snapshot status for this repository.
    Status(StatusArgs),
    /// Remove the trusted policy snapshot.
    Forget(ForgetArgs),
}

#[derive(Debug, Args)]
pub struct TrustArgs {
    #[arg(long)]
    pub path: Option<String>,
}

#[derive(Debug, Args)]
pub struct StatusArgs {
    #[arg(long)]
    pub path: Option<String>,
}

#[derive(Debug, Args)]
pub struct ForgetArgs {
    #[arg(long)]
    pub path: Option<String>,
}

pub fn run(cmd: PolicyCmd) -> Result<ExitCode, String> {
    match cmd {
        PolicyCmd::Trust(args) => {
            let root = root(args.path.as_deref());
            if !confirm_interactive(
                "Trust the current .offsend.yml for editor gates in this repository? [y/N] ",
            )? {
                return Ok(ExitCode::SUCCESS);
            }
            let path = crate::policy_trust::trust(&root)?;
            println!("trusted {}", path.display());
            Ok(ExitCode::SUCCESS)
        }
        PolicyCmd::Status(args) => {
            let root = root(args.path.as_deref());
            match crate::policy_trust::status(&root) {
                crate::policy_trust::TrustStatus::Missing => {
                    println!("status: missing");
                    println!("hint: offsend policy trust");
                }
                crate::policy_trust::TrustStatus::Trusted => println!("status: trusted"),
                crate::policy_trust::TrustStatus::Drift(r) => {
                    println!("status: drift");
                    println!("reason: {r}");
                    println!("hint: offsend policy trust");
                }
                crate::policy_trust::TrustStatus::Invalid(r) => {
                    println!("status: invalid");
                    println!("reason: {r}");
                }
            }
            Ok(ExitCode::SUCCESS)
        }
        PolicyCmd::Forget(args) => {
            let root = root(args.path.as_deref());
            if !confirm_interactive(
                "Forget the trusted policy snapshot for this repository? [y/N] ",
            )? {
                return Ok(ExitCode::SUCCESS);
            }
            if crate::policy_trust::forget(&root)? {
                println!("forgot trust snapshot");
            } else {
                println!("no trust snapshot");
            }
            Ok(ExitCode::SUCCESS)
        }
    }
}

fn root(path: Option<&str>) -> PathBuf {
    let dir = path
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
    crate::hook_git::resolve_repo_root(&dir).unwrap_or(dir)
}

/// `trust` / `forget` must not run from agent shells or CI without a real TTY.
/// Decline (EOF / non-yes) exits 0 without mutating state; missing TTY is an error.
fn confirm_interactive(prompt: &str) -> Result<bool, String> {
    let stdin = io::stdin();
    if !stdin.is_terminal() {
        return Err(
            "policy trust/forget require an interactive terminal (no TTY).".into(),
        );
    }
    eprint!("{prompt}");
    let _ = io::stderr().flush();
    let mut line = String::new();
    match stdin.lock().read_line(&mut line) {
        Ok(0) => Ok(false),
        Ok(_) => {
            let answer = line.trim();
            Ok(answer.eq_ignore_ascii_case("y") || answer.eq_ignore_ascii_case("yes"))
        }
        Err(e) => Err(e.to_string()),
    }
}
