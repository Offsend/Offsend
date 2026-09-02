from __future__ import annotations

import hashlib
import re
from typing import Iterable

SEAL_TOKEN_RE = re.compile(r"\{\{([A-Z][A-Z0-9_]*):v1\.([A-Za-z0-9_-]+)\}\}")

VARIANTS = ("clean", "delete", "redacted", "offsend")
TRANSFORMED_VARIANTS = ("delete", "redacted", "offsend")


def utf8_sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def find_all_spans(text: str, needle: str) -> list[tuple[int, int]]:
    if not needle:
        raise ValueError("empty span needle")
    spans: list[tuple[int, int]] = []
    start = 0
    while True:
        idx = text.find(needle, start)
        if idx < 0:
            break
        end = idx + len(needle)
        spans.append((idx, end))
        start = end
    return spans


def replace_spans(text: str, replacements: Iterable[tuple[int, int, str]]) -> str:
    ordered = sorted(replacements, key=lambda item: (item[0], -(item[1] - item[0])))
    kept: list[tuple[int, int, str]] = []
    last_end = -1
    for start, end, repl in ordered:
        if start < last_end:
            continue
        kept.append((start, end, repl))
        last_end = end
    out = text
    for start, end, repl in sorted(kept, key=lambda item: item[0], reverse=True):
        out = out[:start] + repl + out[end:]
    return out


def extract_seal_tokens(text: str) -> list[str]:
    return [match.group(0) for match in SEAL_TOKEN_RE.finditer(text)]


def contains_exact(haystack: str, needle: str) -> bool:
    return needle in haystack
