//! `keygen` / `seal` / `unseal` commands.

use crate::io::{self, IoError};
use crate::keys::{self, KeyError};
use clap::Args;
use offsend_detect::{DetectionEngine, DetectionRequest};
use offsend_seal::{SealEngine, SealSpan};
use std::process::ExitCode;

#[derive(Debug, Args)]
pub struct KeygenArgs {
    /// Write the key to this file instead of stdout.
    #[arg(short, long)]
    pub output: Option<String>,

    /// Write the key to ~/.offsend/seal.key.
    #[arg(long = "default")]
    pub install_default: bool,

    /// Write a named key to ~/.offsend/keys/NAME.key.
    #[arg(long)]
    pub name: Option<String>,

    /// Overwrite an existing key file.
    #[arg(long)]
    pub force: bool,

    /// Write 32 raw bytes (requires a file target).
    #[arg(long)]
    pub raw: bool,

    /// Working directory used for relative --output paths.
    #[arg(long)]
    pub working_directory: Option<String>,
}

#[derive(Debug, Args)]
pub struct SealArgs {
    /// Text file to seal. Omit to read from stdin.
    pub path: Option<String>,

    #[arg(long)]
    pub key_file: Option<String>,

    #[arg(long)]
    pub key_name: Option<String>,

    #[arg(short, long)]
    pub output: Option<String>,

    #[arg(long)]
    pub force: bool,

    #[arg(long)]
    pub max_plaintext_bytes: Option<usize>,

    #[arg(long)]
    pub quiet: bool,

    #[arg(long)]
    pub working_directory: Option<String>,
}

#[derive(Debug, Args)]
pub struct UnsealArgs {
    pub path: Option<String>,
    #[arg(long)]
    pub key_file: Option<String>,
    #[arg(long)]
    pub key_name: Option<String>,
    #[arg(short, long)]
    pub output: Option<String>,
    #[arg(long)]
    pub force: bool,
    #[arg(long)]
    pub working_directory: Option<String>,
}

#[derive(Debug, thiserror::Error)]
pub enum CmdError {
    #[error("{0}")]
    Io(#[from] IoError),
    #[error("{0}")]
    Key(#[from] KeyError),
    #[error("{0}")]
    Seal(#[from] offsend_seal::SealError),
    #[error("{0}")]
    Message(String),
}

pub fn run_keygen(args: KeygenArgs) -> Result<ExitCode, CmdError> {
    let key = keys::generate();
    let cwd = io::working_dir(args.working_directory.as_deref());

    let targets = [
        args.output.is_some(),
        args.install_default,
        args.name.is_some(),
    ]
    .into_iter()
    .filter(|x| *x)
    .count();
    if targets > 1 {
        return Err(CmdError::Message(
            "Use only one target: --output, --default, or --name.".into(),
        ));
    }

    let target = if let Some(output) = &args.output {
        Some(io::resolve_path(output, &cwd))
    } else if args.install_default {
        Some(keys::default_key_path())
    } else if let Some(name) = &args.name {
        Some(keys::named_key_path(name)?)
    } else {
        None
    };

    match target {
        None => {
            if args.raw {
                return Err(CmdError::Message(
                    "--raw requires a file target (--output, --default, or --name).".into(),
                ));
            }
            println!(
                "{}",
                base64::Engine::encode(&base64::engine::general_purpose::STANDARD, key,)
            );
        }
        Some(path) => {
            keys::write_key(&key, &path, args.raw, args.force)?;
            eprintln!("Wrote seal key to {}", path.display());
        }
    }
    Ok(ExitCode::SUCCESS)
}

pub fn run_seal(args: SealArgs) -> Result<ExitCode, CmdError> {
    if args.force && args.output.is_none() {
        return Err(CmdError::Message("--force requires --output.".into()));
    }
    let cwd = io::working_dir(args.working_directory.as_deref());
    let key = keys::resolve(args.key_file.as_deref(), args.key_name.as_deref(), &cwd)?;
    let max = args
        .max_plaintext_bytes
        .unwrap_or(SealEngine::DEFAULT_MAX_PLAINTEXT_BYTES);
    if max == 0 {
        return Err(CmdError::Message(
            "--max-plaintext-bytes must be a positive integer.".into(),
        ));
    }

    let text = io::read_input(args.path.as_deref(), &cwd)?;
    let detection = DetectionEngine::scan(&DetectionRequest::new(text.clone()));
    let spans: Vec<SealSpan> = detection
        .entities
        .iter()
        .map(|e| SealSpan {
            start: e.start,
            end: e.end,
            value: e.value.clone(),
            type_label: e.entity_type.placeholder_prefix().to_string(),
        })
        .collect();

    let engine = SealEngine::with_max_plaintext_bytes(&key, max)?;
    let result = engine.seal_spans(&detection.scanned_text, &spans)?;
    io::write_output(
        &result.sealed_text,
        args.output.as_deref(),
        &cwd,
        args.force,
    )?;
    if !args.quiet {
        eprintln!("sealed {}", result.sealed_count);
    }
    Ok(ExitCode::SUCCESS)
}

pub fn run_unseal(args: UnsealArgs) -> Result<ExitCode, CmdError> {
    if args.force && args.output.is_none() {
        return Err(CmdError::Message("--force requires --output.".into()));
    }
    let cwd = io::working_dir(args.working_directory.as_deref());
    let key = keys::resolve(args.key_file.as_deref(), args.key_name.as_deref(), &cwd)?;
    let text = io::read_unseal_input(args.path.as_deref(), &cwd)?;
    let engine = SealEngine::new(&key)?;
    let restored = engine.unseal(&text)?;
    io::write_output(&restored, args.output.as_deref(), &cwd, args.force)?;
    Ok(ExitCode::SUCCESS)
}
