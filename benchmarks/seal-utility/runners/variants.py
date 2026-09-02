from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from runners.cases import Case
from runners.common import find_all_spans, replace_spans
from runners.fixtures import substitute_fixtures
from runners.offsend import seal_text
from runners.prompt import render_v1


@dataclass
class MaterializedCase:
    case: Case
    input: str
    secrets: list[dict[str, str]]
    variants: dict[str, str] = field(default_factory=dict)
    issued_tokens: list[str] = field(default_factory=list)


def listed_spans(text: str, secrets: list[dict[str, str]]) -> list[tuple[int, int, str]]:
    spans: list[tuple[int, int, str]] = []
    seen: set[tuple[int, int]] = set()
    for secret in secrets:
        found = find_all_spans(text, secret["value"])
        if not found:
            raise ValueError(f"listed secret {secret.get('fixture') or secret['type']} not in input")
        for start, end in found:
            key = (start, end)
            if key in seen:
                continue
            seen.add(key)
            spans.append((start, end, secret["value"]))
    return spans


def generate_delete(text: str, secrets: list[dict[str, str]]) -> str:
    spans = [(start, end, "") for start, end, _ in listed_spans(text, secrets)]
    return replace_spans(text, spans)


def generate_redacted(text: str, secrets: list[dict[str, str]]) -> str:
    spans = [(start, end, "[REDACTED]") for start, end, _ in listed_spans(text, secrets)]
    return replace_spans(text, spans)


def materialize_case(
    case: Case,
    fixture_values: dict[str, str],
    offsend: Path,
    key_path: Path,
) -> MaterializedCase:
    secrets = case.resolve_secrets(fixture_values)
    text = substitute_fixtures(case.input, fixture_values)
    for secret in secrets:
        if secret["value"] not in text:
            raise ValueError(f"{case.id}: secret {secret.get('fixture') or secret['type']} missing after materialize")
    sealed = seal_text(offsend, key_path, text)
    from runners.common import extract_seal_tokens

    return MaterializedCase(
        case=case,
        input=text,
        secrets=secrets,
        variants={
            "clean": text,
            "delete": generate_delete(text, secrets),
            "redacted": generate_redacted(text, secrets),
            "offsend": sealed,
        },
        issued_tokens=extract_seal_tokens(sealed),
    )


def prompt_for(case: Case, variant_context: str) -> tuple[str, str]:
    return render_v1(case.task, variant_context)
