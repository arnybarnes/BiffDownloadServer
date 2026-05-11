#!/usr/bin/env python3
"""
deploy.py — Archive and deploy BiffDownload to paired Apple TVs.

Usage:
    python3 deploy.py                  # bump build number, deploy to all
    python3 deploy.py --version 1.2    # also set marketing version
    python3 deploy.py --dry-run        # check devices, show versions, stop
"""

import argparse
import json
import logging
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime
from pathlib import Path

# ── Config ────────────────────────────────────────────────────────────────────

PROJECT  = "BiffDownload/BiffDownload.xcodeproj"
PBXPROJ  = "BiffDownload/BiffDownload.xcodeproj/project.pbxproj"
SCHEME   = "BiffDownload"
TEAM_ID  = "A5MEPMWNWX"
LOG_DIR  = Path("deploy-logs")

DEVICES = {
    "Game Room":       "881DB01B-A764-5378-A7B1-9B0CC799D5D3",
    "Living Room (2)": "FA7F8F69-242D-5A53-9CCC-00B1961D138E",
}

# ── ANSI colours ──────────────────────────────────────────────────────────────

GREEN  = "\033[32m"
YELLOW = "\033[33m"
RED    = "\033[31m"
CYAN   = "\033[36m"
BOLD   = "\033[1m"
DIM    = "\033[2m"
RESET  = "\033[0m"

def ok(msg):   print(f"  {GREEN}✓{RESET}  {msg}");   log.info(f"OK: {_strip(msg)}")
def warn(msg): print(f"  {YELLOW}⚠{RESET}  {msg}");  log.warning(_strip(msg))
def err(msg):  print(f"  {RED}✗{RESET}  {msg}");     log.error(_strip(msg))
def info(msg): print(f"  {CYAN}·{RESET}  {msg}");    log.info(_strip(msg))

def header(msg):
    print(f"\n{BOLD}{msg}{RESET}")
    print("─" * 60)
    log.info(f"── {_strip(msg)} ──")

def _strip(s):
    """Remove ANSI codes for clean log lines."""
    return re.sub(r"\033\[[0-9;]*m", "", s)

# ── Logging setup ─────────────────────────────────────────────────────────────

LOG_DIR.mkdir(exist_ok=True)
log_path = LOG_DIR / f"deploy-{datetime.now().strftime('%Y%m%d-%H%M%S')}.log"

logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s  %(levelname)-7s  %(message)s",
    datefmt="%H:%M:%S",
    handlers=[logging.FileHandler(log_path, encoding="utf-8")],
)
log = logging.getLogger("deploy")

# ── Spinner ───────────────────────────────────────────────────────────────────

class Spinner:
    _frames = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

    def __init__(self, label):
        self.label = label
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._spin, daemon=True)

    def _spin(self):
        i = 0
        while not self._stop.is_set():
            frame = self._frames[i % len(self._frames)]
            print(f"\r  {CYAN}{frame}{RESET}  {self.label}…", end="", flush=True)
            time.sleep(0.08)
            i += 1

    def __enter__(self):
        self._thread.start()
        return self

    def __exit__(self, *_):
        self._stop.set()
        self._thread.join()
        print("\r" + " " * (len(self.label) + 10) + "\r", end="", flush=True)

# ── Version management ────────────────────────────────────────────────────────

def read_versions():
    text = Path(PBXPROJ).read_text()
    build   = re.search(r"CURRENT_PROJECT_VERSION = (\d+);", text)
    version = re.search(r"MARKETING_VERSION = ([\d.]+);", text)
    return (
        version.group(1) if version else "1.0",
        int(build.group(1)) if build else 1,
    )


def write_versions(marketing: str, build: int):
    path = Path(PBXPROJ)
    text = path.read_text()
    text = re.sub(r"CURRENT_PROJECT_VERSION = \d+;",
                  f"CURRENT_PROJECT_VERSION = {build};", text)
    text = re.sub(r"MARKETING_VERSION = [\d.]+;",
                  f"MARKETING_VERSION = {marketing};", text)
    path.write_text(text)
    log.debug(f"Wrote versions: {marketing} build {build}")

# ── Device reachability ───────────────────────────────────────────────────────

