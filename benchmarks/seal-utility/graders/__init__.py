from graders.contains_all import grade_contains_all
from graders.exact import grade_exact
from graders.json_fields import grade_json_fields
from graders.security import grade_security

__all__ = [
    "grade_contains_all",
    "grade_exact",
    "grade_json_fields",
    "grade_security",
    "grade_response",
]


def grade_response(kind: str, spec: dict, response: str) -> dict:
    if kind == "json_fields":
        return grade_json_fields(response, spec)
    if kind == "exact":
        return grade_exact(response, spec)
    if kind == "contains_all":
        return grade_contains_all(response, spec)
    raise ValueError(f"unknown grader kind {kind}")
