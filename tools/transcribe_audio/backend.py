#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import hashlib
import json
import sys
import uuid
from pathlib import Path
from typing import Any

try:
    from faster_whisper import WhisperModel
except Exception as exc:  # pragma: no cover
    WhisperModel = None
    IMPORT_ERROR = exc
else:
    IMPORT_ERROR = None

try:
    from opencc import OpenCC
except Exception:  # pragma: no cover
    OpenCC = None


SUPPORTED_EXTENSIONS = {
    ".mp3",
    ".wav",
    ".m4a",
    ".aac",
    ".ogg",
    ".flac",
    ".mp4",
    ".mkv",
    ".mov",
    ".webm",
    ".m4v",
}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def local_state_dir() -> Path:
    return repo_root() / "local" / "transcribe_audio"


def default_output_root() -> Path:
    return local_state_dir() / "outputs"


def suggested_output_dir(input_paths: list[Path]) -> Path:
    if not input_paths:
        return default_output_root()

    expanded = [path.expanduser().resolve() for path in input_paths]
    base_dirs = [(path if path.is_dir() else path.parent) for path in expanded]
    first_base = base_dirs[0]
    if all(base_dir == first_base for base_dir in base_dirs[1:]):
        return first_base / "output"
    return first_base / "output"


def history_path() -> Path:
    return local_state_dir() / "history.json"


def default_settings() -> dict[str, Any]:
    return {
        "outdir": str(default_output_root().resolve()),
        "model": "medium",
        "compute_type": "int8",
        "language": None,
        "device": "auto",
        "beam_size": 5,
        "vad_filter": True,
    }


def _ensure_state_dir() -> None:
    local_state_dir().mkdir(parents=True, exist_ok=True)
    default_output_root().mkdir(parents=True, exist_ok=True)


def _utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def _is_media_file(path: Path) -> bool:
    return path.is_file() and path.suffix.lower() in SUPPORTED_EXTENSIONS


def _collect_from_path(input_path: Path) -> list[Path]:
    if input_path.is_file():
        if not _is_media_file(input_path):
            raise ValueError(f"Unsupported media file: {input_path}")
        return [input_path.resolve()]

    if input_path.is_dir():
        files = sorted(p.resolve() for p in input_path.rglob("*") if _is_media_file(p))
        if not files:
            raise ValueError(f"No supported audio/video files found under: {input_path}")
        return files

    raise ValueError(f"Input path not found: {input_path}")


def collect_inputs(input_paths: list[Path]) -> list[Path]:
    if not input_paths:
        raise ValueError("At least one input path is required.")

    collected: list[Path] = []
    seen: set[Path] = set()
    for input_path in input_paths:
        for item in _collect_from_path(input_path.expanduser()):
            if item in seen:
                continue
            seen.add(item)
            collected.append(item)
    return collected


def _base_name_for(input_file: Path, used: set[str]) -> str:
    candidate = input_file.stem
    if candidate not in used:
        used.add(candidate)
        return candidate

    digest = hashlib.md5(str(input_file).encode("utf-8")).hexdigest()[:8]
    candidate = f"{input_file.stem}-{digest}"
    used.add(candidate)
    return candidate


def _progress_enabled() -> bool:
    return hasattr(sys.stderr, "isatty") and sys.stderr.isatty()


def _emit_progress(message: str) -> None:
    if _progress_enabled():
        print(message, file=sys.stderr, flush=True)


def _simplify_chinese_text(text: str) -> str:
    if not text or OpenCC is None:
        return text
    converter = getattr(_simplify_chinese_text, "_converter", None)
    if converter is None:
        converter = OpenCC("t2s")
        setattr(_simplify_chinese_text, "_converter", converter)
    return converter.convert(text)


def _segments_to_json(
    segments,
    *,
    duration_seconds: float | None = None,
    progress_prefix: str = "",
    simplify_chinese: bool = False,
) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    next_progress_percent = 10
    for index, segment in enumerate(segments):
        if duration_seconds and duration_seconds > 0:
            percent = int(min(100, max(0, (float(segment.end) / float(duration_seconds)) * 100)))
            while percent >= next_progress_percent and next_progress_percent < 100:
                _emit_progress(f"{progress_prefix}{next_progress_percent}%")
                next_progress_percent += 10
        out.append(
            {
                "id": index,
                "start": round(float(segment.start), 3),
                "end": round(float(segment.end), 3),
                "text": _simplify_chinese_text(segment.text.strip()) if simplify_chinese else segment.text.strip(),
                "avg_logprob": getattr(segment, "avg_logprob", None),
                "no_speech_prob": getattr(segment, "no_speech_prob", None),
            }
        )
    return out


