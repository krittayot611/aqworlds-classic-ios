#!/usr/bin/env python3
"""Compare startup before and after a personal signer's bundle-ID change."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import secrets
import struct
import subprocess
import tempfile
import time
import zipfile
import zlib

from cloud_build import prepare_packaging_identity


def run(*command, **options):
    return subprocess.run(command, check=True, **options)


def visible_fraction(path):
    """Measure non-black screenshot pixels without changing the image."""
    png = path.read_bytes()
    width, height, depth, color = struct.unpack_from(">IIBB", png, 16)
    if depth != 8 or color not in (2, 6):
        raise RuntimeError("Unexpected simulator screenshot PNG format.")
    channels = 4 if color == 6 else 3
    compressed = bytearray()
    offset = 8
    while offset < len(png):
        length = struct.unpack_from(">I", png, offset)[0]
        if png[offset + 4:offset + 8] == b"IDAT":
            compressed.extend(png[offset + 8:offset + 8 + length])
        offset += length + 12
    data = zlib.decompress(compressed)
    stride = width * channels
    previous = bytearray(stride)
    visible = sampled = 0
    for y in range(height):
        start = y * (stride + 1)
        kind = data[start]
        row = bytearray(data[start + 1:start + 1 + stride])
        if kind == 2 and not any(row):
            row = previous[:]
        elif kind:
            for i in range(stride):
                left = row[i - channels] if i >= channels else 0
                above = previous[i]
                corner = previous[i - channels] if i >= channels else 0
                if kind == 1:
                    prediction = left
                elif kind == 2:
                    prediction = above
                elif kind == 3:
                    prediction = (left + above) // 2
                elif kind == 4:
                    p = left + above - corner
                    distances = (abs(p - left), abs(p - above), abs(p - corner))
                    prediction = (left, above, corner)[distances.index(min(distances))]
                else:
                    raise RuntimeError("Unexpected PNG row filter.")
                row[i] = (row[i] + prediction) & 255
        if y % 8 == 0:
            for x in range(0, width, 8):
                pixel = x * channels
                visible += max(row[pixel:pixel + 3]) > 8
                sampled += 1
        previous = row
    return visible / sampled


def build_alert_logger(directory, sdk):
    """Log native startup alerts in the simulator without changing their behavior."""
    source = directory / "StartupAlertLogger.m"
    source.write_text('''#import <UIKit/UIKit.h>
#import <objc/runtime.h>
static IMP originalPresent;
static void logPresent(id receiver, SEL selector, UIViewController *controller, BOOL animated, id completion) {
    if ([controller isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)controller;
        NSLog(@"AQW-NATIVE-ALERT title=%@ message=%@", alert.title, alert.message);
    }
    ((void (*)(id, SEL, UIViewController *, BOOL, id))originalPresent)(receiver, selector, controller, animated, completion);
}
__attribute__((constructor)) static void startLogging(void) {
    Method method = class_getInstanceMethod([UIViewController class], @selector(presentViewController:animated:completion:));
    originalPresent = method_setImplementation(method, (IMP)logPresent);
    NSLog(@"AQW-NATIVE-DIAGNOSTIC loaded");
}
''')
    library = directory / "StartupAlertLogger.dylib"
    run("xcrun", "clang", "-target", "x86_64-apple-ios12.0-simulator", "-dynamiclib",
        "-isysroot", sdk, "-fobjc-arc", "-framework", "UIKit", "-framework", "Foundation",
        str(source), "-o", str(library))
    run("codesign", "--force", "--sign", "-", str(library))
    return library


def capture_case(app, bundle_id, label, udid, output, library=None):
    run("codesign", "--force", "--sign", "-", str(app))
    run("xcrun", "simctl", "install", udid, str(app))
    data = Path(subprocess.check_output(
        ["xcrun", "simctl", "get_app_container", udid, bundle_id, "data"], text=True
    ).strip())
    marker = data / "Documents/aqw-startup.log"
    marker.unlink(missing_ok=True)
    console_path = output / ("simulator-" + label + "-console.log")
    env = dict(os.environ, SIMCTL_CHILD_NSUnbufferedIO="YES")
    if library is not None:
        env["SIMCTL_CHILD_DYLD_INSERT_LIBRARIES"] = str(library)
    with console_path.open("wb") as console:
        process = subprocess.Popen(
            ["xcrun", "simctl", "launch", "--console", udid, bundle_id, "--smoke-game"],
            stdout=console, stderr=subprocess.STDOUT, env=env
        )
        try:
            time.sleep(25)
            screenshot = output / ("simulator-" + label + ".png")
            run("xcrun", "simctl", "io", udid, "screenshot", str(screenshot))
            startup_text = marker.read_text() if marker.exists() else ""
            (output / ("simulator-" + label + "-startup.log")).write_text(startup_text)
            fraction = visible_fraction(screenshot)
            console_text = console_path.read_text(errors="replace")
            result = {
                "bundle_id": bundle_id,
                "process_survived_startup": process.poll() is None,
                "main_swf_started": bool(startup_text),
                "ui_initialized": "UI ready" in startup_text,
                "game_client_attached": "Game client attached" in startup_text,
                "stage_security_error": "SecurityError 2070" in startup_text,
                "non_black_fraction": fraction,
                "alert_logger_loaded": "AQW-NATIVE-DIAGNOSTIC" in console_text,
                "native_alerts": [line for line in console_text.splitlines() if "AQW-NATIVE-ALERT" in line],
                "screenshot": screenshot.name,
            }
            result["app_ui_visible"] = result["ui_initialized"] and fraction > 0.05
            print(json.dumps({label: result}), flush=True)
            return result
        finally:
            subprocess.run(["xcrun", "simctl", "terminate", udid, bundle_id], check=False)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    output = root / "output"
    output.mkdir(exist_ok=True)
    sdk = args.sdk.resolve()
    platform_sdk = subprocess.check_output(
        ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True
    ).strip()
    devices = json.loads(subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "available", "--json"], text=True
    ))["devices"]
    choices = [device for group in devices.values() for device in group
               if device.get("isAvailable") and device["name"].startswith(("iPad", "iPhone"))]
    if not choices:
        raise RuntimeError("No available iOS simulator is installed on this runner.")
    choices.sort(key=lambda device: (not device["name"].startswith("iPad"), device["name"]))
    device = choices[0]
    udid = device["udid"]
    print("Starting simulator " + device["name"], flush=True)
    if device["state"] != "Booted":
        run("xcrun", "simctl", "boot", udid)
    run("xcrun", "simctl", "bootstatus", udid, "-b", timeout=600)

    with tempfile.TemporaryDirectory(prefix="aqw-simulator-") as temp:
        directory = Path(temp)
        password = secrets.token_urlsafe(24)
        if os.environ.get("GITHUB_ACTIONS"):
            print("::add-mask::" + password, flush=True)
        p12, profile = prepare_packaging_identity(directory, password)
        ipa = directory / "simulator.ipa"
        run("java", "-Xmx2048m", "-jar", str(sdk / "lib/adt.jar"),
            "-cfg", str(root / "adt.cfg"), "-package", "-target", "ipa-test-interpreter-simulator",
            "-storetype", "pkcs12", "-keystore", str(p12), "-storepass", password,
            "-provisioning-profile", str(profile), str(ipa), str(root / "build/Probe-app.xml"),
            "-platformsdk", platform_sdk, "-C", str(root / "build"), "Probe.swf", "icons")
        with zipfile.ZipFile(ipa) as archive:
            archive.extractall(directory / "unpacked")
        app, = (directory / "unpacked/Payload").glob("*.app")
        info_path = app / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        original_id = info["CFBundleIdentifier"]
        (app / "embedded.mobileprovision").unlink(missing_ok=True)
        results = {"device": device["name"], "scope": "Official game import and Stage attachment; physical signing, login and gameplay are unverified."}
        for label, bundle_id in [("original", original_id), ("resigned", original_id + ".resigntest")]:
            info["CFBundleIdentifier"] = bundle_id
            info_path.write_bytes(plistlib.dumps(info))
            results[label] = capture_case(app, bundle_id, label, udid, output)
            (output / "simulator-startup.json").write_text(json.dumps(results, indent=2) + "\n")
        if not all(results[label]["app_ui_visible"] and results[label]["game_client_attached"]
                   and not results[label]["stage_security_error"] for label in ("original", "resigned")):
            try:
                library = build_alert_logger(directory, platform_sdk)
                results["native_alert_diagnostic"] = capture_case(
                    app, info["CFBundleIdentifier"], "alert-diagnostic", udid, output, library
                )
            except Exception as error:
                results["native_alert_diagnostic"] = {"diagnostic_error": str(error)}
            (output / "simulator-startup.json").write_text(json.dumps(results, indent=2) + "\n")
            raise RuntimeError("Game import or startup failed. See simulator screenshots and startup logs.")


if __name__ == "__main__":
    main()
