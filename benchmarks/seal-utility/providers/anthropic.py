from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

from providers.base import Completion


class AnthropicProvider:
    def complete(
        self,
        *,
        model: str,
        system: str,
        user: str,
        temperature: float,
        max_tokens: int,
    ) -> Completion:
        api_key = os.environ.get("ANTHROPIC_API_KEY")
        if not api_key:
            raise RuntimeError("ANTHROPIC_API_KEY is not set")
        workspace_id = (os.environ.get("ANTHROPIC_WORKSPACE_ID") or "").strip()
        payload = {
            "model": model,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "system": system,
            "messages": [{"role": "user", "content": user}],
        }
        headers = {
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        }
        if workspace_id:
            headers["anthropic-workspace-id"] = workspace_id
        req = urllib.request.Request(
            "https://api.anthropic.com/v1/messages",
            data=json.dumps(payload).encode("utf-8"),
            headers=headers,
            method="POST",
        )
        body = _request(req)
        parts = body.get("content") or []
        text = "".join(part.get("text", "") for part in parts if part.get("type") == "text")
        usage = body.get("usage") or {}
        return Completion(
            text=text,
            prompt_tokens=_int_or_none(usage.get("input_tokens")),
            provider_request_id=body.get("id"),
            model_version=body.get("model"),
        )


def _request(req: urllib.request.Request) -> dict:
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        if (
            exc.code == 400
            and "anthropic-workspace-id is required" in detail
            and not (os.environ.get("ANTHROPIC_WORKSPACE_ID") or "").strip()
        ):
            raise RuntimeError(
                "Anthropic identity-linked key requires a workspace. "
                "Set ANTHROPIC_WORKSPACE_ID to a wrkspc_… id from "
                "Claude Console → Settings → Workspaces."
            ) from exc
        raise RuntimeError(f"Anthropic HTTP {exc.code}: {detail}") from exc


def _int_or_none(value) -> int | None:
    return int(value) if isinstance(value, int) else None
