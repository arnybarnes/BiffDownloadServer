import json
import os
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from uuid import uuid4


ROOT = Path(__file__).parent
WEB_DIR = ROOT / "web"
CONFIG_PATH = ROOT / "config.local.json"
START_LOCAL_SCRIPT = ROOT / "start-local.ps1"
DOWNLOAD_LOG_PATH = ROOT / "download-debug.log"
SEARCH_RESULT_CACHE: dict[str, str] = {}
DEFAULT_DOWNLOAD_ROOT = Path(r"C:\Users\arnyb\Downloads")
TEMP_DOWNLOAD_ROOT = Path(r"C:\Users\arnyb\Downloads\temp")
VIDEO_EXTENSIONS = {".mkv", ".mp4"}


@dataclass
class ProviderConfig:
    provider: str
    base_url: str | None
    api_key: str | None
    username: str | None = None
    password: str | None = None


@dataclass
class DownloaderConfig:
    downloader: str
    rpc_url: str | None
    secret: str | None
    download_dir: str | None = None


@dataclass
class DownloadRequestState:
    target_directory: str | None
    requested_file_name: str | None
    staging_directory: str | None = None
    resolved_file_name: str | None = None
    selection_state: str = "pending"
    selection_message: str | None = None
    selected_file_index: str | None = None
    selected_file_name: str | None = None
    selected_file_path: str | None = None
    selected_file_bytes: int | None = None
    applied_gid: str | None = None
    finalization_state: str = "not_requested"
    finalization_message: str | None = None
    finalized_path: str | None = None
    finalization_mode: str | None = None
    finalization_source_path: str | None = None
    finalization_destination_path: str | None = None
    finalization_total_bytes: int | None = None
    finalization_completed_bytes: int | None = None
    cleanup_state: str = "not_requested"
    cleanup_message: str | None = None
    cleanup_deleted_paths: list[str] | None = None


DOWNLOAD_REQUESTS: dict[str, DownloadRequestState] = {}
DOWNLOAD_STATUS_KEYS = [
    "gid",
    "status",
    "totalLength",
    "completedLength",
    "downloadSpeed",
    "dir",
    "files",
    "infoHash",
    "followedBy",
    "following",
    "bittorrent",
]
DOWNLOAD_MONITOR_INTERVAL_SECONDS = 2.0
DOWNLOAD_LOG_LOCK = threading.Lock()


def format_log_value(value: Any) -> str:
    if isinstance(value, Path):
        value = str(value)
    elif isinstance(value, set):
        value = sorted(str(item) for item in value)
    elif isinstance(value, tuple):
        value = [str(item) for item in value]
    elif isinstance(value, list):
        value = [str(item) if isinstance(item, Path) else item for item in value]
    elif isinstance(value, dict):
        value = {
            str(key): str(item) if isinstance(item, Path) else item
            for key, item in value.items()
        }

    try:
        return json.dumps(value, ensure_ascii=True, default=str)
    except TypeError:
        return json.dumps(str(value), ensure_ascii=True)


def log_download_event(event: str, **fields: Any) -> None:
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    details = " ".join(
        f"{key}={format_log_value(value)}"
        for key, value in fields.items()
    )
    line = f"[{timestamp}] download {event}"
    if details:
        line = f"{line} {details}"

    print(line, flush=True)

    try:
        with DOWNLOAD_LOG_LOCK:
            with DOWNLOAD_LOG_PATH.open("a", encoding="utf-8") as handle:
                handle.write(line)
                handle.write("\n")
    except OSError as exc:
        print(
            f"[{timestamp}] download log_write_failed path={format_log_value(str(DOWNLOAD_LOG_PATH))} error={format_log_value(str(exc))}",
            flush=True,
        )


def get_download_root() -> Path:
    config = get_downloader_config()
    configured_root = (config.download_dir or "").strip()
    if configured_root:
        return Path(configured_root).expanduser()
    return DEFAULT_DOWNLOAD_ROOT


def ensure_temp_download_root() -> Path:
    TEMP_DOWNLOAD_ROOT.mkdir(parents=True, exist_ok=True)
    return TEMP_DOWNLOAD_ROOT


def build_download_folder_payload() -> dict[str, Any]:
    root = get_download_root()
    folders: list[dict[str, Any]] = [
        {
            "key": "",
            "name": "Default",
            "relativePath": "",
            "absolutePath": str(root),
            "isDefault": True,
        }
    ]

    if root.exists() and root.is_dir():
        for child in sorted(root.iterdir(), key=lambda path: path.name.lower()):
            if child.is_dir():
                folders.append(
                    {
                        "key": child.name,
                        "name": child.name,
                        "relativePath": child.name,
                        "absolutePath": str(child),
                        "isDefault": False,
                    }
                )

    return {
        "status": "ok",
        "root": str(root),
        "count": len(folders),
        "folders": folders,
    }


def resolve_download_dir(folder: str | None) -> Path:
    root = get_download_root().resolve()
    folder_name = (folder or "").strip()
    if not folder_name:
        return root

    requested = Path(folder_name)
    if requested.is_absolute() or len(requested.parts) != 1 or requested.parts[0] in {"", ".", ".."}:
        raise ValueError("Folder must be a direct child of the download root.")

    candidate = (root / requested.parts[0]).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise ValueError("Folder must stay inside the download root.") from exc

    if not candidate.exists() or not candidate.is_dir():
        raise ValueError("Selected folder does not exist.")

    return candidate


def validate_output_name(file_name: str | None) -> str | None:
    value = (file_name or "").strip()
    if not value:
        return None

    if Path(value).name != value:
        raise ValueError("File name must not include a path.")

    invalid_chars = '<>:"/\\|?*'
    if any(char in invalid_chars for char in value):
        raise ValueError("File name contains invalid Windows path characters.")
    if any(ord(char) < 32 for char in value):
        raise ValueError("File name contains unsupported control characters.")

    return value


def resolve_output_name(file_name: str | None, source_name: str | None = None) -> str | None:
    requested_name = (file_name or "").strip()
    if not requested_name:
        return None

    if Path(requested_name).suffix:
        return requested_name

    source_suffix = Path(source_name or "").suffix.lower()
    if source_suffix in VIDEO_EXTENSIONS:
        return f"{requested_name}{source_suffix}"
    return f"{requested_name}.mkv"


def is_torrent_source(uri: str) -> bool:
    normalized = uri.strip().lower()
    if normalized.startswith("magnet:?"):
        return True
    parsed = urllib.parse.urlparse(normalized)
    return parsed.path.endswith(".torrent")


def parse_aria2_file_entry(file_entry: dict[str, Any]) -> dict[str, Any]:
    path = file_entry.get("path")
    return {
        "index": str(file_entry.get("index") or ""),
        "path": path,
        "name": Path(path).name if path else None,
        "lengthBytes": int(file_entry.get("length", "0")),
        "completedBytes": int(file_entry.get("completedLength", "0")),
        "selected": str(file_entry.get("selected", "true")).lower() == "true",
    }