def query_connected_devices():
    """Return a set of our config UDIDs that devicectl considers reachable."""
    tmp = Path(tempfile.mktemp(suffix=".json"))
    try:
        result = subprocess.run(
            ["xcrun", "devicectl", "list", "devices", "--json-output", str(tmp)],
            capture_output=True, text=True,
        )
        log.debug(f"devicectl exit={result.returncode}")
        if result.stdout: log.debug(f"devicectl stdout: {result.stdout[:500]}")
        if result.stderr: log.debug(f"devicectl stderr: {result.stderr[:500]}")

        if result.returncode != 0 or not tmp.exists():
            return set()
        raw = tmp.read_text()
        log.debug(f"devicectl JSON ({len(raw)} bytes)")
        data = json.loads(raw)
    except (json.JSONDecodeError, OSError) as e:
        log.error(f"devicectl parse failed: {e}")
        return set()
    finally:
        tmp.unlink(missing_ok=True)

    reachable = set()
    for dev in data.get("result", {}).get("devices", []):
        name  = dev.get("deviceProperties", {}).get("name", "?")
        conn  = dev.get("connectionProperties", {})
        state = conn.get("tunnelState", "unavailable")
        hostnames = set(conn.get("potentialHostnames", []) + conn.get("localHostnames", []))
        log.debug(f"  device '{name}' tunnelState={state} hostnames={hostnames}")
        if state == "unavailable":
            continue
        for our_name, our_id in DEVICES.items():
            if f"{our_id}.coredevice.local" in hostnames:
                log.debug(f"  → matched '{our_name}' ({our_id})")
                reachable.add(our_id)
    return reachable


def print_device_table(reachable: set):
    header("Apple TV Targets")
    col_w = max(len(n) for n in DEVICES) + 2
    for name, udid in DEVICES.items():
        if udid in reachable:
            status = f"{GREEN}● connected{RESET}"
        else:
            status = f"{YELLOW}○ not reachable{RESET}"
        print(f"  {name:<{col_w}}  {DIM}{udid}{RESET}  {status}")
        log.info(f"  {name}: {'reachable' if udid in reachable else 'not reachable'}")


def deployment_targets(reachable: set):
    """Return configured Apple TVs that are reachable enough to receive an install."""
    return [(name, udid) for name, udid in DEVICES.items() if udid in reachable]


def print_deployment_plan(targets):
    header("Deployment Plan")
    if not targets:
        warn("No reachable Apple TVs will be deployed to.")
        return

    names = ", ".join(name for name, _ in targets)
    info(f"Deploying to {len(targets)} Apple TV{'' if len(targets) == 1 else 's'}: {names}")
    for name, udid in targets:
        print(f"  {GREEN}→{RESET}  {name}  {DIM}{udid}{RESET}")
        log.info(f"Deploy target: {name} ({udid})")

# ── Build steps ───────────────────────────────────────────────────────────────

def run_xcodebuild(cmd, spinner_label):
    """Run an xcodebuild command with a spinner, logging all output."""
    log.info(f"Running: {' '.join(cmd)}")
    with Spinner(spinner_label):
        result = subprocess.run(cmd, capture_output=True, text=True)

    # Always log full output
    if result.stdout:
        for line in result.stdout.splitlines():
            log.debug(f"  {line}")
    if result.stderr:
        for line in result.stderr.splitlines():
            log.debug(f"  STDERR: {line}")

    if result.returncode != 0:
        # Surface actionable error lines to terminal
        for line in result.stdout.splitlines():
            if any(k in line for k in ("error:", "** ARCHIVE FAILED **", "** EXPORT FAILED **")):
                print(f"  {RED}{line}{RESET}")
                log.error(line)
        err(f"{spinner_label} failed (exit {result.returncode})")
        info(f"Full output in {log_path}")
        sys.exit(result.returncode)


def archive(archive_path: Path):
    header("Step 1 — Archive")
    run_xcodebuild([
        "xcodebuild", "archive",
        "-project", PROJECT,
        "-scheme", SCHEME,
        "-configuration", "Release",
        "-destination", "generic/platform=tvOS",
        "-archivePath", str(archive_path),
        "CODE_SIGN_STYLE=Automatic",
        f"DEVELOPMENT_TEAM={TEAM_ID}",
    ], "Archiving")
    ok("Archive complete")


def export_ipa(archive_path: Path, export_path: Path) -> Path:
    header("Step 2 — Export IPA")
    options = {
        "method": "development",
        "teamID": TEAM_ID,
        "compileBitcode": False,
        "thinning": "<none>",
    }
    export_path.mkdir(parents=True, exist_ok=True)
    plist_path = export_path / "ExportOptions.plist"
    with open(plist_path, "wb") as f:
        plistlib.dump(options, f)
    log.debug(f"ExportOptions: {options}")

    run_xcodebuild([
        "xcodebuild", "-exportArchive",
        "-archivePath", str(archive_path),
        "-exportPath", str(export_path),
        "-exportOptionsPlist", str(plist_path),
    ], "Exporting IPA")

    ipa_files = list(export_path.glob("*.ipa"))
    if not ipa_files:
        err("No .ipa found after export")
        info(f"Full output in {log_path}")
        sys.exit(1)

    ok(f"IPA exported → {ipa_files[0].name}")
    return ipa_files[0]


