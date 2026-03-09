#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
CLI_SCRIPT = ROOT / "tools" / "transcribe_audio" / "transcribe_cli.py"
TRANSCRIBE_VENV_PYTHON = ROOT / ".tools" / "transcribe_audio" / ".venv" / "bin" / "python"
SERVER_NAME = "transcribe_audio"
SERVER_VERSION = "0.1.0"
SUPPORTED_PROTOCOL_VERSIONS = {"2024-11-05", "2025-03-26"}


def _python_executable() -> str:
    if TRANSCRIBE_VENV_PYTHON.exists():
        return str(TRANSCRIBE_VENV_PYTHON)
    return sys.executable


def _tool_success(payload: dict[str, Any]) -> dict[str, Any]:
    text = json.dumps(payload, ensure_ascii=False, indent=2)
    return {
        "content": [{"type": "text", "text": text}],
        "structuredContent": payload,
        "isError": payload.get("ok") is False,
    }


def _tool_error(message: str) -> dict[str, Any]:
    payload = {"ok": False, "error": message}
    return {
        "content": [{"type": "text", "text": json.dumps(payload, ensure_ascii=False, indent=2)}],
        "structuredContent": payload,
        "isError": True,
    }


def _run_cli(arguments: list[str]) -> dict[str, Any]:
    command = [_python_executable(), str(CLI_SCRIPT), *arguments]
    completed = subprocess.run(
        command,
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    stdout = completed.stdout.strip()
    stderr = completed.stderr.strip()

    if stdout:
        try:
            payload = json.loads(stdout)
        except json.JSONDecodeError as exc:
            raise RuntimeError(f"Invalid CLI JSON output: {exc}") from exc
    else:
        payload = {"ok": completed.returncode == 0}

    if completed.returncode != 0 and payload.get("ok") is not False:
        payload = {
            "ok": False,
            "error": payload.get("error") or stderr or f"CLI exited with status {completed.returncode}.",
        }

    if stderr and "stderr" not in payload:
        payload["stderr"] = stderr

    return payload


def _tool_definitions() -> list[dict[str, Any]]:
    return [
        {
            "name": "transcribe_file",
            "description": "Transcribe one local audio/video file and record the result in local history.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "input_path": {"type": "string"},
                    "outdir": {"type": "string"},
                    "model": {"type": "string", "enum": ["small", "medium"]},
                    "compute_type": {"type": "string", "enum": ["int8", "int8_float16", "float16"]},
                },
                "required": ["input_path"],
                "additionalProperties": False,
            },
        },
        {
            "name": "transcribe_directory",
            "description": "Transcribe every supported media file under one local directory and record the result in local history.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "input_dir": {"type": "string"},
                    "outdir": {"type": "string"},
                    "model": {"type": "string", "enum": ["small", "medium"]},
                    "compute_type": {"type": "string", "enum": ["int8", "int8_float16", "float16"]},
                },
                "required": ["input_dir"],
                "additionalProperties": False,
            },
        },
        {
            "name": "get_result",
            "description": "Get one transcription job by job id.",
            "inputSchema": {
                "type": "object",
                "properties": {"job_id": {"type": "string"}},
                "required": ["job_id"],
                "additionalProperties": False,
            },
        },
        {
            "name": "list_outputs",
            "description": "List recent transcription jobs from local history.",
            "inputSchema": {
                "type": "object",
                "properties": {"limit": {"type": "integer", "minimum": 1, "maximum": 500}},
                "additionalProperties": False,
            },
        },
    ]


def _handle_tool_call(name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    if name == "transcribe_file":
        payload = _run_cli(
            [
                "transcribe",
                "--input",
                arguments["input_path"],
                *(_outdir_args(arguments)),
                *(_model_args(arguments)),
                *(_compute_type_args(arguments)),
            ]
        )
        return _tool_success(payload)

    if name == "transcribe_directory":
        payload = _run_cli(
            [
                "transcribe",
                "--input",
                arguments["input_dir"],
                *(_outdir_args(arguments)),
                *(_model_args(arguments)),
                *(_compute_type_args(arguments)),
            ]
        )
        return _tool_success(payload)

    if name == "get_result":
        payload = _run_cli(["get_result", "--job-id", arguments["job_id"]])
        return _tool_success(payload)

    if name == "list_outputs":
        payload = _run_cli(["list_outputs", "--limit", str(int(arguments.get("limit", 50)))])
        return _tool_success(payload)

    return _tool_error(f"Unknown tool: {name}")


def _outdir_args(arguments: dict[str, Any]) -> list[str]:
    outdir = arguments.get("outdir")
    return ["--outdir", outdir] if outdir else []


def _model_args(arguments: dict[str, Any]) -> list[str]:
    model = arguments.get("model")
    return ["--model", model] if model else []


def _compute_type_args(arguments: dict[str, Any]) -> list[str]:
    compute_type = arguments.get("compute_type")
    return ["--compute-type", compute_type] if compute_type else []


def _read_message() -> dict[str, Any] | None:
    headers: dict[str, str] = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        if line in (b"\r\n", b"\n"):
            break
        decoded = line.decode("utf-8").strip()
        if ":" not in decoded:
            continue
        key, value = decoded.split(":", 1)
        headers[key.lower()] = value.strip()

    content_length = int(headers.get("content-length", "0"))
    if content_length <= 0:
        return None
    body = sys.stdin.buffer.read(content_length)
    if not body:
        return None
    return json.loads(body.decode("utf-8"))


def _write_message(payload: dict[str, Any]) -> None:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(body)}\r\n\r\n".encode("ascii"))
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()


def _response(msg_id: Any, result: Any) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": msg_id, "result": result}


def _error(msg_id: Any, code: int, message: str) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": msg_id, "error": {"code": code, "message": message}}


def _handle_request(message: dict[str, Any]) -> dict[str, Any] | None:
    method = message.get("method", "")
    msg_id = message.get("id")
    params = message.get("params", {}) or {}

    if method == "notifications/initialized":
        return None
    if method == "initialize":
        requested = params.get("protocolVersion") or "2024-11-05"
        protocol_version = requested if requested in SUPPORTED_PROTOCOL_VERSIONS else "2024-11-05"
        return _response(
            msg_id,
            {
                "protocolVersion": protocol_version,
                "capabilities": {"tools": {}},
                "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
            },
        )
    if method == "ping":
        return _response(msg_id, {})
    if method == "tools/list":
        return _response(msg_id, {"tools": _tool_definitions()})
    if method == "tools/call":
        try:
            name = params["name"]
            arguments = params.get("arguments", {}) or {}
            return _response(msg_id, _handle_tool_call(name, arguments))
        except Exception as exc:
            return _response(msg_id, _tool_error(str(exc)))
    if method.startswith("notifications/") or method.startswith("$/"):
        return None
    return _error(msg_id, -32601, f"Method not found: {method}")


def main() -> int:
    os.environ.setdefault("PYTHONUNBUFFERED", "1")
    while True:
        message = _read_message()
        if message is None:
            return 0
        try:
            response = _handle_request(message)
        except Exception as exc:
            response = _error(message.get("id"), -32000, str(exc))
        if response is not None:
            _write_message(response)


if __name__ == "__main__":
    raise SystemExit(main())
