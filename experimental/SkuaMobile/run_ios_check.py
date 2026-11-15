"""Run the developer-only iOS compiler check and retain startup/crash evidence."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import time

BUNDLE = "com.personal.aqw.scriptcheck"
PROCESS = "AqwScriptRuntimeCheck"


def version(text: str) -> tuple[int, ...]:
    return tuple(int(part) for part in text.split("."))[:2]


def choose_phone(devices: dict, runtimes: list[dict], sdk: str) -> dict:
    compatible = {
        runtime["identifier"]: version(runtime["version"])
        for runtime in runtimes
        if runtime.get("isAvailable", False)
        and ".iOS-" in runtime["identifier"]
        and version(runtime["version"]) <= version(sdk)
    }
    phones = [
        {**device, "runtime": runtime, "runtimeVersion": compatible[runtime]}
        for runtime, group in devices.items() if runtime in compatible
        for device in group
        if device.get("isAvailable", False) and device["name"].startswith("iPhone")
    ]
    if not phones:
        raise RuntimeError(f"No available iPhone simulator compatible with Xcode SDK {sdk}")
    return max(phones, key=lambda d: (d["runtimeVersion"], d["state"] == "Booted", d["name"] == "iPhone 16", d["name"]))


def boot_device(device: dict, run) -> dict:
    """Retry infrastructure startup once on a fresh simulator, without erasing data."""
    try:
        if device["state"] != "Booted":
            run("xcrun", "simctl", "boot", device["udid"])
        run("xcrun", "simctl", "bootstatus", device["udid"], "-b", timeout=240)
        return device
    except (subprocess.TimeoutExpired, RuntimeError) as error:
        print(f"Simulator boot failed; trying a fresh device: {error}", flush=True)
        run("xcrun", "simctl", "shutdown", device["udid"], timeout=30, required=False)
        fresh_id = run("xcrun", "simctl", "create", "AQW Runtime Check Retry",
                       device["deviceTypeIdentifier"], device["runtime"], timeout=60)
        fresh = {**device, "udid": fresh_id, "state": "Shutdown", "freshBootRetry": True}
        run("xcrun", "simctl", "boot", fresh_id)
        run("xcrun", "simctl", "bootstatus", fresh_id, "-b", timeout=240)
        return fresh


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=Path("runtime-diagnostics"))
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    app = args.app.resolve()
    if not app.is_dir():
        raise RuntimeError(f"Missing built app: {app}")
    device = None
    container = None
    app_pid = None
    launched_at = time.time()
    command_number = 0

    def run(*command: str, timeout: int = 120, required: bool = True) -> str:
        nonlocal command_number
        command_number += 1
        print("RUN:", " ".join(command), flush=True)
        try:
            proc = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
            text = proc.stdout + proc.stderr
            (output / f"command-{command_number:02}.txt").write_text(text)
            if proc.returncode and required:
                raise RuntimeError(f"Command failed ({proc.returncode}): {' '.join(command)}\n{text[-6000:]}")
            return proc.stdout.strip()
        except subprocess.TimeoutExpired as exc:
            def decode(value):
                return value.decode(errors="replace") if isinstance(value, bytes) else (value or "")
            evidence = decode(exc.stdout) + decode(exc.stderr)
            (output / f"command-{command_number:02}.txt").write_text(evidence + "\n" + str(exc))
            print(evidence[-2000:], flush=True)
            if required:
                raise
            return ""

    try:
        sdk = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version")
        runtime_inventory = json.loads(run("xcrun", "simctl", "list", "runtimes", "-j"))
        device_inventory = json.loads(run("xcrun", "simctl", "list", "devices", "available", "-j"))
        (output / "simulator-inventory.json").write_text(json.dumps({
            "sdk": sdk, "runtimes": runtime_inventory, "devices": device_inventory,
        }, indent=2))
        device = choose_phone(device_inventory["devices"], runtime_inventory["runtimes"], sdk)
        (output / "selected-device.json").write_text(json.dumps(device, indent=2))
        print("Selected:", device, flush=True)
        device = boot_device(device, run)
        (output / "selected-device.json").write_text(json.dumps(device, indent=2))
        run("xcrun", "simctl", "install", device["udid"], str(app))
        container = Path(run("xcrun", "simctl", "get_app_container", device["udid"], BUNDLE, "data"))
        # A fresh result is required even if a developer reruns this check locally.
        for name in ("runtime-result.txt", "runtime-progress.txt"):
            (container / "Documents" / name).unlink(missing_ok=True)
        # This freshly installed CI app has no process to terminate. Avoid the
        # iOS 26 FrontBoard termination request before launching it directly.
        # A console attachment is also unnecessary: results are stored in Documents.
        # CoreSimulatorBridge retries launch for 120 seconds. Let that request
        # finish before the harness times out, so its actual error is retained.
        launch_output = run("xcrun", "simctl", "launch",
                            device["udid"], BUNDLE, timeout=150)
        (output / "launch-result.txt").write_text(launch_output)
        if not launch_output.startswith(BUNDLE + ": "):
            raise RuntimeError(f"Simulator did not confirm an application PID: {launch_output}")
        app_pid = int(launch_output.rsplit(":", 1)[1].strip())
        print("Launched:", launch_output, flush=True)
        result = container / "Documents/runtime-result.txt"
        progress = container / "Documents/runtime-progress.txt"
        deadline = time.monotonic() + args.timeout
        previous = ""
        while not result.exists() and time.monotonic() < deadline:
            current = progress.read_text() if progress.exists() else ""
            if current != previous:
                print(current[len(previous):], end="", flush=True)
                previous = current
            time.sleep(1)
        if not result.exists():
            run("/usr/bin/sample", str(app_pid), "5", "-file", str(output / "app-stacks.txt"),
                timeout=20, required=False)
            raise RuntimeError(f"No result after {args.timeout}s. Last stage:\n{previous[-4000:]}")
        text = result.read_text()
        (output / "runtime-result.txt").write_text(text)
        print(text, flush=True)
        if not text.startswith("PASS:"):
            raise RuntimeError("The iOS compiler/IL execution check reported FAIL; see runtime-result.txt")
    except Exception as exc:
        (output / "harness-error.txt").write_text(str(exc))
        raise
    finally:
        if container is not None:
            for name in ("runtime-progress.txt", "runtime-result.txt"):
                source = container / "Documents" / name
                if source.exists():
                    shutil.copy2(source, output / name)
        if device is not None:
            run("xcrun", "simctl", "io", device["udid"], "screenshot", str(output / "screen.png"),
                timeout=30, required=False)
            logs = run("xcrun", "simctl", "spawn", device["udid"], "log", "show", "--last", "5m",
                       "--style", "compact", "--predicate", f'process == "{PROCESS}" OR eventMessage CONTAINS "{BUNDLE}"',
                       timeout=30, required=False)
            (output / "simulator-app.log").write_text(logs)
            device_root = Path.home() / "Library/Developer/CoreSimulator/Devices" / device["udid"]
            for location in (Path.home() / "Library/Logs/DiagnosticReports",
                             device_root / "data/Library/Logs/CrashReporter"):
                if location.exists():
                    for path in location.rglob(f"{PROCESS}*"):
                        if path.is_file() and path.stat().st_mtime >= launched_at - 5:
                            shutil.copy2(path, output / path.name)
            run("xcrun", "simctl", "terminate", device["udid"], BUNDLE, timeout=15, required=False)


if __name__ == "__main__":
    main()
