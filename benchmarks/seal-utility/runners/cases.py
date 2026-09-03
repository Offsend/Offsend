from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import jsonschema
import yaml

from runners.fixtures import load_fixture_catalog
from runners.paths import CASES_DIR, SCHEMAS_DIR

CATEGORIES = ("config", "debugging", "mcp", "transformation", "code")
CATEGORY_QUOTAS = {
    "config": 10,
    "debugging": 5,
    "mcp": 5,
    "transformation": 5,
    "code": 5,
}


@dataclass(frozen=True)
class SensitiveItem:
    type: str
    fixture: str | None
    inline_value: str | None


@dataclass(frozen=True)
class Case:
    id: str
    category: str
    task: str
    input: str
    sensitive: tuple[SensitiveItem, ...]
    expected_structure: tuple[str, ...]
    grader: dict[str, Any]
    placeholder_eligible: bool
    path: Path

    def resolve_secrets(self, fixture_values: dict[str, str]) -> list[dict[str, str]]:
        secrets: list[dict[str, str]] = []
        for item in self.sensitive:
            if item.fixture:
                if item.fixture not in fixture_values:
                    raise ValueError(f"{self.id}: unknown fixture {item.fixture}")
                value = fixture_values[item.fixture]
                secrets.append({"fixture": item.fixture, "value": value, "type": item.type})
            else:
                assert item.inline_value is not None
                secrets.append({"fixture": "", "value": item.inline_value, "type": item.type})
        return secrets


def load_case_schema() -> dict[str, Any]:
    import json

    return json.loads((SCHEMAS_DIR / "case.schema.json").read_text())


def load_cases(cases_dir: Path | None = None) -> list[Case]:
    cases_dir = cases_dir or CASES_DIR
    schema = load_case_schema()
    catalog = load_fixture_catalog()
    cases: list[Case] = []
    seen: set[str] = set()
    for path in sorted(cases_dir.glob("*/*.yaml")):
        raw = yaml.safe_load(path.read_text())
        jsonschema.validate(raw, schema)
        case = _parse_case(raw, path)
        folder = path.parent.name
        if folder == "code":
            if case.category not in ("code", "editing"):
                raise ValueError(f"{path}: category {case.category} does not match folder")
        elif case.category != folder:
            raise ValueError(f"{path}: category {case.category} does not match folder {folder}")
        if case.id in seen:
            raise ValueError(f"duplicate case id {case.id}")
        if case.id != path.stem:
            raise ValueError(f"{path}: filename must match id {case.id}")
        for item in case.sensitive:
            if item.fixture and item.fixture not in catalog:
                raise ValueError(f"{case.id}: fixture {item.fixture} not in fixtures.yaml")
            if item.inline_value and item.type not in ("password", "email"):
                raise ValueError(
                    f"{case.id}: inline value: only allowed for password/email, not {item.type}"
                )
        seen.add(case.id)
        cases.append(case)
    return cases


def assert_corpus_quotas(cases: list[Case]) -> None:
    counts: dict[str, int] = {name: 0 for name in CATEGORY_QUOTAS}
    multi = 0
    for case in cases:
        bucket = "code" if case.category in ("code", "editing") else case.category
        if bucket not in counts:
            raise ValueError(f"unknown category {case.category}")
        counts[bucket] += 1
        if len(case.sensitive) >= 2:
            multi += 1
    errors = [f"{name}: {counts[name]} != {quota}" for name, quota in CATEGORY_QUOTAS.items() if counts[name] != quota]
    if errors:
        raise ValueError("corpus quota mismatch: " + "; ".join(errors))
    if multi < 5:
        raise ValueError(f"need ≥5 multi-secret cases, found {multi}")


def _parse_case(raw: dict[str, Any], path: Path) -> Case:
    sensitive = tuple(
        SensitiveItem(
            type=item["type"],
            fixture=item.get("fixture"),
            inline_value=item.get("value"),
        )
        for item in raw["sensitive"]
    )
    return Case(
        id=raw["id"],
        category=raw["category"],
        task=raw["task"].strip("\n"),
        input=raw["input"].strip("\n") + ("\n" if raw["input"].endswith("\n") else ""),
        sensitive=sensitive,
        expected_structure=tuple(raw["expected_structure"]),
        grader=raw["grader"],
        placeholder_eligible=bool(raw["placeholder"]["eligible"]),
        path=path,
    )
