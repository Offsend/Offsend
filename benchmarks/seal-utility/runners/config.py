from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import jsonschema
import yaml

from runners.paths import BENCH_ROOT, SCHEMAS_DIR


@dataclass(frozen=True)
class ModelSpec:
    id: str
    provider: str
    family: str | None


@dataclass(frozen=True)
class BenchmarkConfig:
    benchmark_version: str
    prompt_template: str
    conversation_mode: str
    runs_per_case: int
    temperature: float
    max_tokens: int
    runner_seed: str
    fixture_seed: str
    seal_token_version: str
    models: tuple[ModelSpec, ...]
    raw: dict[str, Any]


def load_benchmark_config(path: Path | None = None) -> BenchmarkConfig:
    path = path or (BENCH_ROOT / "benchmark.yaml")
    raw = yaml.safe_load(path.read_text())
    schema = json.loads((SCHEMAS_DIR / "benchmark.schema.json").read_text())
    jsonschema.validate(raw, schema)
    models = tuple(
        ModelSpec(id=item["id"], provider=item["provider"], family=item.get("family"))
        for item in raw["models"]
    )
    families = {m.family or m.provider for m in models}
    if len(families) < 2:
        raise ValueError("benchmark.yaml must list at least two model families")
    return BenchmarkConfig(
        benchmark_version=raw["benchmark_version"],
        prompt_template=raw["prompt_template"],
        conversation_mode=raw["conversation_mode"],
        runs_per_case=int(raw["runs_per_case"]),
        temperature=float(raw["temperature"]),
        max_tokens=int(raw.get("max_tokens", 1024)),
        runner_seed=str(raw["runner_seed"]),
        fixture_seed=str(raw["fixture_seed"]),
        seal_token_version=raw["seal_token_version"],
        models=models,
        raw=raw,
    )
