//! `--shell-gate`

use super::artifacts::{self, Enforcement};
use super::render::{self, Permission};
use super::sensitive::{self, is_suspicious};
use super::Adapter;
use serde_json::Value;
use std::process::ExitCode;

#[derive(Clone, Copy, PartialEq, Eq)]
enum ShellMode {
    Deny,
    Ask,
}

pub fn run(
    adapter: Adapter,
    stdin: &str,
    shell_mode: Option<&str>,
    ignore_patterns: &[String],
    project_root: Option<&std::path::Path>,
    sandbox_required: bool,
) -> ExitCode {
    if !matches!(adapter, Adapter::Cursor | Adapter::Claude) {
        return render::permission_response(adapter, Permission::Allow, None, None);
    }
    let mode = match shell_mode.unwrap_or("deny") {
        "ask" => ShellMode::Ask,
        _ => ShellMode::Deny,
    };

    if stdin.len() > crate::io::MAX_INPUT_BYTES {
        return finish(
            adapter,
            Permission::Deny,
            "Offsend: blocked this shell command — hook input exceeds the safety limit.",
        );
    }
    let root: Value = match serde_json::from_str(stdin) {
        Ok(v) => v,
        Err(_) => {
            return finish(
                adapter,
                Permission::Deny,
                "Offsend: unrecognized shell-gate hook input denied.",
            )
        }
    };
    let Some(command) = extract_command(&root, adapter) else {
        return finish(
            adapter,
            Permission::Deny,
            "Offsend: unrecognized shell-gate hook input denied.",
        );
    };
    let cwd = root.get("cwd").and_then(|v| v.as_str());

    let mut deny = false;
    let mut ask = false;
    let mut reasons = Vec::new();

    // Editor-reported sandbox bit. Unknown/absent stays silent; only an
    // explicit `sandbox: false` is actionable when the project requires one.
    if sandbox_required {
        if root.get("sandbox").and_then(|v| v.as_bool()) == Some(false) {
            if mode == ShellMode::Deny {
                deny = true;
            } else {
                ask = true;
            }
            reasons.push(
                "Offsend: command is running outside the editor sandbox while sandbox.enabled is true."
                    .into(),
            );
        }
    }

    if references_policy_mutation(&command) {
        deny = true;
        reasons.push(
            "Offsend: agents cannot trust/forget the trusted policy snapshot. Run this yourself."
                .into(),
        );
    }
    if references_unseal(&command) {
        deny = true;
        reasons.push(
            "Offsend blocked `offsend unseal` — it restores sealed secrets to plaintext.".into(),
        );
    }
    if let Some(key) = git_config_sensitive(&command) {
        deny = true;
        reasons.push(format!(
            "Offsend blocked Git config mutation on execution-sensitive key {key}."
        ));
    }
    if let Some(var) = env_poisoning(&command) {
        deny = true;
        reasons.push(format!(
            "Offsend blocked the {var} override because it changes the host execution environment."
        ));
    }
    if let Some(msg) = privileged_daemon(&command) {
        deny = true;
        reasons.push(msg);
    }

    for candidate in path_candidates(&command) {
        let path = sensitive::resolve_path(&candidate, cwd);
        if let Some(artifact) = artifacts::classify(&path) {
            match artifact.enforcement {
                Enforcement::Deny => {
                    deny = true;
                    reasons.push(format!(
                        "Offsend blocked this command because it targets executable workspace configuration ({}).",
                        std::path::Path::new(&path).file_name().and_then(|s| s.to_str()).unwrap_or("file")
                    ));
                }
                Enforcement::DenyWhenContentExecutable => {
                    if mode == ShellMode::Deny {
                        deny = true;
                    } else {
                        ask = true;
                    }
                    reasons.push(format!(
                        "Offsend: command targets editor configuration ({}).",
                        std::path::Path::new(&path)
                            .file_name()
                            .and_then(|s| s.to_str())
                            .unwrap_or("file")
                    ));
                }
                Enforcement::Observe => {}
            }
        }
        for check in sensitive::sensitivity_check_paths(&path, cwd) {
            if is_suspicious(&check) {
                if mode == ShellMode::Deny {
                    deny = true;
                } else {
                    ask = true;
                }
                reasons.push(format!(
                    "Offsend: command references sensitive path ({}).",
                    std::path::Path::new(&check)
                        .file_name()
                        .and_then(|s| s.to_str())
                        .unwrap_or("path")
                ));
            }
        }
        if let Some(proj) = project_root {
            if matches_ignore_pattern(&candidate, &path, ignore_patterns, proj) {
                if mode == ShellMode::Deny {
                    deny = true;
                } else {
                    ask = true;
                }
                reasons.push(format!(
                    "Offsend: command references a path covered by ignore.patterns ({}).",
                    candidate
                ));
            }
        }
    }

    if deny {
        finish(adapter, Permission::Deny, &reasons.join(" "))
    } else if ask {
        finish(adapter, Permission::Ask, &reasons.join(" "))
    } else {
        render::permission_response(adapter, Permission::Allow, None, None)
    }
}

