# Transcribe Audio MCP Server

Local stdio MCP server for `TranscribeAudio`.

It exposes the transcription CLI as MCP tools for local agent workflows. The SwiftUI app is not required to run the server.

## Setup

```bash
tools/transcribe_audio_mcp/bootstrap.sh
```

## Run

```bash
.tools/transcribe_audio_mcp/.venv/bin/python tools/transcribe_audio_mcp/server.py
```

## Transport

- stdio only
- no HTTP or SSE transport
- no auth layer in v1

## Exposed Tools

- `transcribe_file`
- `transcribe_directory`
- `get_result`
- `list_outputs`

## Notes

- The server shells out to `tools/transcribe_audio/transcribe_cli.py`.
- Media processing still happens through the existing Python backend and local faster-whisper setup.
- Runtime history and outputs remain under `local/transcribe_audio/`, which is gitignored.
