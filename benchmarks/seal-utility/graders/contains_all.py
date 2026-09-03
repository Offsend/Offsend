from __future__ import annotations

from typing import Any


def grade_contains_all(response: str, spec: dict[str, Any]) -> dict[str, Any]:
    required = spec.get("required")
    if not isinstance(required, list) or not required:
        raise ValueError("contains_all grader requires required string list")
    for item in required:
        if not isinstance(item, str) or item not in response:
            label = item if isinstance(item, str) else type(item).__name__
            return {
                "score": 0,
                "failure_bucket": "lost_structure",
                "failure_detail": f"missing_substring: {label}",
            }
    return {"score": 1, "failure_bucket": None, "failure_detail": None}