fn matches_ignore_pattern(
    candidate: &str,
    resolved: &str,
    patterns: &[String],
    project_root: &std::path::Path,
) -> bool {
    use offsend_policy::PathExcludeMatcher;
    if patterns.is_empty() {
        return false;
    }
    // `fixtures/` means the directory tree; PathExcludeMatcher treats trailing
    // `/` as a glob path, so normalize to `fixtures/**` for directory coverage.
    let normalized: Vec<String> = patterns
        .iter()
        .map(|p| {
            if p.ends_with('/') && !p.ends_with("/**") {
                format!("{}**", p)
            } else {
                p.clone()
            }
        })
        .collect();
    let root = project_root
        .canonicalize()
        .unwrap_or_else(|_| project_root.to_path_buf());
    let root_s = root.to_string_lossy();
    for rel in [candidate, resolved] {
        let trimmed = rel.trim_start_matches("./");
        if PathExcludeMatcher::is_excluded(trimmed, &normalized) {
            return true;
        }
        // Bare directory name (`fixtures`) matches `fixtures/**`.
        if PathExcludeMatcher::is_excluded(&format!("{trimmed}/x"), &normalized) {
            return true;
        }
        let abs = std::path::Path::new(rel);
        let abs_s = abs.to_string_lossy();
        if let Some(suffix) = abs_s.strip_prefix(root_s.as_ref()) {
            let rel = suffix.trim_start_matches('/');
            if PathExcludeMatcher::is_excluded(rel, &normalized)
                || PathExcludeMatcher::is_excluded(&format!("{rel}/x"), &normalized)
            {
                return true;
            }
        }
    }
    false
}

fn finish(adapter: Adapter, permission: Permission, reason: &str) -> ExitCode {
    render::permission_response(adapter, permission, Some(reason), Some(reason))
}

fn extract_command<'a>(root: &'a Value, adapter: Adapter) -> Option<&'a str> {
    match adapter {
        Adapter::Cursor => root.get("command").and_then(|v| v.as_str()),
        Adapter::Claude => root
            .pointer("/tool_input/command")
            .or_else(|| root.get("command"))
            .and_then(|v| v.as_str()),
        _ => None,
    }
}

fn references_policy_mutation(command: &str) -> bool {
    let tokens = shell_tokens(command);
    tokens.windows(3).any(|w| {
        executable_name(&w[0]) == "offsend"
            && w[1] == "policy"
            && matches!(w[2].as_str(), "trust" | "forget")
    })
}

fn references_unseal(command: &str) -> bool {
    let tokens = shell_tokens(command);
    tokens
        .windows(2)
        .any(|w| executable_name(&w[0]) == "offsend" && w[1] == "unseal")
}