def choose_largest_video_file(file_entries: list[dict[str, Any]]) -> dict[str, Any] | None:
    candidates = [
        file_entry
        for file_entry in file_entries
        if file_entry.get("path") and Path(file_entry["path"]).suffix.lower() in VIDEO_EXTENSIONS
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda item: (item["lengthBytes"], item["name"] or ""))


def build_selection_payload(request: DownloadRequestState | None) -> dict[str, Any]:
    if request is None:
        return {
            "state": "not_requested",
            "message": None,
            "selectedFile": None,
            "renameTarget": None,
        }

    selected_file = None
    if request.selected_file_index:
        selected_file = {
            "index": request.selected_file_index,
            "name": request.selected_file_name,
            "path": request.selected_file_path,
            "sizeBytes": request.selected_file_bytes,
        }

    rename_target = None
    if request.requested_file_name and request.selected_file_index:
        rename_target = {
            "requestedName": request.requested_file_name,
            "fileName": request.resolved_file_name or request.requested_file_name,
            "appliesToIndex": request.selected_file_index,
        }

    return {
        "state": request.selection_state,
        "message": request.selection_message,
        "selectedFile": selected_file,
        "renameTarget": rename_target,
    }


def build_finalization_payload(request: DownloadRequestState | None) -> dict[str, Any] | None:
    if request is None:
        return None

    return {
        "state": request.finalization_state,
        "message": request.finalization_message,
        "mode": request.finalization_mode,
        "stagingDirectory": request.staging_directory,
        "targetDirectory": request.target_directory,
        "sourcePath": request.finalization_source_path,
        "destinationPath": request.finalization_destination_path,
        "totalBytes": request.finalization_total_bytes,
        "completedBytes": request.finalization_completed_bytes,
        "finalPath": request.finalized_path,
    }


def build_cleanup_payload(request: DownloadRequestState | None) -> dict[str, Any] | None:
    if request is None:
        return None

    return {
        "state": request.cleanup_state,
        "message": request.cleanup_message,
        "deletedPaths": request.cleanup_deleted_paths,
    }


def build_available_destination_path(path: Path) -> Path:
    if not path.exists():
        return path

    stem = path.stem if path.suffix else path.name
    suffix = path.suffix
    parent = path.parent
    counter = 2

    while True:
        candidate_name = f"{stem} ({counter}){suffix}"
        candidate = parent / candidate_name
        if not candidate.exists():
            return candidate
        counter += 1


def download_has_all_bytes(result: dict[str, Any]) -> bool:
    try:
        total_bytes = int(result.get("totalLength", "0"))
        completed_bytes = int(result.get("completedLength", "0"))
    except (TypeError, ValueError):
        return False

    return total_bytes > 0 and completed_bytes >= total_bytes


def choose_finalization_source(
    request: DownloadRequestState,
    file_entries: list[dict[str, Any]],
    primary_path: str | None,
) -> Path | None:
    existing_paths: list[Path] = []
    raw_paths: list[str] = []
    for entry in file_entries:
        raw_path = entry.get("path")
        if not raw_path:
            continue
        raw_paths.append(str(raw_path))
        candidate = Path(raw_path)
        if candidate.exists():
            existing_paths.append(candidate)

    log_download_event(
        "finalization_source_scan",
        requested_name=request.requested_file_name,
        selected_index=request.selected_file_index,
        primary_path=primary_path,
        staging_directory=request.staging_directory,
        raw_paths=raw_paths,
        existing_paths=[str(path) for path in existing_paths],
    )

    if request.selected_file_index:
        for entry in file_entries:
            if entry.get("index") != request.selected_file_index:
                continue
            raw_path = entry.get("path")
            if raw_path:
                candidate = Path(raw_path)
                if candidate.exists():
                    log_download_event(
                        "finalization_source_selected_index",
                        selected_index=request.selected_file_index,
                        source_path=str(candidate),
                    )
                    return candidate

    selected_path = (request.selected_file_path or "").strip()
    if selected_path:
        candidate = Path(selected_path)
        if candidate.exists():
            log_download_event(
                "finalization_source_selected_path",
                source_path=str(candidate),
            )
            return candidate

    selected_name = (request.selected_file_name or "").strip().lower()
    if selected_name:
        name_matches = [
            path for path in existing_paths
            if path.name.lower() == selected_name
        ]
        if len(name_matches) == 1:
            log_download_event(
                "finalization_source_selected_name",
                source_path=str(name_matches[0]),
            )
            return name_matches[0]

    selected_video = choose_largest_video_file(file_entries)
    if selected_video:
        selected_video_path = selected_video.get("path")
        if selected_video_path:
            candidate = Path(selected_video_path)
            if candidate.exists():
                log_download_event(
                    "finalization_source_largest_video",
                    source_path=str(candidate),
                    selected_index=selected_video.get("index"),
                )
                return candidate

    if not existing_paths and primary_path:
        candidate = Path(primary_path)
        if candidate.exists():
            log_download_event(
                "finalization_source_primary_path_without_existing_paths",
                source_path=str(candidate),
            )
            return candidate
        log_download_event(
            "finalization_source_primary_path_missing",
            primary_path=primary_path,
        )
        return None

    video_paths = [
        path for path in existing_paths
        if path.suffix.lower() in VIDEO_EXTENSIONS
    ]
    if len(video_paths) == 1:
        log_download_event(
            "finalization_source_single_video",
            source_path=str(video_paths[0]),
        )
        return video_paths[0]

    if len(existing_paths) == 1:
        log_download_event(
            "finalization_source_single_existing_path",
            source_path=str(existing_paths[0]),
        )
        return existing_paths[0]

    log_download_event(
        "finalization_source_unresolved",
        staging_directory=request.staging_directory,
        existing_paths=[str(path) for path in existing_paths],
        primary_path=primary_path,
    )
    return None


def choose_cleanup_targets(
    request: DownloadRequestState,
    file_entries: list[dict[str, Any]],
    primary_path: str | None,
) -> list[Path]:
    staging_dir_value = (request.staging_directory or "").strip()
    if not staging_dir_value:
        log_download_event("cleanup_targets_missing_staging_directory")
        return []

    staging_dir = Path(staging_dir_value)
    try:
        staging_root = staging_dir.resolve()
    except OSError:
        staging_root = staging_dir

    candidate_paths: list[Path] = []
    raw_paths: list[str] = []
    for entry in file_entries:
        raw_path = entry.get("path")
        if not raw_path:
            continue
        raw_paths.append(str(raw_path))
        candidate = Path(raw_path)
        if candidate.exists():
            candidate_paths.append(candidate)

    if not candidate_paths and primary_path:
        primary_candidate = Path(primary_path)
        if primary_candidate.exists():
            candidate_paths.append(primary_candidate)

    unique_targets: list[Path] = []
    seen_targets: set[Path] = set()

    for candidate in candidate_paths:
        try:
            relative = candidate.resolve().relative_to(staging_root)
        except ValueError:
            continue
        except OSError:
            continue

        if not relative.parts:
            continue

        top_level = staging_dir / relative.parts[0]
        if not top_level.exists():
            continue

        try:
            resolved_top_level = top_level.resolve()
        except OSError:
            resolved_top_level = top_level

        if resolved_top_level in seen_targets:
            continue
        seen_targets.add(resolved_top_level)
        unique_targets.append(top_level)

    log_download_event(
        "cleanup_targets_resolved",
        staging_directory=staging_dir_value,
        raw_paths=raw_paths,
        targets=[str(path) for path in unique_targets],
    )
    return unique_targets


