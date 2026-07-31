//! Build argv for `offsend run` — port of Swift `SandboxLaunch` /
//! `SandboxMechanismResolver`.

use crate::sandbox_provider::SandboxProvider;
use std::env;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EditorTarget {
    Cursor,
    Claude,
    Codex,
}

impl EditorTarget {
    pub fn parse(raw: &str) -> Option<Self> {
        match raw.trim().to_ascii_lowercase().as_str() {
            "cursor" => Some(Self::Cursor),
            "claude" => Some(Self::Claude),
            "codex" => Some(Self::Codex),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Cursor => "cursor",
            Self::Claude => "claude",
            Self::Codex => "codex",
        }
    }

    pub fn agent_binary(self) -> Option<&'static str> {
        match self {
            Self::Claude => Some("claude"),
            Self::Codex => Some("codex"),
            Self::Cursor => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SandboxMechanism {
    Wrapper,
    CursorNative,
    ClaudeNative,
    CodexUserScope,
    #[allow(dead_code)]
    Unavailable,
}

impl SandboxMechanism {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Wrapper => "wrapper",
            Self::CursorNative => "cursorNative",
            Self::ClaudeNative => "claudeNative",
            Self::CodexUserScope => "codexUserScope",
            Self::Unavailable => "unavailable",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Invocation {
    pub program: String,
    pub arguments: Vec<String>,
    pub display: String,
    pub uses_wrapper: bool,
    pub mechanism: Option<SandboxMechanism>,
    pub profile_relative_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LaunchError {
    UnsupportedTarget(String),
    MissingBinary(String),
    MissingWrapperProfile(String),
}

impl std::fmt::Display for LaunchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnsupportedTarget(name) => write!(
                f,
                "Unsupported editor for `offsend run`: {name}. Use cursor, claude, or codex."
            ),
            Self::MissingBinary(name) => write!(f, "Could not find `{name}` on PATH."),
            Self::MissingWrapperProfile(path) => write!(
                f,
                "Missing sandbox profile at {path}. Run `offsend sync` or `offsend run … --sync` first."
            ),
        }
    }
}

impl std::error::Error for LaunchError {}

pub fn plan(target: EditorTarget, wrapper_available: bool) -> SandboxMechanism {
    match target {
        EditorTarget::Claude | EditorTarget::Codex if wrapper_available => SandboxMechanism::Wrapper,
        EditorTarget::Cursor => SandboxMechanism::CursorNative,
        EditorTarget::Claude => SandboxMechanism::ClaudeNative,
        EditorTarget::Codex => SandboxMechanism::CodexUserScope,
    }
}

pub fn wrapper_available(provider: &SandboxProvider) -> bool {
    if let Some(env_name) = provider.detect_env.as_deref() {
        if env::var_os(env_name)
            .map(|v| !v.is_empty())
            .unwrap_or(false)
        {
            return true;
        }
    }
    which(&provider.binary).is_some()
}

pub fn which(program: &str) -> Option<PathBuf> {
    if program.starts_with('/') {
        let path = PathBuf::from(program);
        return is_executable(&path).then_some(path);
    }
    let path_var = env::var_os("PATH")?;
    for dir in env::split_paths(&path_var) {
        let candidate = dir.join(program);
        if is_executable(&candidate) {
            return Some(candidate);
        }
    }
    None
}

fn is_executable(path: &Path) -> bool {
    let Ok(meta) = std::fs::metadata(path) else {
        return false;
    };
    if !meta.is_file() {
        return false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        meta.permissions().mode() & 0o111 != 0
    }
    #[cfg(not(unix))]
    {
        true
    }
}

pub fn launch_hint(provider: &SandboxProvider, target: EditorTarget) -> String {
    let relative = provider.profile_relative_path(target.as_str());
    let binary = target.agent_binary().unwrap_or(target.as_str());
    let args = provider.expand_run_args(&relative, binary);
    let rendered = std::iter::once(provider.binary.as_str())
        .chain(args.iter().map(String::as_str))
        .collect::<Vec<_>>()
        .join(" ");
    format!(
        "Start {} through the sandbox: offsend run {} (or: {rendered}). \
         Offsend writes the profile; it cannot wrap a process that is already running.",
        target.as_str(),
        target.as_str()
    )
}

pub fn invocation(
    target: EditorTarget,
    sandbox_enabled: bool,
    provider: &SandboxProvider,
    wrapper_available: bool,
    agent_arguments: &[String],
    open_path: Option<&str>,
) -> Result<Invocation, LaunchError> {
    match target {
        EditorTarget::Cursor => Ok(cursor_invocation(
            sandbox_enabled,
            open_path,
            agent_arguments,
        )),
        EditorTarget::Claude | EditorTarget::Codex => Ok(cli_agent_invocation(
            target,
            sandbox_enabled,
            provider,
            wrapper_available,
            agent_arguments,
        )),
    }
}

fn cursor_invocation(
    sandbox_enabled: bool,
    open_path: Option<&str>,
    extra: &[String],
) -> Invocation {
    let mut arguments = vec!["-a".into(), "Cursor".into()];
    if let Some(path) = open_path.filter(|p| !p.is_empty()) {
        arguments.push(path.to_string());
    }
    arguments.extend(extra.iter().cloned());
    let display = std::iter::once("open".to_string())
        .chain(arguments.iter().cloned())
        .collect::<Vec<_>>()
        .join(" ");
    Invocation {
        program: "/usr/bin/open".into(),
        arguments,
        display,
        uses_wrapper: false,
        mechanism: sandbox_enabled.then_some(SandboxMechanism::CursorNative),
        profile_relative_path: None,
    }
}

fn cli_agent_invocation(
    target: EditorTarget,
    sandbox_enabled: bool,
    provider: &SandboxProvider,
    wrapper_available: bool,
    agent_arguments: &[String],
) -> Invocation {
    let binary = target.agent_binary().unwrap_or(target.as_str()).to_string();
    let mechanism = plan(target, wrapper_available);
    let wrap = sandbox_enabled && mechanism == SandboxMechanism::Wrapper;
    if wrap {
        let relative = provider.profile_relative_path(target.as_str());
        let mut arguments = provider.expand_run_args(&relative, &binary);
        arguments.extend(agent_arguments.iter().cloned());
        let display = std::iter::once(provider.binary.clone())
            .chain(arguments.iter().cloned())
            .collect::<Vec<_>>()
            .join(" ");
        return Invocation {
            program: provider.binary.clone(),
            arguments,
            display,
            uses_wrapper: true,
            mechanism: Some(SandboxMechanism::Wrapper),
            profile_relative_path: Some(relative),
        };
    }

    let display = std::iter::once(binary.clone())
        .chain(agent_arguments.iter().cloned())
        .collect::<Vec<_>>()
        .join(" ");
    Invocation {
        program: binary,
        arguments: agent_arguments.to_vec(),
        display,
        uses_wrapper: false,
        mechanism: sandbox_enabled.then_some(mechanism),
        profile_relative_path: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn provider() -> SandboxProvider {
        crate::sandbox_provider::resolve(None, None, false)
            .expect("shipped nono")
            .provider
    }

    #[test]
    fn claude_without_sandbox_launches_bare() {
        let inv = invocation(
            EditorTarget::Claude,
            false,
            &provider(),
            true,
            &["-p".into(), "hi".into()],
            None,
        )
        .unwrap();
        assert_eq!(inv.program, "claude");
        assert_eq!(inv.arguments, vec!["-p", "hi"]);
        assert!(!inv.uses_wrapper);
        assert!(inv.mechanism.is_none());
        assert_eq!(inv.display, "claude -p hi");
    }

    #[test]
    fn claude_with_sandbox_and_wrapper_wraps() {
        let inv = invocation(EditorTarget::Claude, true, &provider(), true, &[], None).unwrap();
        assert_eq!(inv.program, "nono");
        assert_eq!(
            inv.arguments,
            vec![
                "run",
                "--profile",
                "./.offsend/nono/offsend-claude.json",
                "--allow-cwd",
                "--",
                "claude",
            ]
        );
        assert!(inv.uses_wrapper);
        assert_eq!(inv.mechanism, Some(SandboxMechanism::Wrapper));
        assert_eq!(
            inv.profile_relative_path.as_deref(),
            Some(".offsend/nono/offsend-claude.json")
        );
    }

    #[test]
    fn claude_with_sandbox_without_wrapper_bare() {
        let inv = invocation(EditorTarget::Claude, true, &provider(), false, &[], None).unwrap();
        assert_eq!(inv.program, "claude");
        assert!(inv.arguments.is_empty());
        assert!(!inv.uses_wrapper);
        assert_eq!(inv.mechanism, Some(SandboxMechanism::ClaudeNative));
    }

    #[test]
    fn codex_with_wrapper_wraps() {
        let inv = invocation(
            EditorTarget::Codex,
            true,
            &provider(),
            true,
            &["exec".into(), "ls".into()],
            None,
        )
        .unwrap();
        assert_eq!(inv.program, "nono");
        assert!(inv.arguments.iter().any(|a| a == "codex"));
        assert_eq!(
            inv.arguments[inv.arguments.len() - 2..],
            ["exec".to_string(), "ls".to_string()]
        );
        assert_eq!(
            inv.profile_relative_path.as_deref(),
            Some(".offsend/nono/offsend-codex.json")
        );
    }

    #[test]
    fn custom_binary_from_provider() {
        let mut p = provider();
        p.binary = "/opt/wrap".into();
        let inv = invocation(EditorTarget::Claude, true, &p, true, &[], None).unwrap();
        assert_eq!(inv.program, "/opt/wrap");
        assert!(inv.display.starts_with("/opt/wrap "));
    }

    #[test]
    fn cursor_never_uses_wrapper() {
        let inv = invocation(
            EditorTarget::Cursor,
            true,
            &provider(),
            true,
            &[],
            Some("/tmp/repo"),
        )
        .unwrap();
        assert_eq!(inv.program, "/usr/bin/open");
        assert_eq!(inv.arguments, vec!["-a", "Cursor", "/tmp/repo"]);
        assert!(!inv.uses_wrapper);
        assert_eq!(inv.mechanism, Some(SandboxMechanism::CursorNative));
    }

    #[test]
    fn cursor_without_sandbox_still_opens() {
        let inv = invocation(EditorTarget::Cursor, false, &provider(), true, &[], None).unwrap();
        assert_eq!(inv.program, "/usr/bin/open");
        assert_eq!(inv.arguments, vec!["-a", "Cursor"]);
        assert!(inv.mechanism.is_none());
    }

    #[test]
    fn windsurf_rejected_via_parse() {
        assert!(EditorTarget::parse("windsurf").is_none());
    }
}
