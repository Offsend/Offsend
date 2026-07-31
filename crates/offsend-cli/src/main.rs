//! Offsend CLI (Rust). Binary name: `offsend`.

mod adapter;
mod check;
mod doctor_cmd;
mod edit_cmd;
mod git;
mod history_cmd;
mod hook_ai;
mod hook_cmd;
mod hook_git;
mod hook_policy;
mod ignore_cmd;
mod init_cmd;
mod io;
mod keys;
mod policy_cmd;
mod policy_trust;
mod protect_cmd;
mod run_cmd;
mod sandbox_ensure;
mod sandbox_launch;
mod sandbox_policy;
mod sandbox_provider;
mod sandbox_sync;
mod seal_cmd;
mod show_cmd;
mod sync_cmd;
mod yaml_ignore;

use clap::{Parser, Subcommand};
use std::process::ExitCode;

#[derive(Parser)]
#[command(
    name = "offsend",
    about = "Local sensitive data checks for developers.",
    version = env!("OFFSEND_CLI_VERSION")
)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Generate a 32-byte seal key for use with seal / unseal.
    Keygen(seal_cmd::KeygenArgs),
    /// Replace sensitive values with reversible {{TYPE:v1.…}} seal tokens.
    Seal(seal_cmd::SealArgs),
    /// Restore plaintext from {{TYPE:v1.…}} seal tokens.
    Unseal(seal_cmd::UnsealArgs),
    /// Scan files or prompt text for sensitive data.
    Check(check::CheckArgs),
    /// Create a starter `.offsend.yml`.
    Init(init_cmd::InitArgs),
    /// Apply .offsend.yml: materialize AI ignore files and install hooks.
    Sync(sync_cmd::SyncArgs),
    /// Create missing AI ignore/rule files and promote exposure patterns.
    Protect(protect_cmd::ProtectArgs),
    /// Add paths/patterns to team ignore policy.
    Ignore(ignore_cmd::IgnoreArgs),
    /// Install or remove Offsend git and AI-editor hooks.
    #[command(subcommand)]
    Hook(hook_cmd::HookCmd),
    /// Trust / inspect policy snapshots used by adapter gates.
    #[command(subcommand)]
    Policy(policy_cmd::PolicyCmd),
    /// Verify local Offsend CLI setup and dependencies.
    Doctor(doctor_cmd::DoctorArgs),
    /// Launch an AI editor under the sandbox from `.offsend.yml`.
    Run(run_cmd::RunArgs),
    /// Open `.offsend.yml` in your configured editor.
    Edit(edit_cmd::EditArgs),
    /// List sensitive files exposed to AI tools.
    Show(show_cmd::ShowArgs),
    /// Audit or scrub sensitive values in local agent transcripts.
    History(history_cmd::HistoryArgs),
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let result: Result<ExitCode, String> = match cli.command {
        Commands::Keygen(args) => seal_cmd::run_keygen(args).map_err(|e| e.to_string()),
        Commands::Seal(args) => seal_cmd::run_seal(args).map_err(|e| e.to_string()),
        Commands::Unseal(args) => seal_cmd::run_unseal(args).map_err(|e| e.to_string()),
        Commands::Check(args) => check::run(args).map_err(|e| e.to_string()),
        Commands::Init(args) => init_cmd::run(args),
        Commands::Sync(args) => sync_cmd::run(args).map_err(|e| e.to_string()),
        Commands::Protect(args) => protect_cmd::run(args),
        Commands::Ignore(args) => ignore_cmd::run(args),
        Commands::Hook(cmd) => hook_cmd::run(cmd),
        Commands::Policy(cmd) => policy_cmd::run(cmd),
        Commands::Doctor(args) => doctor_cmd::run(args),
        Commands::Run(args) => run_cmd::run(args),
        Commands::Edit(args) => edit_cmd::run(args),
        Commands::Show(args) => show_cmd::run(args),
        Commands::History(args) => history_cmd::run(args),
    };
    match result {
        Ok(code) => code,
        Err(err) => {
            eprintln!("{err}");
            ExitCode::from(2)
        }
    }
}