def best_effort_remove_aria2_download(
    root_result: dict[str, Any],
    effective_result: dict[str, Any],
    followed_by: list[str],
) -> None:
    active_states = {"active", "waiting", "paused"}
    gids_to_stop: list[str] = []

    root_gid = str(root_result.get("gid") or "")
    effective_gid = str(effective_result.get("gid") or "")

    if root_gid and root_result.get("status") in active_states:
        gids_to_stop.append(root_gid)
    if effective_gid and effective_result.get("status") in active_states and effective_gid not in gids_to_stop:
        gids_to_stop.append(effective_gid)

    for gid in gids_to_stop:
        try:
            aria2_rpc_call("aria2.forceRemove", [gid])
            log_download_event("cleanup_force_removed_gid", gid=gid)
        except (urllib.error.URLError, RuntimeError) as exc:
            log_download_event("cleanup_force_remove_failed", gid=gid, error=str(exc))

    if gids_to_stop:
        time.sleep(0.25)

    gids_to_forget: list[str] = []
    for raw_gid in [root_gid, effective_gid, *followed_by]:
        gid = str(raw_gid or "").strip()
        if gid and gid not in gids_to_forget:
            gids_to_forget.append(gid)

    for gid in gids_to_forget:
        try:
            aria2_rpc_call("aria2.removeDownloadResult", [gid])
            log_download_event("cleanup_removed_download_result", gid=gid)
        except (urllib.error.URLError, RuntimeError) as exc:
            log_download_event("cleanup_remove_download_result_failed", gid=gid, error=str(exc))


def delete_cleanup_targets(targets: list[Path]) -> list[str]:
    deleted_paths: list[str] = []
    for target in targets:
        if not target.exists():
            continue

        if target.is_dir():
            shutil.rmtree(target)
        else:
            target.unlink()
        deleted_paths.append(str(target))

    return deleted_paths


