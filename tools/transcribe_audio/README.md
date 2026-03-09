# Transcribe Audio Tool

Python backend and CLI layer for local audio/video transcription.

## Outputs

Each successful run can produce:

- `*.transcript.txt` for plain-text transcripts
- `*.segments.json` for timestamped segments
- `*.meta.json` for run metadata

## Setup

From the repository root:

```bash
tools/transcribe_audio/bootstrap.sh
```

This installs the backend environment at `.tools/transcribe_audio/.venv/`.

## Native App

The macOS app lives in `apps/TranscribeAudioMac/` and calls the JSON CLI in this folder.

Launch it with:

```bash
cd apps/TranscribeAudioMac
./run.sh
```

## JSON CLI

Export defaults and local history:

```bash
.tools/transcribe_audio/.venv/bin/python tools/transcribe_audio/transcribe_cli.py export_state
```

Transcribe one or more files or directories:

```bash
.tools/transcribe_audio/.venv/bin/python tools/transcribe_audio/transcribe_cli.py transcribe \
  --input "/path/to/media.wav" \
  --model medium \
  --language en \
  --compute-type int8
```

Supported public commands:

- `transcribe`
- `list_outputs`
- `get_result`
- `export_state`

Notes:

- `--language` is optional and can be used to skip auto-detection.
- When run interactively, progress updates are printed to stderr while JSON stays on stdout.
- Chinese transcripts are normalized to simplified Chinese by default.

## Compatibility CLI

The legacy entrypoint is still available:

```bash
.tools/transcribe_audio/.venv/bin/python tools/transcribe_audio/transcribe.py \
  --input "/path/to/media.wav" \
  --outdir "./output"
```

If `--outdir` is omitted, outputs are written to an `output/` subfolder beside the selected input.

## Local State

Runtime history and outputs live under `local/transcribe_audio/`, which is gitignored and excluded from the public repository.