def install(ipa_path: Path, reachable: set):
    header("Step 3 — Install on devices")
    results = {
        "successful": [],
        "failed": [],
        "skipped": [],
    }

    for name, udid in DEVICES.items():
        if udid not in reachable:
            warn(f"{name} — skipped (not reachable)")
            results["skipped"].append(name)
            continue

        cmd = ["xcrun", "devicectl", "device", "install", "app",
               "--device", udid, str(ipa_path)]
        log.info(f"Running: {' '.join(cmd)}")

        with Spinner(f"Installing on {name}"):
            result = subprocess.run(cmd, capture_output=True, text=True)

        if result.stdout:
            for line in result.stdout.splitlines():
                log.debug(f"  [{name}] {line}")
        if result.stderr:
            for line in result.stderr.splitlines():
                log.debug(f"  [{name}] STDERR: {line}")

        if result.returncode == 0:
            ok(f"{name} — installed")
            results["successful"].append(name)
        else:
            err(f"{name} — install failed (exit {result.returncode})")
            # Show stderr on terminal for install failures
            for line in (result.stdout + result.stderr).splitlines():
                if line.strip():
                    print(f"    {DIM}{line}{RESET}")
            info(f"Full output in {log_path}")
            results["failed"].append(name)

    return results

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Archive and deploy BiffDownload to Apple TVs.")
    parser.add_argument("--version", metavar="X.Y", help="Set marketing version (e.g. 1.2)")
    parser.add_argument("--dry-run", action="store_true", help="Check devices and versions only, no build")
    args = parser.parse_args()

    repo_root = Path(__file__).parent
    os.chdir(repo_root)

    log.info(f"deploy.py started  args={vars(args)}")
    info(f"Log → {log_path}")

    # ── Versions ──────────────────────────────────────────────────────────────
    current_version, current_build = read_versions()
    new_version = args.version or current_version
    new_build   = current_build + 1
    log.info(f"Versions: {current_version} ({current_build}) → {new_version} ({new_build})")

    header("Version")
    if args.version and args.version != current_version:
        info(f"Marketing version  {DIM}{current_version}{RESET} → {BOLD}{new_version}{RESET}")
    else:
        info(f"Marketing version  {BOLD}{current_version}{RESET}")
    info(f"Build number       {DIM}{current_build}{RESET} → {BOLD}{new_build}{RESET}")

    # ── Devices ───────────────────────────────────────────────────────────────
    with Spinner("Checking devices"):
        reachable = query_connected_devices()

    print_device_table(reachable)
    targets = deployment_targets(reachable)

    if args.dry_run:
        print_deployment_plan(targets)
        print()
        info("Dry run — stopping before build.")
        return

    print_deployment_plan(targets)

    if not targets:
        err("No target devices reachable — aborting.")
        info(f"Full output in {log_path}")
        sys.exit(1)

    # ── Bump versions in project ──────────────────────────────────────────────
    write_versions(new_version, new_build)
    info(f"Updated {PBXPROJ}")

    work_dir     = Path(tempfile.mkdtemp(prefix="BiffDownload-"))
    archive_path = work_dir / "BiffDownload.xcarchive"
    export_path  = work_dir / "export"
    log.info(f"Work dir: {work_dir}")

    try:
        archive(archive_path)
        ipa_path = export_ipa(archive_path, export_path)
        install_results = install(ipa_path, reachable)
    except KeyboardInterrupt:
        print("\n")
        warn("Interrupted — restoring version numbers.")
        write_versions(current_version, current_build)
        log.warning("Interrupted by user — versions restored.")
        sys.exit(1)
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)
        log.info(f"Cleaned up {work_dir}")

    # ── Summary ───────────────────────────────────────────────────────────────
    header("Done")
    successful = install_results["successful"]
    failed = install_results["failed"]
    skipped = install_results["skipped"]

    if successful:
        ok(f"Successful: {', '.join(successful)}")
    else:
        warn("Successful: none")

    if skipped:
        warn(f"Skipped: {', '.join(skipped)}")

    if failed:
        err(f"Failed: {', '.join(failed)}")
        warn(f"Deployment incomplete for {new_version} ({new_build}).")
        info(f"Log → {log_path}")
        sys.exit(1)
    else:
        ok(f"Deployed {BOLD}{new_version} ({new_build}){RESET} to: {', '.join(successful)}")
        info(f"Log → {log_path}")


if __name__ == "__main__":
    main()