def copy_finalized_file(
    request: DownloadRequestState,
    gid: str,
    source_path: Path,
    destination: Path,
) -> None:
    partial_destination = destination.with_name(f".{destination.name}.partial-{uuid4().hex}")
    total_bytes = request.finalization_total_bytes or 0
    copied_bytes = 0
    last_logged_step = -1

    request.finalization_state = "in_progress"
    request.finalization_mode = "copy"
    request.finalization_message = "Copying selected video from temp to the destination folder."
    request.finalization_source_path = str(source_path)
    request.finalization_destination_path = str(destination)
    request.finalization_completed_bytes = 0

    log_download_event(
        "finalization_copy_started",
        gid=gid,
        source_path=str(source_path),
        destination=str(destination),
        total_bytes=total_bytes,
    )

    try:
        with source_path.open("rb") as source_handle, partial_destination.open("wb") as destination_handle:
            while True:
                chunk = source_handle.read(4 * 1024 * 1024)
                if not chunk:
                    break

                destination_handle.write(chunk)
                copied_bytes += len(chunk)
                request.finalization_completed_bytes = copied_bytes

                if total_bytes > 0:
                    step = min(10, (copied_bytes * 10) // total_bytes)
                else:
                    step = 10
                if step != last_logged_step:
                    last_logged_step = step
                    log_download_event(
                        "finalization_progress",
                        gid=gid,
                        source_path=str(source_path),
                        destination=str(destination),
                        completed_bytes=copied_bytes,
                        total_bytes=total_bytes,
                    )

            destination_handle.flush()
            os.fsync(destination_handle.fileno())

        os.replace(partial_destination, destination)
        request.finalization_state = "completed"
        request.finalization_mode = "copy"
        request.finalized_path = str(destination)
        request.finalization_completed_bytes = total_bytes
        request.finalization_message = "Selected video copied from temp to the destination folder."
        log_download_event(
            "finalization_completed",
            gid=gid,
            source_path=str(source_path),
            destination=str(destination),
            mode=request.finalization_mode,
            message=request.finalization_message,
        )
    except (OSError, shutil.Error, ValueError) as exc:
        request.finalization_state = "error"
        request.finalization_message = f"Could not copy selected video: {exc}"
        request.finalized_path = None
        try:
            if partial_destination.exists():
                partial_destination.unlink()
        except OSError:
            pass
        log_download_event(
            "finalization_exception",
            gid=gid,
            source_path=str(source_path),
            target_directory=request.target_directory,
            error=str(exc),
        )


def request_download_finalization(
    request: DownloadRequestState,
    effective_result: dict[str, Any],
    file_entries: list[dict[str, Any]],
    primary_path: str | None,
) -> str:
    if request.finalization_state == "completed":
        request.finalization_message = request.finalization_message or "Selected video already copied to the destination folder."
        log_download_event(
            "finalization_skipped_already_completed",
            gid=effective_result.get("gid"),
            final_path=request.finalized_path,
            message=request.finalization_message,
        )
        return "completed"

    if request.finalization_state in {"queued", "in_progress"}:
        request.finalization_message = request.finalization_message or "Selected video is already being copied."
        log_download_event(
            "finalization_skipped_already_running",
            gid=effective_result.get("gid"),
            state=request.finalization_state,
            destination=request.finalization_destination_path,
        )
        return "in_progress"

    target_dir = Path(request.target_directory or get_download_root())
    log_download_event(
        "finalization_begin",
        gid=effective_result.get("gid"),
        status=effective_result.get("status"),
        target_directory=str(target_dir),
        staging_directory=request.staging_directory,
        requested_name=request.requested_file_name,
        resolved_name=request.resolved_file_name,
        primary_path=primary_path,
    )

    if not download_has_all_bytes(effective_result):
        request.finalization_state = "not_requested"
        request.finalization_message = "Download has not reached 100% yet."
        log_download_event(
            "finalization_rejected_not_ready",
            gid=effective_result.get("gid"),
            completed_bytes=effective_result.get("completedLength"),
            total_bytes=effective_result.get("totalLength"),
        )
        raise ValueError(request.finalization_message)

    source_path = choose_finalization_source(request, file_entries, primary_path)
    if source_path is None:
        request.finalization_state = "error"
        request.finalization_message = "Could not locate the selected video in the temp folder."
        log_download_event(
            "finalization_failed_missing_source",
            gid=effective_result.get("gid"),
            target_directory=str(target_dir),
            staging_directory=request.staging_directory,
            primary_path=primary_path,
        )
        raise FileNotFoundError(request.finalization_message)

    resolved_name = request.resolved_file_name or resolve_output_name(
        request.requested_file_name,
        source_path.name,
    ) or source_path.name

    try:
        target_dir.mkdir(parents=True, exist_ok=True)
        total_bytes = source_path.stat().st_size
    except OSError as exc:
        request.finalization_state = "error"
        request.finalization_message = f"Could not prepare destination folder: {exc}"
        log_download_event(
            "finalization_prepare_failed",
            gid=effective_result.get("gid"),
            target_directory=str(target_dir),
            source_path=str(source_path),
            error=str(exc),
        )
        raise

    destination = build_available_destination_path(target_dir / resolved_name)
    request.finalization_state = "queued"
    request.finalization_mode = "copy"
    request.finalization_message = "Queued selected video for copy into the destination folder."
    request.finalized_path = None
    request.finalization_source_path = str(source_path)
    request.finalization_destination_path = str(destination)
    request.finalization_total_bytes = total_bytes
    request.finalization_completed_bytes = 0

    threading.Thread(
        target=copy_finalized_file,
        args=(request, str(effective_result.get("gid") or ""), source_path, destination),
        daemon=True,
    ).start()

    log_download_event(
        "finalization_copy_enqueued",
        gid=effective_result.get("gid"),
        source_path=str(source_path),
        destination=str(destination),
        total_bytes=total_bytes,
    )
    return "started"


def request_download_cleanup(
    root_result: dict[str, Any],
    effective_result: dict[str, Any],
    followed_by: list[str],
    request: DownloadRequestState,
    file_entries: list[dict[str, Any]],
    primary_path: str | None,
) -> str:
    if request.finalization_state != "completed":
        request.cleanup_state = "error"
        request.cleanup_message = "Copy the selected video before deleting temp files."
        log_download_event(
            "cleanup_rejected_finalization_incomplete",
            gid=effective_result.get("gid"),
            finalization_state=request.finalization_state,
        )
        return "error"

    if request.cleanup_state == "completed":
        request.cleanup_message = request.cleanup_message or "Temp torrent files already deleted."
        log_download_event(
            "cleanup_skipped_already_completed",
            gid=effective_result.get("gid"),
            deleted_paths=request.cleanup_deleted_paths or [],
        )
        return "completed"

    if request.cleanup_state == "in_progress":
        request.cleanup_message = request.cleanup_message or "Temp torrent files are already being deleted."
        log_download_event(
            "cleanup_skipped_already_running",
            gid=effective_result.get("gid"),
        )
        return "in_progress"

    request.cleanup_state = "in_progress"
    request.cleanup_message = "Deleting torrent data from the temp folder."
    request.cleanup_deleted_paths = None

    targets = choose_cleanup_targets(request, file_entries, primary_path)
    if not targets:
        request.cleanup_state = "error"
        request.cleanup_message = "Could not find temp files for this download."
        log_download_event(
            "cleanup_targets_missing",
            gid=effective_result.get("gid"),
            staging_directory=request.staging_directory,
        )
        return "error"

    log_download_event(
        "cleanup_begin",
        gid=effective_result.get("gid"),
        targets=[str(path) for path in targets],
    )

    try:
        best_effort_remove_aria2_download(root_result, effective_result, followed_by)
        deleted_paths = delete_cleanup_targets(targets)
    except (urllib.error.URLError, RuntimeError, OSError, shutil.Error) as exc:
        request.cleanup_state = "error"
        request.cleanup_message = f"Could not delete temp files: {exc}"
        log_download_event(
            "cleanup_exception",
            gid=effective_result.get("gid"),
            error=str(exc),
            targets=[str(path) for path in targets],
        )
        return "error"

    request.cleanup_state = "completed"
    request.cleanup_deleted_paths = deleted_paths
    if deleted_paths:
        request.cleanup_message = "Temp torrent files deleted."
    else:
        request.cleanup_message = "No temp files remained for this download."

    log_download_event(
        "cleanup_completed",
        gid=effective_result.get("gid"),
        deleted_paths=deleted_paths,
        message=request.cleanup_message,
    )
    return "completed"


def load_local_config() -> dict[str, Any]:
    if not CONFIG_PATH.exists():
        return {}
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def get_service_config(service_name: str) -> tuple[str, int]:
    local_config = load_local_config()
    services = local_config.get("services", {})
    service_config = services.get(service_name, {})
    env_prefix = service_name.upper()
    host = os.getenv(f"{env_prefix}_HOST") or service_config.get("host") or "127.0.0.1"
    port_value = os.getenv(f"{env_prefix}_PORT") or service_config.get("port")
    default_port = 8789 if service_name == "web" else 8790
    return host, int(port_value or default_port)


def get_provider_config() -> ProviderConfig:
    local_config = load_local_config()
    provider_settings = local_config.get("providers", {})
    provider = (os.getenv("TORRENT_PROVIDER") or local_config.get("provider") or "mock").strip().lower() or "mock"

    if provider == "prowlarr":
        prowlarr_config = provider_settings.get("prowlarr", {})
        return ProviderConfig(
            provider=provider,
            base_url=os.getenv("PROWLARR_URL") or prowlarr_config.get("base_url"),
            api_key=os.getenv("PROWLARR_API_KEY") or prowlarr_config.get("api_key"),
            username=os.getenv("PROWLARR_USERNAME") or prowlarr_config.get("username"),
            password=os.getenv("PROWLARR_PASSWORD") or prowlarr_config.get("password"),
        )

    if provider == "jackett":
        jackett_config = provider_settings.get("jackett", {})
        return ProviderConfig(
            provider=provider,
            base_url=os.getenv("JACKETT_URL") or jackett_config.get("base_url"),
            api_key=os.getenv("JACKETT_API_KEY") or jackett_config.get("api_key"),
            username=os.getenv("JACKETT_USERNAME") or jackett_config.get("username"),
            password=os.getenv("JACKETT_PASSWORD") or jackett_config.get("password"),
        )

    return ProviderConfig(provider="mock", base_url=None, api_key=None)


def get_downloader_config() -> DownloaderConfig:
    local_config = load_local_config()
    downloader_settings = local_config.get("downloaders", {})
    downloader = (os.getenv("TORRENT_DOWNLOADER") or local_config.get("downloader") or "none").strip().lower() or "none"

    if downloader == "aria2":
        aria2_config = downloader_settings.get("aria2", {})
        return DownloaderConfig(
            downloader=downloader,
            rpc_url=os.getenv("ARIA2_RPC_URL") or aria2_config.get("rpc_url"),
            secret=os.getenv("ARIA2_RPC_SECRET") or aria2_config.get("secret"),
            download_dir=os.getenv("ARIA2_DOWNLOAD_DIR") or aria2_config.get("download_dir"),
        )

    return DownloaderConfig(downloader="none", rpc_url=None, secret=None)


def json_response(handler: BaseHTTPRequestHandler, status: int, payload: dict[str, Any]) -> None:
    body = json.dumps(payload, indent=2).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    handler.send_header("Access-Control-Allow-Headers", "Content-Type")
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)