fn git_config_sensitive(command: &str) -> Option<&'static str> {
    let tokens = shell_tokens(command);
    let Some(git_i) = tokens.iter().position(|t| executable_name(t) == "git") else {
        return None;
    };
    let rest = &tokens[git_i + 1..];
    if rest.first().map(|s| s.as_str()) != Some("config") {
        return None;
    }
    // Read-only forms are always allowed.
    let listing = rest.iter().any(|t| {
        matches!(
            t.as_str(),
            "-l" | "--list" | "--get" | "-get" | "--get-all" | "--get-regexp"
        )
    });
    if listing {
        return None;
    }
    const KEYS: &[&str] = &[
        "core.hookspath",
        "core.sshcommand",
        "core.gitproxy",
        "core.fsmonitor",
        "core.editor",
        "core.pager",
        "core.askpass",
        "init.templatedir",
        "sequence.editor",
        "diff.external",
        "gpg.program",
        "include.path",
        "credential.helper",
    ];
    for t in rest.iter().skip(1) {
        let key = t.trim_start_matches("--").to_ascii_lowercase();
        if KEYS
            .iter()
            .any(|k| key == *k || key.starts_with(&format!("{k}=")))
        {
            return Some("git-config");
        }
        if key.starts_with("alias.") || key.starts_with("pager.") {
            return Some("git-config");
        }
        if matches!(key.as_str(), "edit" | "-e" | "--edit") {
            return Some("core.editor");
        }
    }
    // any other `git config` without a read flag is treated as a mutation attempt
    Some("git-config")
}

fn env_poisoning(command: &str) -> Option<String> {
    const HARD: &[&str] = &[
        "BASH_ENV",
        "ENV",
        "ZDOTDIR",
        "IFS",
        "CDPATH",
        "SHELLOPTS",
        "NODE_OPTIONS",
        "PYTHONPATH",
        "PYTHONSTARTUP",
        "PYTHONHOME",
        "LD_PRELOAD",
        "DYLD_INSERT_LIBRARIES",
        "GIT_SSH_COMMAND",
        "GIT_ASKPASS",
        "GIT_EDITOR",
        "SSH_ASKPASS",
    ];
    let upper = command.to_ascii_uppercase();
    for var in HARD {
        if upper.contains(&format!("{var}=")) {
            return Some((*var).to_string());
        }
    }
    if upper.contains("DYLD_") || upper.contains("LD_") || upper.contains("GIT_CONFIG_") {
        return Some("loader/git-config env".into());
    }
    // Any PATH= override can redirect which binaries run next.
    if shell_tokens(command)
        .iter()
        .any(|t| t.starts_with("PATH=") || t.starts_with("path="))
        || command.contains("PATH=")
    {
        return Some("PATH".into());
    }
    None
}

fn privileged_daemon(command: &str) -> Option<String> {
    let lower = command.to_ascii_lowercase();
    if ["docker.sock", "podman.sock", "containerd.sock", "unix://"]
        .iter()
        .any(|m| lower.contains(m))
    {
        return Some("Offsend blocked access to a container daemon socket.".into());
    }
    let tokens = shell_tokens(command);
    let Some(first) = tokens.first() else {
        return None;
    };
    let exe = executable_name(first);
    if matches!(
        exe.as_str(),
        "docker" | "podman" | "nerdctl" | "docker-compose"
    ) {
        let ops = [
            "run", "create", "exec", "start", "attach", "cp", "up", "build", "pull", "push",
            "commit", "load", "import", "tag",
        ];
        if tokens.iter().any(|t| ops.contains(&t.as_str()))
            || lower.contains("--privileged")
            || lower.contains("--network=host")
            || lower.contains("--pid=host")
        {
            return Some(format!(
                "Offsend blocked container operation through {exe} outside the agent sandbox."
            ));
        }
    }
    None
}

