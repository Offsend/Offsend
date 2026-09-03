from __future__ import annotations

from typing import Any


def grade_exact(response: str, spec: dict[str, Any]) -> dict[str, Any]:
    expected = spec.get("expected")
    if not isinstance(expected, str):
        raise ValueError("exact grader requires expected string")
    if response.strip() == expected.strip():
        return {"score": 1, "failure_bucket": None, "failure_detail": None}
    return {
        "score": 0,
        "failure_bucket": "task_failure_other",
        "failure_detail": "exact_mismatch",
    }