def normalize_result(item: dict[str, Any]) -> dict[str, Any]:
    indexer = item.get("indexer") or item.get("indexerName") or "Unknown"
    title = item.get("title") or item.get("sortTitle") or "Untitled"
    link = item.get("downloadUrl") or item.get("guid") or item.get("infoUrl") or item.get("magnetUrl")
    return {
        "title": title,
        "indexer": indexer,
        "size": item.get("size"),
        "seeders": item.get("seeders"),
        "leechers": item.get("leechers"),
        "publishDate": item.get("publishDate"),
        "link": link,
        "magnetUrl": item.get("magnetUrl"),
        "protocol": item.get("protocol"),
    }


def resolve_download_source(item: dict[str, Any]) -> str | None:
    link = item.get("link")
    magnet_url = item.get("magnetUrl")

    if isinstance(link, str) and link.startswith("magnet:?"):
        return link
    if isinstance(magnet_url, str) and magnet_url:
        return magnet_url
    if isinstance(link, str) and link:
        return link
    return None


def fetch_json(url: str, headers: dict[str, str]) -> Any:
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=15) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return json.loads(response.read().decode(charset))


def get_provider_reachability(config: ProviderConfig) -> dict[str, Any]:
    if config.provider == "mock":
        return {
            "name": config.provider,
            "configured": False,
            "reachable": False,
            "baseUrl": None,
            "message": "Mock mode is active.",
        }

    configured = bool(config.base_url and config.api_key)
    if not configured:
        return {
            "name": config.provider,
            "configured": False,
            "reachable": False,
            "baseUrl": config.base_url,
            "message": f"{config.provider.title()} is not fully configured.",
        }

    parsed = urllib.parse.urlparse(config.base_url or "")
    host = parsed.hostname
    if not host:
        return {
            "name": config.provider,
            "configured": True,
            "reachable": False,
            "baseUrl": config.base_url,
            "message": f"Invalid {config.provider.title()} URL: {config.base_url}",
        }

    port = parsed.port
    if port is None:
        port = 443 if parsed.scheme == "https" else 80

    try:
        with socket.create_connection((host, port), timeout=3):
            return {
                "name": config.provider,
                "configured": True,
                "reachable": True,
                "baseUrl": config.base_url,
                "host": host,
                "port": port,
                "message": f"{config.provider.title()} is reachable.",
            }
    except OSError as exc:
        return {
            "name": config.provider,
            "configured": True,
            "reachable": False,
            "baseUrl": config.base_url,
            "host": host,
            "port": port,
            "message": f"Could not reach {config.provider.title()} at {config.base_url}: {exc}",
        }


def post_json(url: str, payload: dict[str, Any]) -> Any:
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return json.loads(response.read().decode(charset))


def search_prowlarr(query: str, config: ProviderConfig) -> dict[str, Any]:
    if not config.base_url or not config.api_key:
        return {
            "provider": "prowlarr",
            "configured": False,
            "results": [],
            "message": "Set PROWLARR_URL and PROWLARR_API_KEY to enable live search.",
        }

    base_url = config.base_url.rstrip("/")
    params = urllib.parse.urlencode({"query": query, "type": "search", "limit": "25"})
    url = f"{base_url}/api/v1/search?{params}"
    headers = {"X-Api-Key": config.api_key, "Accept": "application/json"}

    try:
        payload = fetch_json(url, headers)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        return {
            "provider": "prowlarr",
            "configured": True,
            "results": [],
            "message": f"Prowlarr returned HTTP {exc.code}.",
            "detail": detail[:500],
        }
    except urllib.error.URLError as exc:
        return {
            "provider": "prowlarr",
            "configured": True,
            "results": [],
            "message": f"Could not reach Prowlarr at {config.base_url}: {exc.reason}",
        }

    items = payload if isinstance(payload, list) else payload.get("records", [])
    return {
        "provider": "prowlarr",
        "configured": True,
        "results": [normalize_result(item) for item in items],
        "message": f"Found {len(items)} result(s) from Prowlarr.",
    }


def search_jackett(query: str, config: ProviderConfig) -> dict[str, Any]:
    if not config.base_url or not config.api_key:
        return {
            "provider": "jackett",
            "configured": False,
            "results": [],
            "message": "Set JACKETT_URL and JACKETT_API_KEY to enable Jackett support.",
        }

    return {
        "provider": "jackett",
        "configured": True,
        "results": [],
        "message": "Jackett wiring is not implemented yet. The API shape is ready for it.",
    }


def search_mock(query: str) -> dict[str, Any]:
    return {
        "provider": "mock",
        "configured": False,
        "results": [
            {
                "title": f"{query} Example Release 1080p",
                "indexer": "MockIndexer",
                "size": 1610612736,
                "seeders": 84,
                "leechers": 4,
                "publishDate": "2026-03-28T12:00:00Z",
                "link": "magnet:?xt=urn:btih:EXAMPLE1",
                "magnetUrl": "magnet:?xt=urn:btih:EXAMPLE1",
                "protocol": "torrent",
            },
            {
                "title": f"{query} Example Release 4K",
                "indexer": "MockIndexer",
                "size": 12884901888,
                "seeders": 25,
                "leechers": 1,
                "publishDate": "2026-03-27T19:30:00Z",
                "link": "magnet:?xt=urn:btih:EXAMPLE2",
                "magnetUrl": "magnet:?xt=urn:btih:EXAMPLE2",
                "protocol": "torrent",
            },
        ],
        "message": "Mock mode is active. Configure Prowlarr when you're ready for live results.",
    }


def perform_search(query: str) -> dict[str, Any]:
    config = get_provider_config()
    if config.provider == "prowlarr":
        return search_prowlarr(query, config)
    if config.provider == "jackett":
        return search_jackett(query, config)
    return search_mock(query)


def aria2_rpc_call(method: str, params: list[Any]) -> Any:
    config = get_downloader_config()
    if config.downloader != "aria2" or not config.rpc_url:
        raise RuntimeError("aria2 is not configured")

    rpc_params = list(params)
    if config.secret:
        rpc_params.insert(0, f"token:{config.secret}")

    payload = {
        "jsonrpc": "2.0",
        "id": "torrentsearch",
        "method": method,
        "params": rpc_params,
    }
    return post_json(config.rpc_url, payload)


def get_aria2_status_payload(gid: str, keys: list[str]) -> dict[str, Any]:
    payload = aria2_rpc_call("aria2.tellStatus", [gid, keys])
    if "error" in payload:
        raise RuntimeError(payload["error"].get("message", "aria2 RPC error"))
    return payload.get("result", {})


