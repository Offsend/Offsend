from __future__ import annotations

import base64
import hashlib
import json
from pathlib import Path
from typing import Any

import yaml

from runners.paths import BENCH_ROOT, SCHEMAS_DIR

FIXTURE_PLACEHOLDER = "{{fixture:"

_PASSWORD_WORDS = (
    "correct",
    "horse",
    "battery",
    "staple",
    "orchid",
    "maple",
    "river",
    "cinder",
    "velvet",
    "copper",
    "lantern",
    "pebble",
    "willow",
    "quartz",
    "nebula",
    "harbor",
    "flint",
    "cedar",
    "meadow",
    "onyx",
)


def load_fixture_catalog(path: Path | None = None) -> dict[str, dict[str, Any]]:
    path = path or (BENCH_ROOT / "fixtures.yaml")
    raw = yaml.safe_load(path.read_text()) or {}
    if not isinstance(raw, dict):
        raise ValueError("fixtures.yaml must be a mapping of id → generator")
    return raw


def materialize_value(fixture_id: str, kind: str, fixture_seed: str) -> str:
    digest = hashlib.sha256(f"{fixture_seed}:{fixture_id}:{kind}".encode("utf-8")).digest()
    if kind == "url_password":
        return _url_password(digest)
    if kind == "email":
        return f"ops.{digest[:4].hex()}@mail.example.com"
    if kind == "aws_access_key":
        return _aws_access_key(digest)
    if kind == "github_pat":
        return "ghp_" + _alnum(digest, 36)
    if kind == "openai_api_key":
        return "sk-" + _alnum(digest, 48)
    if kind == "stripe_secret":
        return "sk_live_51" + _alnum(digest, 24)
    if kind == "slack_bot":
        return (
            "xoxb-"
            + _digits(digest, 12)
            + "-"
            + _digits(digest[8:], 13)
            + "-"
            + _alnum(digest[16:], 24)
        )
    if kind == "jwt":
        return _jwt(digest)
    if kind == "bearer":
        return _alnum(digest, 32)
    raise ValueError(f"unknown fixture kind {kind!r} for {fixture_id}")


def materialize_catalog(catalog: dict[str, dict[str, Any]], fixture_seed: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for fixture_id, spec in catalog.items():
        kind = spec["kind"]
        values[fixture_id] = materialize_value(fixture_id, kind, fixture_seed)
    return values


def substitute_fixtures(text: str, values: dict[str, str]) -> str:
    out = text
    for fixture_id, value in values.items():
        out = out.replace(f"{{{{fixture:{fixture_id}}}}}", value)
    if FIXTURE_PLACEHOLDER in out:
        raise ValueError(f"unresolved fixture placeholder in text: {out}")
    return out


def _alnum(digest: bytes, n: int) -> str:
    alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    raw = digest
    while len(raw) < n:
        raw += hashlib.sha256(raw).digest()
    return "".join(alphabet[b % 62] for b in raw[:n])


def _digits(digest: bytes, n: int) -> str:
    raw = digest
    while len(raw) < n:
        raw += hashlib.sha256(raw).digest()
    return "".join(str(b % 10) for b in raw[:n])


def _url_password(digest: bytes) -> str:
    words = [_PASSWORD_WORDS[digest[i] % len(_PASSWORD_WORDS)] for i in range(3)]
    return f"{words[0]}-{words[1]}-{words[2]}-{digest[3] % 90 + 10}"


def _aws_access_key(digest: bytes) -> str:
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    chars = [alphabet[digest[i] % 36] for i in range(16)]
    if not any(c.isdigit() for c in chars):
        chars[0] = str(digest[16] % 10)
        chars[8] = str(digest[17] % 10)
    return "AKIA" + "".join(chars)


def _jwt(digest: bytes) -> str:
    header = _b64url(b'{"alg":"HS256","typ":"JWT"}')
    payload = _b64url(
        json.dumps(
            {"sub": digest[:8].hex(), "iat": 1_700_000_000},
            separators=(",", ":"),
        ).encode("utf-8")
    )
    sig = _b64url(digest + hashlib.sha256(digest).digest())
    return f"{header}.{payload}.{sig}"


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def fixtures_schema() -> dict[str, Any]:
    return json.loads((SCHEMAS_DIR / "fixtures.schema.json").read_text())
