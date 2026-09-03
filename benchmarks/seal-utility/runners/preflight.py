from __future__ import annotations

from dataclasses import dataclass

from runners.common import TRANSFORMED_VARIANTS, extract_seal_tokens
from runners.variants import MaterializedCase


@dataclass
class PreflightResult:
    ok: bool
    reason: str | None = None


def run_preflight(item: MaterializedCase) -> PreflightResult:
    secrets = [secret["value"] for secret in item.secrets]
    for variant in TRANSFORMED_VARIANTS:
        text = item.variants[variant]
        for value in secrets:
            if value in text:
                return PreflightResult(False, "seal_miss" if variant == "offsend" else "plaintext_absent")

    sealed = item.variants["offsend"]
    tokens = extract_seal_tokens(sealed)
    if len(tokens) < len(secrets):
        return PreflightResult(False, "overseal")
    for value in secrets:
        if value in sealed:
            return PreflightResult(False, "seal_miss")

    for fragment in item.case.expected_structure:
        if fragment not in sealed:
            return PreflightResult(False, "structure_lost")

    if not tokens:
        return PreflightResult(False, "overseal")
    return PreflightResult(True)
