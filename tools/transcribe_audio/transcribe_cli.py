#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import backend


def _write(payload: dict, exit_code: int = 0) -> int:
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return exit_code


def _ok(**payload) -> int:
    return _write({"ok": True, **payload}, exit_code=0)


def _error(message: str) -> int:
    return _write({"ok": False, "error": message}, exit_code=1)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Stateful JSON CLI for local audio/video transcription.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    transcribe = subparsers.add_parser("transcribe", help="Transcribe one or more files/directories.")
    transcribe.add_argument("--input", action="append", required=True, help="Input file or directory. Repeat for multiple files.")
    transcribe.add_argument("--outdir", help="Output directory. Defaults to an output/ subfolder beside the input file or directory.")
    transcribe.add_argument("--model", default="medium", help="Whisper model name/path (default: medium)")
    transcribe.add_argument("--compute-type", default="int8", help="faster-whisper compute type (default: int8)")
    transcribe.add_argument("--language", help="Optional language code hint, for example zh or en.")
    transcribe.add_argument(
        "--device",
        default="auto",
        choices=["auto", "cpu", "cuda"],
        help="Inference device (default: auto)",
    )
    transcribe.add_argument("--beam-size", type=int, default=5, help="Beam size (default: 5)")
    transcribe.add_argument("--no-vad-filter", action="store_true", help="Disable VAD filter (enabled by default)")

    list_outputs = subparsers.add_parser("list_outputs", help="List recorded transcription jobs.")
    list_outputs.add_argument("--limit", type=int, default=50, help="Max jobs to return (default: 50)")

    get_result = subparsers.add_parser("get_result", help="Get one transcription job by job id.")
    get_result.add_argument("--job-id", required=True)

    subparsers.add_parser("export_state", help="Export defaults and history for native clients.")
    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        if args.command == "transcribe":
            input_paths = [Path(item) for item in args.input]
            outdir = Path(args.outdir).expanduser() if args.outdir else backend.suggested_output_dir(input_paths)
            job = backend.run_transcription_job(
                input_paths=input_paths,
                outdir=outdir,
                model_name=args.model,
                compute_type=args.compute_type,
                language=args.language,
                device=args.device,
                beam_size=args.beam_size,
                vad_filter=not args.no_vad_filter,
            )
            return _ok(job=job)

        if args.command == "list_outputs":
            jobs = backend.list_jobs(limit=args.limit)
            return _ok(jobs=jobs, count=len(jobs))

        if args.command == "get_result":
            job = backend.get_job(args.job_id)
            return _ok(job=job)

        if args.command == "export_state":
            snapshot = backend.export_state()
            return _ok(**snapshot)

        return _error(f"Unknown command: {args.command}")
    except Exception as exc:
        return _error(str(exc))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
