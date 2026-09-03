from __future__ import annotations

from providers.anthropic import AnthropicProvider
from providers.base import Completion, Provider
from providers.openai import OpenAIProvider


def get_provider(name: str) -> Provider:
    if name == "openai":
        return OpenAIProvider()
    if name == "anthropic":
        return AnthropicProvider()
    raise ValueError(f"unknown provider {name}")


__all__ = ["Completion", "Provider", "get_provider"]
