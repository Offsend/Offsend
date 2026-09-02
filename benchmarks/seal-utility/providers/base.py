from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class Completion:
    text: str
    prompt_tokens: int | None
    provider_request_id: str | None
    model_version: str | None


class Provider(Protocol):
    def complete(
        self,
        *,
        model: str,
        system: str,
        user: str,
        temperature: float,
        max_tokens: int,
    ) -> Completion: ...