def resolve_download_request_state(
    gid: str,
) -> tuple[dict[str, Any], dict[str, Any], list[str], DownloadRequestState | None, list[dict[str, Any]], str | None]:
    root_result = get_aria2_status_payload(gid, DOWNLOAD_STATUS_KEYS)

    effective_result = root_result
    followed_by = root_result.get("followedBy") or []
    if followed_by:
        try:
            effective_result = get_aria2_status_payload(followed_by[0], DOWNLOAD_STATUS_KEYS)
        except (urllib.error.URLError, RuntimeError):
            pass

    requested_gid = str(root_result.get("gid") or gid)
    effective_result, request = apply_download_selection(requested_gid, effective_result, DOWNLOAD_STATUS_KEYS)

    files = effective_result.get("files", [])
    primary_path = files[0].get("path") if files else None
    parsed_files = [parse_aria2_file_entry(item) for item in files]
    if request is not None:
        log_download_event(
            "status_observed",
            requested_gid=requested_gid,
            effective_gid=effective_result.get("gid"),
            status=effective_result.get("status"),
            followed_by=followed_by,
            primary_path=primary_path,
            staging_directory=request.staging_directory,
            target_directory=request.target_directory,
            finalization_state=request.finalization_state,
            file_paths=[entry.get("path") for entry in parsed_files if entry.get("path")],
        )
    if request is not None and download_has_all_bytes(effective_result):
        ready_message = "Download data is complete. Waiting for the Apple TV app to request the final copy."
        if request.finalization_state == "not_requested" and request.finalization_message != ready_message:
            request.finalization_message = ready_message
            log_download_event(
                "ready_for_finalization",
                requested_gid=requested_gid,
                effective_gid=effective_result.get("gid"),
                primary_path=primary_path,
                target_directory=request.target_directory,
            )

    return root_result, effective_result, followed_by, request, parsed_files, primary_path


def monitor_download_requests(stop_event: threading.Event) -> None:
    log_download_event(
        "monitor_started",
        interval_seconds=DOWNLOAD_MONITOR_INTERVAL_SECONDS,
    )
    while not stop_event.wait(DOWNLOAD_MONITOR_INTERVAL_SECONDS):
        for gid, request in list(DOWNLOAD_REQUESTS.items()):
            if request.finalization_state == "completed":
                continue

            try:
                resolve_download_request_state(gid)
            except (urllib.error.URLError, RuntimeError, OSError, ValueError) as exc:
                log_download_event(
                    "monitor_iteration_failed",
                    gid=gid,
                    finalization_state=request.finalization_state,
                    error=str(exc),
                )
                continue


def apply_download_selection(
    requested_gid: str,
    effective_result: dict[str, Any],
    keys: list[str],
) -> tuple[dict[str, Any], DownloadRequestState | None]:
    request = DOWNLOAD_REQUESTS.get(requested_gid)
    if request is None:
        return effective_result, None

    file_entries = [parse_aria2_file_entry(item) for item in effective_result.get("files", [])]
    multi_file = len(file_entries) > 1
    if not multi_file:
        if file_entries:
            selected = choose_largest_video_file(file_entries) or file_entries[0]
            request.selected_file_index = selected["index"]
            request.selected_file_name = selected["name"]
            request.selected_file_path = selected["path"]
            request.selected_file_bytes = selected["lengthBytes"]
            request.resolved_file_name = resolve_output_name(request.requested_file_name, selected["name"])
            request.selection_state = "selected"
            request.selection_message = "Single file will remain in temp until the Apple TV app requests the final copy."
            request.applied_gid = str(effective_result.get("gid") or requested_gid)
            return effective_result, request

        request.selection_state = "pending"
        request.selection_message = "Waiting for the downloader to report the file layout."
        return effective_result, request

    selected_video = choose_largest_video_file(file_entries)
    if selected_video is None:
        request.selection_state = "pending"
        request.selection_message = "Entire torrent is downloading in temp. Waiting for a video file to be identified."
        return effective_result, request

    request.selected_file_index = selected_video["index"]
    request.selected_file_name = selected_video["name"]
    request.selected_file_path = selected_video["path"]
    request.selected_file_bytes = selected_video["lengthBytes"]
    request.resolved_file_name = resolve_output_name(request.requested_file_name, selected_video["name"])
    request.selection_state = "selected"
    request.selection_message = "Entire torrent stays in temp; the selected video will be copied after the download reaches 100%."
    request.applied_gid = str(effective_result.get("gid") or requested_gid)
    return effective_result, request


def queue_download(uri: str, *, download_dir: Path | None = None, file_name: str | None = None) -> dict[str, Any]:
    config = get_downloader_config()
    if config.downloader != "aria2":
        return {
            "status": "error",
            "message": "No supported downloader is configured.",
        }

    target_dir = download_dir or get_download_root()
    staging_dir = ensure_temp_download_root()
    options: dict[str, Any] = {}
    options["dir"] = str(staging_dir)
    resolved_file_name = resolve_output_name(file_name)

    try:
        payload = aria2_rpc_call("aria2.addUri", [[uri], options])
    except urllib.error.URLError as exc:
        return {
            "status": "error",
            "message": f"Could not reach aria2 RPC: {exc.reason}",
        }
    except RuntimeError as exc:
        return {
            "status": "error",
            "message": str(exc),
        }

    if "error" in payload:
        return {
            "status": "error",
            "message": payload["error"].get("message", "aria2 RPC error"),
            "detail": payload["error"],
        }

    gid = payload.get("result")
    if gid:
        DOWNLOAD_REQUESTS[str(gid)] = DownloadRequestState(
            target_directory=str(target_dir),
            requested_file_name=file_name,
            staging_directory=str(staging_dir),
            resolved_file_name=resolved_file_name if not is_torrent_source(uri) else None,
        )
        log_download_event(
            "queued",
            gid=gid,
            target_directory=str(target_dir),
            staging_directory=str(staging_dir),
            requested_name=file_name,
            resolved_name=resolved_file_name,
            is_torrent=is_torrent_source(uri),
            uri_preview=uri[:200],
        )
    return {
        "status": "ok",
        "message": "Download queued.",
        "downloader": "aria2",
        "gid": gid,
        "directory": str(target_dir),
        "stagingDirectory": str(staging_dir),
        "fileName": resolved_file_name or file_name,
    }


def build_download_status_payload(
    root_result: dict[str, Any],
    effective_result: dict[str, Any],
    followed_by: list[str],
    request: DownloadRequestState | None,
    primary_path: str | None,
) -> dict[str, Any]:
    response_directory = request.target_directory if request and request.target_directory else effective_result.get("dir")
    response_primary_path = request.finalized_path if request and request.finalized_path else primary_path
    torrent_info = effective_result.get("bittorrent", {}).get("info", {})
    return {
        "status": "ok",
        "downloader": "aria2",
        "download": {
            "requestedGid": root_result.get("gid"),
            "gid": effective_result.get("gid"),
            "state": effective_result.get("status"),
            "infoHash": effective_result.get("infoHash"),
            "totalBytes": int(effective_result.get("totalLength", "0")),
            "completedBytes": int(effective_result.get("completedLength", "0")),
            "downloadSpeedBytesPerSecond": int(effective_result.get("downloadSpeed", "0")),
            "directory": response_directory,
            "primaryPath": response_primary_path,
            "stagingDirectory": request.staging_directory if request else effective_result.get("dir"),
            "name": torrent_info.get("name"),
            "metadataGid": root_result.get("gid") if root_result.get("gid") != effective_result.get("gid") else None,
            "followedBy": followed_by,
            "fileSelection": build_selection_payload(request),
            "finalization": build_finalization_payload(request),
            "cleanup": build_cleanup_payload(request),
        },
    }


