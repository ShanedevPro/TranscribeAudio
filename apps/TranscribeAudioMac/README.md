# TranscribeAudioMac

Native macOS front-end for the local transcription backend in `tools/transcribe_audio/`.

## Requirements

- macOS 14+
- Swift 5.9+
- The Python backend bootstrapped via `tools/transcribe_audio/bootstrap.sh`

## Run

```bash
cd apps/TranscribeAudioMac
./run.sh
```

## Architecture

- SwiftUI desktop UI with `NavigationSplitView`
- Invokes `tools/transcribe_audio/transcribe_cli.py` for all backend work
- Reads and writes local state under `local/transcribe_audio/`

## Current Scope

- Transcribe workspace for new jobs
- History workspace for past runs
- File, multi-file, and directory selection
- Model and compute-type selection
- Transcript preview and output-path inspection
