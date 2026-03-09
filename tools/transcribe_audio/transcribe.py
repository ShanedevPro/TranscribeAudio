#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import backend


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Transcribe local audio/video files into TXT and JSON segments using faster-whisper."
    )
    parser.add_argument("--input", required=True, help="Input file or directory")
    parser.add_argument("--outdir", required=True, help="Output directory")
    parser.add_argument("--model", default="medium", help="Whisper model name/path (default: medium)")
    parser.add_argument("--compute-type", default="int8", help="faster-whisper compute type (default: int8)")
    parser.add_argument("--language", help="Optional language code hint, for example zh or en.")
    parser.add_argument(
        "--device",
        default="auto",
        choices=["auto", "cpu", "cuda"],
        help="Inference device (default: auto)",
    )
    parser.add_argument("--beam-size", type=int, default=5, help="Beam size (default: 5)")
    parser.add_argument(
        "--no-vad-filter",
        action="store_true",
        help="Disable VAD filter (enabled by default)",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    try:
        job = backend.run_transcription_job(
            input_paths=[Path(args.input)],
            outdir=Path(args.outdir).expanduser(),
            model_name=args.model,
            compute_type=args.compute_type,
            language=args.language,
            device=args.device,
            beam_size=args.beam_size,
            vad_filter=not args.no_vad_filter,
        )
        print(json.dumps({"count": len(job["outputs"]), "outputs": job["outputs"]}, ensure_ascii=False, indent=2))
        return 0
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