def get_download_status(gid: str) -> dict[str, Any]:
    config = get_downloader_config()
    if config.downloader != "aria2":
        return {
            "status": "error",
            "message": "No supported downloader is configured.",
        }

    try:
        root_result, effective_result, followed_by, request, _, primary_path = resolve_download_request_state(gid)
    except urllib.error.URLError as exc:
        return {
            "status": "error",
            "message": f"Could not reach aria2 RPC: {exc.reason}",
        }
    except RuntimeError as exc:
        return {
            "status": "error",
            "message": str(exc),
        }

    return build_download_status_payload(root_result, effective_result, followed_by, request, primary_path)


def build_api_health_payload() -> dict[str, Any]:
    config = get_provider_config()
    provider = get_provider_reachability(config)
    return {
        "status": "ok" if provider["reachable"] or not provider["configured"] else "degraded",
        "provider": provider,
    }


def build_api_v1_health_payload() -> dict[str, Any]:
    config = get_provider_config()
    downloader = get_downloader_config()
    download_root = get_download_root()
    provider = get_provider_reachability(config)
    return {
        "status": "ok" if provider["reachable"] or not provider["configured"] else "degraded",
        "service": "torrentsearch-api",
        "version": "v1",
        "provider": provider,
        "downloader": {
            "name": downloader.downloader,
            "configured": bool(downloader.rpc_url) if downloader.downloader != "none" else False,
            "downloadRoot": str(download_root),
        },
    }


def get_local_ipv4_addresses() -> list[str]:
    addresses: set[str] = set()
    hostname = socket.gethostname()

    try:
        for info in socket.getaddrinfo(hostname, None, socket.AF_INET, socket.SOCK_STREAM):
            address = info[4][0]
            if not address.startswith("127.") and not address.startswith("169.254."):
                addresses.add(address)
    except socket.gaierror:
        pass

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
            probe.connect(("8.8.8.8", 80))
            address = probe.getsockname()[0]
            if not address.startswith("127."):
                addresses.add(address)
    except OSError:
        pass

    return sorted(addresses)


def ip_priority(address: str) -> tuple[int, str]:
    if address.startswith("192.168."):
        return (0, address)
    if address.startswith("172."):
        try:
            second_octet = int(address.split(".")[1])
            if 16 <= second_octet <= 31:
                return (1, address)
        except (IndexError, ValueError):
            pass
    if address.startswith("10."):
        return (2, address)
    return (3, address)


def build_api_v1_system_payload() -> dict[str, Any]:
    web_host, web_port = get_service_config("web")
    api_host, api_port = get_service_config("api")
    addresses = get_local_ipv4_addresses()
    preferred_ip = sorted(addresses, key=ip_priority)[0] if addresses else None
    provider = get_provider_reachability(get_provider_config())
    return {
        "status": "ok" if provider["reachable"] or not provider["configured"] else "degraded",
        "system": {
            "hostname": socket.gethostname(),
            "lanIPv4": addresses,
            "preferredLanIp": preferred_ip,
            "restartSupported": START_LOCAL_SCRIPT.exists(),
            "provider": provider,
            "web": {
                "host": web_host,
                "port": web_port,
                "localUrl": f"http://127.0.0.1:{web_port}/",
            },
            "api": {
                "host": api_host,
                "port": api_port,
                "localUrl": f"http://127.0.0.1:{api_port}",
                "lanUrl": f"http://{preferred_ip}:{api_port}" if preferred_ip else None,
            },
        },
    }


def launch_start_local_script() -> None:
    if not START_LOCAL_SCRIPT.exists():
        raise FileNotFoundError(f"Restart script not found: {START_LOCAL_SCRIPT}")

    creation_flags = 0
    for flag_name in ("CREATE_NEW_PROCESS_GROUP", "DETACHED_PROCESS"):
        creation_flags |= getattr(subprocess, flag_name, 0)

    subprocess.Popen(
        [
            "powershell",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(START_LOCAL_SCRIPT),
        ],
        cwd=str(ROOT),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=creation_flags,
    )


def schedule_local_restart(delay_seconds: float = 0.75) -> None:
    def restart_worker() -> None:
        time.sleep(delay_seconds)
        launch_start_local_script()

    threading.Thread(target=restart_worker, daemon=True).start()


def build_api_v1_search_payload(query: str) -> dict[str, Any]:
    raw = perform_search(query)
    items = raw.get("results", [])
    response_items = []
    for item in items:
        source_uri = resolve_download_source(item)
        result_id = uuid4().hex
        if source_uri:
            SEARCH_RESULT_CACHE[result_id] = source_uri

        response_items.append(
            {
                "resultId": result_id,
                "title": item.get("title"),
                "indexer": item.get("indexer"),
                "sizeBytes": item.get("size"),
                "seeders": item.get("seeders"),
                "leechers": item.get("leechers"),
                "publishedAt": item.get("publishDate"),
                "protocol": item.get("protocol"),
                "hasSource": bool(source_uri),
            }
        )

    return {
        "status": "ok",
        "query": query,
        "message": raw.get("message"),
        "provider": raw.get("provider"),
        "count": len(response_items),
        "items": response_items,
    }


