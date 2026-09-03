from __future__ import annotations

import json
import re
from typing import Any

# Entire response is one fenced block. Surrounding prose still fails.
_SINGLE_FENCE_RE = re.compile(r"^```(?:[A-Za-z0-9_+-]+)?\r?\n(.*)\r?\n```$", re.DOTALL)


def grade_json_fields(response: str, spec: dict[str, Any]) -> dict[str, Any]:
    expected = spec.get("expected")
    if not isinstance(expected, dict):
        raise ValueError("json_fields grader requires expected object")
    tolerance = spec.get("tolerance") or {}

    stripped, fence_error = _json_payload(response)
    if fence_error:
        return _fail("invalid_json", fence_error)
    try:
        parsed = json.loads(stripped)
    except json.JSONDecodeError as exc:
        return _fail("invalid_json", f"json_decode: {exc.msg}")
    if not isinstance(parsed, dict):
        return _fail("invalid_json", f"not_object: {type(parsed).__name__}")

    for key, want in expected.items():
        if key not in parsed:
            return _fail("lost_structure", f"missing_key: {key}")
        got = parsed[key]
        if not _values_equal(got, want, tolerance.get(key)):
            return _fail(
                "wrong_field_interpretation",
                f"field_mismatch: {key} (got {_type_name(got)}, expected {_type_name(want)})",
            )
    return {"score": 1, "failure_bucket": None, "failure_detail": None}


def _values_equal(got: Any, want: Any, tol: float | None) -> bool:
    if isinstance(want, bool) or isinstance(got, bool):
        return isinstance(got, bool) and isinstance(want, bool) and got is want
    if isinstance(want, str):
        return isinstance(got, str) and got.strip() == want.strip()
    if isinstance(want, int) and not isinstance(want, bool):
        if isinstance(got, bool) or not isinstance(got, (int, float)):
            return False
        if isinstance(got, float) and not got.is_integer():
            if tol is None:
                return False
            return abs(float(got) - float(want)) <= float(tol)
        return int(got) == want if tol is None else abs(float(got) - float(want)) <= float(tol)
    if isinstance(want, float):
        if isinstance(got, bool) or not isinstance(got, (int, float)):
            return False
        if tol is None:
            return float(got) == want
        return abs(float(got) - want) <= float(tol)
    if isinstance(want, list):
        return isinstance(got, list) and got == want
    return got == want


def _json_payload(response: str) -> tuple[str, str | None]:
    stripped = response.strip()
    if "```" not in stripped:
        return stripped, None
    match = _SINGLE_FENCE_RE.fullmatch(stripped)
    if not match:
        return "", "markdown_fence"
    return match.group(1).strip(), None


def _type_name(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, int):
        return "int"
    if isinstance(value, float):
        return "float"
    if isinstance(value, str):
        return "str"
    if isinstance(value, list):
        return "list"
    if isinstance(value, dict):
        return "object"
    return type(value).__name__


def _fail(bucket: str, detail: str) -> dict[str, Any]:
    return {"score": 0, "failure_bucket": bucket, "failure_detail": detail}
