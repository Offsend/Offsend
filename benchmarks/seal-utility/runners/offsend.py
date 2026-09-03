from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

from runners.paths import CACHE_DIR, REPO_ROOT


class OffsendError(RuntimeError):
    pass


def resolve_offsend_bin(explicit: str | None = None) -> Path:
    if explicit:
        path = Path(explicit).expanduser()
        candidates = [path] if path.is_absolute() else [Path.cwd() / path, REPO_ROOT / path]
        for candidate in candidates:
            resolved = candidate.resolve()
            if resolved.is_file():
                return resolved
        raise OffsendError(f"offsend binary not found: {path}")
    env = os.environ.get("OFFSEND_BIN")
    if env:
        path = Path(env).expanduser().resolve()
        if path.is_file():
            return path
    candidates = [
        REPO_ROOT / "target" / "release" / "offsend",
        REPO_ROOT / "target" / "debug" / "offsend",
    ]
    for path in candidates:
        if path.is_file():
            return path
    which = subprocess.run(["which", "offsend"], capture_output=True, text=True)
    if which.returncode == 0:
        return Path(which.stdout.strip())
    raise OffsendError(
        "offsend binary not found; pass --offsend or build with "
        "`cargo build -p offsend-cli --release`"
    )


def ensure_benchmark_key(offsend: Path, key_path: Path | None = None) -> Path:
    key_path = key_path or (CACHE_DIR / "benchmark.key")
    key_path.parent.mkdir(parents=True, exist_ok=True)
    if not key_path.is_file():
        _run(offsend, ["keygen", "-o", str(key_path), "--force"])
    return key_path


def seal_text(offsend: Path, key_path: Path, text: str) -> str:
    with tempfile.TemporaryDirectory() as tmp:
        return _run(
            offsend,
            [
                "seal",
                "--key-file",
                str(key_path),
                "--quiet",
                "--working-directory",
                tmp,
            ],
            stdin=text,
        )


def detect_findings(offsend: Path, text: str, *, secrets_only: bool = True) -> list[dict]:
    args = [
        "check",
        "--stdin",
        "--format",
        "json",
        "--fail-on",
        "none",
        "--quiet",
    ]
    if not secrets_only:
        args.append("--no-secrets-only")
    with tempfile.TemporaryDirectory() as tmp:
        args.extend(["--working-directory", tmp])
        raw = _run(offsend, args, stdin=text)
    report = json.loads(raw)
    findings = []
    for item in report.get("findings", []):
        start = int(item["start"])
        end = int(item["end"])
        findings.append(
            {
                "entity_type": item["entity_type"],
                "start": start,
                "end": end,
                "value": text[start:end],
                "is_secret": bool(item.get("is_secret")),
                "is_critical_secret": bool(item.get("is_critical_secret")),
            }
        )
    return findings


def offsend_version(offsend: Path) -> str | None:
    try:
        out = _run(offsend, ["--version"]).strip()
    except OffsendError:
        return None
    parts = out.split()
    return parts[-1] if parts else out or None


def _run(offsend: Path, args: list[str], stdin: str | None = None) -> str:
    proc = subprocess.run(
        [str(offsend), *args],
        input=stdin.encode("utf-8") if stdin is not None else None,
        capture_output=True,
    )
    if proc.returncode != 0:
        err = proc.stderr.decode("utf-8", errors="replace").strip()
        raise OffsendError(f"offsend {' '.join(args)} failed ({proc.returncode}): {err}")
    return proc.stdout.decode("utf-8")