def transcribe_files(
    input_files: list[Path],
    outdir: Path,
    model_name: str = "small",
    compute_type: str = "int8",
    language: str | None = None,
    device: str = "auto",
    beam_size: int = 5,
    vad_filter: bool = True,
) -> list[dict[str, Any]]:
    if WhisperModel is None:  # pragma: no cover
        raise RuntimeError(
            "faster-whisper is not available. Run tools/transcribe_audio/bootstrap.sh first."
        ) from IMPORT_ERROR

    outdir.mkdir(parents=True, exist_ok=True)
    model = WhisperModel(model_name, device=device, compute_type=compute_type)
    used_basenames: set[str] = set()
    outputs: list[dict[str, Any]] = []

    for file_index, input_file in enumerate(input_files, start=1):
        basename = _base_name_for(input_file, used_basenames)
        txt_path = outdir / f"{basename}.transcript.txt"
        segments_path = outdir / f"{basename}.segments.json"
        meta_path = outdir / f"{basename}.meta.json"
        progress_prefix = f"[{file_index}/{len(input_files)}] {input_file.name} "

        _emit_progress(f"{progress_prefix}starting")

        segments_iter, info = model.transcribe(
            str(input_file),
            language=language,
            beam_size=beam_size,
            vad_filter=vad_filter,
        )
        segments = _segments_to_json(
            segments_iter,
            duration_seconds=getattr(info, "duration", None),
            progress_prefix=progress_prefix,
            simplify_chinese=(language or getattr(info, "language", "")) == "zh",
        )
        transcript_text = "\n\n".join(seg["text"] for seg in segments if seg["text"]).strip()

        txt_path.write_text((transcript_text + "\n") if transcript_text else "", encoding="utf-8")
        segments_path.write_text(
            json.dumps(segments, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

        meta = {
            "input_file": str(input_file.resolve()),
            "created_at": _utc_now(),
            "model": model_name,
            "compute_type": compute_type,
            "requested_language": language,
            "device": device,
            "beam_size": beam_size,
            "vad_filter": vad_filter,
            "language": getattr(info, "language", None),
            "language_probability": getattr(info, "language_probability", None),
            "duration_seconds": getattr(info, "duration", None),
            "output_txt": str(txt_path.resolve()),
            "output_segments_json": str(segments_path.resolve()),
        }
        meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

        outputs.append(
            {
                "input_file": str(input_file.resolve()),
                "txt": str(txt_path.resolve()),
                "segments_json": str(segments_path.resolve()),
                "meta_json": str(meta_path.resolve()),
                "language": meta["language"],
            }
        )
        _emit_progress(
            f"{progress_prefix}done ({len(segments)} segments, language={meta['language'] or 'unknown'})"
        )

    return outputs


def read_history_data() -> dict[str, Any]:
    _ensure_state_dir()
    path = history_path()
    if not path.exists():
        data = {"version": 1, "defaults": default_settings(), "jobs": []}
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        return data

    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    data.setdefault("version", 1)
    data.setdefault("defaults", default_settings())
    data.setdefault("jobs", [])
    defaults = data["defaults"]
    if defaults.get("model") == "small":
        defaults["model"] = "medium"
    defaults.setdefault("language", None)
    return data


def write_history_data(data: dict[str, Any]) -> None:
    _ensure_state_dir()
    history_path().write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def list_jobs(limit: int | None = None) -> list[dict[str, Any]]:
    jobs = read_history_data()["jobs"]
    jobs = sorted(jobs, key=lambda item: item.get("created_at", ""), reverse=True)
    if limit is not None:
        return jobs[:limit]
    return jobs


def get_job(job_id: str) -> dict[str, Any]:
    for job in read_history_data()["jobs"]:
        if job.get("id") == job_id:
            return job
    raise ValueError(f"Job not found: {job_id}")


def _job_kind(input_paths: list[Path]) -> str:
    if len(input_paths) == 1 and input_paths[0].expanduser().is_dir():
        return "directory"
    if len(input_paths) == 1:
        return "file"
    return "multi_file"


def run_transcription_job(
    input_paths: list[Path],
    outdir: Path,
    model_name: str = "small",
    compute_type: str = "int8",
    language: str | None = None,
    device: str = "auto",
    beam_size: int = 5,
    vad_filter: bool = True,
) -> dict[str, Any]:
    requested_paths = [str(path.expanduser().resolve()) for path in input_paths]
    resolved_outdir = outdir.expanduser().resolve()
    data = read_history_data()
    data["defaults"] = {
        "outdir": str(resolved_outdir),
        "model": model_name,
        "compute_type": compute_type,
        "language": language,
        "device": device,
        "beam_size": beam_size,
        "vad_filter": vad_filter,
    }

    job = {
        "id": uuid.uuid4().hex,
        "kind": _job_kind(input_paths),
        "input_paths": requested_paths,
        "input_files": [],
        "outdir": str(resolved_outdir),
        "model": model_name,
        "compute_type": compute_type,
        "requested_language": language,
        "device": device,
        "beam_size": beam_size,
        "vad_filter": vad_filter,
        "created_at": _utc_now(),
        "finished_at": None,
        "status": "running",
        "outputs": [],
        "error": None,
    }

    try:
        files = collect_inputs(input_paths)
        job["input_files"] = [str(item) for item in files]
        outputs = transcribe_files(
            input_files=files,
            outdir=resolved_outdir,
            model_name=model_name,
            compute_type=compute_type,
            language=language,
            device=device,
            beam_size=beam_size,
            vad_filter=vad_filter,
        )
        job["outputs"] = outputs
        job["status"] = "success"
    except Exception as exc:
        job["status"] = "error"
        job["error"] = str(exc)
        raise
    finally:
        job["finished_at"] = _utc_now()
        jobs = [existing for existing in data["jobs"] if existing.get("id") != job["id"]]
        jobs.append(job)
        data["jobs"] = jobs
        write_history_data(data)

    return job


def export_state() -> dict[str, Any]:
    data = read_history_data()
    history = sorted(data["jobs"], key=lambda item: item.get("created_at", ""), reverse=True)
    return {
        "defaults": data["defaults"],
        "history": history,
        "count": len(history),
    }
