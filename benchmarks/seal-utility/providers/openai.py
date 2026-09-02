from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

from providers.base import Completion


class OpenAIProvider:
    def complete(
        self,
        *,
        model: str,
        system: str,
        user: str,
        temperature: float,
        max_tokens: int,
    ) -> Completion:
        api_key = os.environ.get("OPENAI_API_KEY")
        if not api_key:
            raise RuntimeError("OPENAI_API_KEY is not set")
        payload = {
            "model": model,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
        }
        req = urllib.request.Request(
            "https://api.openai.com/v1/chat/completions",
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        body = _request(req)
        choice = body["choices"][0]["message"]["content"] or ""
        usage = body.get("usage") or {}
        return Completion(
            text=choice,
            prompt_tokens=_int_or_none(usage.get("prompt_tokens")),
            provider_request_id=body.get("id"),
            model_version=body.get("model"),
        )


def _request(req: urllib.request.Request) -> dict:
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"OpenAI HTTP {exc.code}: {detail}") from exc


def _int_or_none(value) -> int | None:
    return int(value) if isinstance(value, int) else None
