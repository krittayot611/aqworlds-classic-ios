#!/usr/bin/env python3
"""Compile AQWorlds Classic and optionally package a personal interpreter IPA."""

import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", required=True, type=Path, help="AIR SDK directory")
    parser.add_argument("--package", action="store_true", help="Also build an iOS test IPA")
    parser.add_argument("--p12", type=Path, help="Local Apple signing identity (.p12)")
    parser.add_argument("--profile", type=Path, help="Local iOS provisioning profile")
    parser.add_argument("--app-id", default="com.personal.aqwprobe", help="Bundle ID matching the profile")
    args = parser.parse_args()
    sdk = args.sdk.expanduser().resolve()
    root = Path(__file__).resolve().parent
    build = root / "build"
    java = shutil.which("java")
    if not java:
        parser.error("Install a Java runtime and make java available on PATH.")
    if not (sdk / "lib/mxmlc-cli.jar").is_file():
        parser.error("The SDK directory must contain lib/mxmlc-cli.jar.")
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+)+", args.app_id):
        parser.error("Use a reverse-domain bundle ID matching your provisioning profile.")
    if args.package:
        if not (sdk / "lib/aot").is_dir():
            parser.error("This SDK has no iOS packager. Use the Windows or macOS AIR SDK with iOS support.")
        for name, path in [("--p12", args.p12), ("--profile", args.profile)]:
            if path is None or not path.expanduser().is_file():
                parser.error("Provide " + name + " with a local signing file.")

    build.mkdir(exist_ok=True)
    icon_dir = build / "icons"
    icon_dir.mkdir(exist_ok=True)
    for size in (29, 40, 50, 57, 58, 60, 72, 76, 80, 87, 100, 114, 120, 144, 152, 167, 180, 1024):
        destination = icon_dir / ("icon" + str(size) + ".png")
        if sys.platform == "darwin":
            command = ["sips", "-z", str(size), str(size), str(root / "AppIconSource.png"),
                       "--out", str(destination)]
        else:
            converter = shutil.which("magick") or shutil.which("convert")
            if not converter:
                parser.error("Install ImageMagick to generate native icon sizes on this platform.")
            command = [converter, str(root / "AppIconSource.png"),
                       "-resize", str(size) + "x" + str(size) + "!", str(destination)]
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL)
    subprocess.run([
        java, "-Dflexlib=" + str(sdk / "frameworks"),
        "-jar", str(sdk / "lib/mxmlc-cli.jar"), "+configname=air",
        "-source-path=" + str(root),
        "-debug=false",
        "-output=" + str(build / "Probe.swf"), str(root / "Main.as"),
    ], check=True)

    namespace = "http://ns.adobe.com/air/application/51.3"
    ET.register_namespace("", namespace)
    descriptor = ET.parse(root / "Probe-app.xml")
    descriptor.find("{" + namespace + "}id").text = args.app_id
    version = descriptor.find("{" + namespace + "}versionNumber").text
    descriptor.write(build / "Probe-app.xml", encoding="utf-8", xml_declaration=True)
    # AIR's prepare command validates the application descriptor and file list.
    subprocess.run([
        java, "-jar", str(sdk / "lib/adt.jar"), "-cfg", str(root / "adt.cfg"), "-prepare",
        str(build / "Probe.airi"), str(build / "Probe-app.xml"),
        "-C", str(build), "Probe.swf", "icons",
    ], check=True)
    print("Compiled SWF and validated AIR descriptor.")

    if args.package:
        # ADT requests the signing password locally. It is never written to a file.
        subprocess.run([
            java, "-jar", str(sdk / "lib/adt.jar"), "-cfg", str(root / "adt.cfg"), "-package",
            "-target", "ipa-test-interpreter", "-storetype", "pkcs12",
            "-keystore", str(args.p12.expanduser().resolve()),
            "-provisioning-profile", str(args.profile.expanduser().resolve()),
            str(build / ("AQWorlds-Classic-" + version + ".ipa")),
            str(build / "Probe-app.xml"), "-C", str(build), "Probe.swf", "icons",
        ], check=True)
        print("IPA packaged. Installation, login and gameplay still require an iPhone test.")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        print("Build failed. See the AIR SDK error above.", file=sys.stderr)
        sys.exit(error.returncode)