class ApiHandler(BaseHTTPRequestHandler):
    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def read_json_body(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        body = self.rfile.read(length).decode("utf-8")
        return json.loads(body) if body else {}

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/health":
            json_response(self, HTTPStatus.OK, build_api_health_payload())
            return

        if parsed.path == "/api/v1/health":
            json_response(self, HTTPStatus.OK, build_api_v1_health_payload())
            return

        if parsed.path == "/api/v1/system":
            json_response(self, HTTPStatus.OK, build_api_v1_system_payload())
            return

        if parsed.path == "/api/v1/download-folders":
            json_response(self, HTTPStatus.OK, build_download_folder_payload())
            return

        if parsed.path in {"/api/search", "/api/v1/search"}:
            params = urllib.parse.parse_qs(parsed.query)
            query = (params.get("q") or [""])[0].strip()
            if not query:
                json_response(self, HTTPStatus.BAD_REQUEST, {"error": "Missing query parameter: q"})
                return

            if parsed.path == "/api/v1/search":
                json_response(self, HTTPStatus.OK, build_api_v1_search_payload(query))
            else:
                json_response(self, HTTPStatus.OK, perform_search(query))
            return

        if parsed.path.startswith("/api/v1/downloads/"):
            gid = parsed.path.rsplit("/", 1)[-1].strip()
            if not gid:
                json_response(self, HTTPStatus.BAD_REQUEST, {"error": "Missing download id"})
                return

            payload = get_download_status(gid)
            status_code = HTTPStatus.OK if payload.get("status") == "ok" else HTTPStatus.BAD_GATEWAY
            json_response(self, status_code, payload)
            return

        json_response(self, HTTPStatus.NOT_FOUND, {"error": "Not found"})

    def do_POST(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/v1/system/restart":
            if os.name != "nt":
                json_response(
                    self,
                    HTTPStatus.NOT_IMPLEMENTED,
                    {"error": "Restart is only implemented for the local Windows launcher."},
                )
                return

            if not START_LOCAL_SCRIPT.exists():
                json_response(
                    self,
                    HTTPStatus.NOT_IMPLEMENTED,
                    {"error": f"Restart script not found: {START_LOCAL_SCRIPT.name}"},
                )
                return

            try:
                schedule_local_restart()
            except OSError as exc:
                json_response(
                    self,
                    HTTPStatus.INTERNAL_SERVER_ERROR,
                    {"error": f"Could not schedule restart: {exc}"},
                )
                return

            json_response(
                self,
                HTTPStatus.ACCEPTED,
                {
                    "status": "restarting",
                    "message": "Local restart scheduled via start-local.ps1.",
                },
            )
            return

        path_parts = [part for part in parsed.path.split("/") if part]
        if len(path_parts) == 5 and path_parts[:3] == ["api", "v1", "downloads"] and path_parts[4] in {"finalize", "cleanup"}:
            gid = path_parts[3].strip()
            if not gid:
                json_response(self, HTTPStatus.BAD_REQUEST, {"error": "Missing download id"})
                return

            try:
                root_result, effective_result, followed_by, request, parsed_files, primary_path = resolve_download_request_state(gid)
            except urllib.error.URLError as exc:
                json_response(
                    self,
                    HTTPStatus.BAD_GATEWAY,
                    {"error": f"Could not reach aria2 RPC: {exc.reason}"},
                )
                return
            except RuntimeError as exc:
                json_response(self, HTTPStatus.BAD_GATEWAY, {"error": str(exc)})
                return

            if request is None:
                json_response(self, HTTPStatus.NOT_FOUND, {"error": "Unknown download id"})
                return

            if path_parts[4] == "finalize":
                try:
                    outcome = request_download_finalization(request, effective_result, parsed_files, primary_path)
                except ValueError as exc:
                    payload = build_download_status_payload(root_result, effective_result, followed_by, request, primary_path)
                    payload["message"] = str(exc)
                    json_response(self, HTTPStatus.CONFLICT, payload)
                    return
                except FileNotFoundError as exc:
                    payload = build_download_status_payload(root_result, effective_result, followed_by, request, primary_path)
                    payload["message"] = str(exc)
                    json_response(self, HTTPStatus.CONFLICT, payload)
                    return
                except OSError as exc:
                    payload = build_download_status_payload(root_result, effective_result, followed_by, request, primary_path)
                    payload["message"] = str(exc)
                    json_response(self, HTTPStatus.INTERNAL_SERVER_ERROR, payload)
                    return

                payload = build_download_status_payload(root_result, effective_result, followed_by, request, primary_path)
                if outcome == "started":
                    payload["message"] = "Final copy requested."
                    json_response(self, HTTPStatus.ACCEPTED, payload)
                    return
                if outcome == "in_progress":
                    payload["message"] = "Final copy is already in progress."
                else:
                    payload["message"] = "Selected video already copied."
                json_response(self, HTTPStatus.OK, payload)
                return

            outcome = request_download_cleanup(
                root_result,
                effective_result,
                followed_by,
                request,
                parsed_files,
                primary_path,
            )
            payload = build_download_status_payload(root_result, effective_result, followed_by, request, primary_path)
            if outcome == "completed":
                payload["message"] = request.cleanup_message or "Temp torrent files deleted."
            elif outcome == "in_progress":
                payload["message"] = request.cleanup_message or "Temp file deletion is already in progress."
            else:
                payload["message"] = request.cleanup_message or "Could not delete temp files."
            json_response(self, HTTPStatus.OK, payload)
            return

        if parsed.path != "/api/v1/downloads":
            json_response(self, HTTPStatus.NOT_FOUND, {"error": "Not found"})
            return

        try:
            payload = self.read_json_body()
        except json.JSONDecodeError:
            json_response(self, HTTPStatus.BAD_REQUEST, {"error": "Invalid JSON body"})
            return

        result_id = (payload.get("resultId") or "").strip()
        uri = SEARCH_RESULT_CACHE.get(result_id, "").strip() if result_id else ""
        if not uri:
            uri = (payload.get("sourceUrl") or payload.get("downloadUrl") or payload.get("magnetUri") or "").strip()
        if not uri:
            json_response(
                self,
                HTTPStatus.BAD_REQUEST,
                {"error": "Provide one of: resultId, sourceUrl, downloadUrl, magnetUri"},
            )
            return

        try:
            download_dir = resolve_download_dir(payload.get("folder"))
            file_name = validate_output_name(payload.get("fileName"))
        except ValueError as exc:
            json_response(self, HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return

        result = queue_download(uri, download_dir=download_dir, file_name=file_name)
        status_code = HTTPStatus.ACCEPTED if result.get("status") == "ok" else HTTPStatus.BAD_GATEWAY
        json_response(self, status_code, result)

    def log_message(self, format: str, *args: Any) -> None:
        print(f"api {self.address_string()} - {format % args}")


class WebHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, directory=str(WEB_DIR), **kwargs)

    def log_message(self, format: str, *args: Any) -> None:
        print(f"web {self.address_string()} - {format % args}")


def serve(server: ThreadingHTTPServer, label: str) -> None:
    host, port = server.server_address
    print(f"{label} server listening on http://{host}:{port}")
    server.serve_forever()


def main() -> None:
    web_host, web_port = get_service_config("web")
    api_host, api_port = get_service_config("api")

    web_server = ThreadingHTTPServer((web_host, web_port), WebHandler)
    api_server = ThreadingHTTPServer((api_host, api_port), ApiHandler)
    monitor_stop_event = threading.Event()

    web_thread = threading.Thread(target=serve, args=(web_server, "Web"), daemon=True)
    api_thread = threading.Thread(target=serve, args=(api_server, "API"), daemon=True)
    monitor_thread = threading.Thread(
        target=monitor_download_requests,
        args=(monitor_stop_event,),
        daemon=True,
    )

    web_thread.start()
    api_thread.start()
    monitor_thread.start()

    try:
        web_thread.join()
        api_thread.join()
    except KeyboardInterrupt:
        monitor_stop_event.set()
        web_server.shutdown()
        api_server.shutdown()
    finally:
        monitor_stop_event.set()


if __name__ == "__main__":
    main()