fn path_candidates(command: &str) -> Vec<String> {
    let mut out = Vec::new();
    for token in shell_tokens(command) {
        let t = token.trim_matches('\'').trim_matches('"');
        if t.contains('/') || t.starts_with('.') || t.contains('\\') {
            if !t.starts_with('-') {
                out.push(t.to_string());
            }
        }
    }
    // Reconstruct adjacent string literals joined by `+` (e.g. "c"+"ert"+".pem"
    // or "f"+"ixtures"). Always keep them — ignore.patterns may name bare dirs.
    for reconstructed in adjacent_string_concats(command) {
        if !reconstructed.is_empty() {
            out.push(reconstructed);
        }
    }
    // Also pull quoted path-shaped literals out of heredoc / python bodies.
    for lit in quoted_literals(command) {
        if lit.contains('/') || lit.starts_with('.') || lit.contains('\\') || !lit.contains(' ')
        {
            if !lit.starts_with('-') && !lit.is_empty() {
                out.push(lit);
            }
        }
    }
    out
}

fn quoted_literals(command: &str) -> Vec<String> {
    let s = command.replace("\\\"", "\"");
    let chars: Vec<char> = s.chars().collect();
    let mut out = Vec::new();
    let mut i = 0usize;
    while i < chars.len() {
        if let Some((end, val)) = read_quoted_literal(&chars, i) {
            out.push(val);
            i = end;
        } else {
            i += 1;
        }
    }
    out
}

/// Join `"a"+"b"+"c"` / `'a'+'b'` chains (including shell-escaped `\"`) into one string.
fn adjacent_string_concats(command: &str) -> Vec<String> {
    let s = command.replace("\\\"", "\"");
    let chars: Vec<char> = s.chars().collect();
    let mut out = Vec::new();
    let mut i = 0usize;
    while i < chars.len() {
        let Some((mut end, mut joined)) = read_quoted_literal(&chars, i) else {
            i += 1;
            continue;
        };
        let start = i;
        let mut j = end;
        let mut chained = false;
        loop {
            let mut k = j;
            while k < chars.len() && chars[k].is_whitespace() {
                k += 1;
            }
            if k >= chars.len() || chars[k] != '+' {
                break;
            }
            k += 1;
            while k < chars.len() && chars[k].is_whitespace() {
                k += 1;
            }
            let Some((next_end, piece)) = read_quoted_literal(&chars, k) else {
                break;
            };
            joined.push_str(&piece);
            chained = true;
            j = next_end;
            end = next_end;
        }
        if chained {
            out.push(joined);
            i = end;
        } else {
            i = start + 1;
        }
    }
    out
}

fn read_quoted_literal(chars: &[char], start: usize) -> Option<(usize, String)> {
    if start >= chars.len() {
        return None;
    }
    let q = chars[start];
    if q != '"' && q != '\'' {
        return None;
    }
    let mut i = start + 1;
    let mut val = String::new();
    while i < chars.len() {
        if chars[i] == '\\' && i + 1 < chars.len() {
            val.push(chars[i + 1]);
            i += 2;
            continue;
        }
        if chars[i] == q {
            return Some((i + 1, val));
        }
        val.push(chars[i]);
        i += 1;
    }
    None
}

fn shell_tokens(command: &str) -> Vec<String> {
    // Naive tokenizer: split on whitespace; good enough for control-plane matchers.
    command
        .split_whitespace()
        .map(|s| s.trim_matches(|c| c == ';' || c == '&' || c == '|'))
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .collect()
}

fn executable_name(token: &str) -> String {
    std::path::Path::new(token)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or(token)
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reconstructs_adjacent_string_concat() {
        let cmd = r#"python3 -c 'from pathlib import Path; list(Path("f"+"ixtures").iterdir())'"#;
        let got = adjacent_string_concats(cmd);
        assert!(
            got.iter().any(|s| s == "fixtures"),
            "expected fixtures in {got:?}"
        );
        let candidates = path_candidates(cmd);
        assert!(
            candidates.iter().any(|s| s == "fixtures"),
            "expected fixtures candidate in {candidates:?}"
        );
    }

    #[test]
    fn fixtures_dir_pattern_matches_basename() {
        assert!(matches_ignore_pattern(
            "fixtures",
            "/tmp/proj/fixtures",
            &["fixtures/".into()],
            std::path::Path::new("/tmp/proj"),
        ));
    }
}
