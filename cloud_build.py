#!/usr/bin/env python3
"""Build an AIR interpreter IPA on macOS and remove its temporary packaging signature."""

import argparse
import datetime
import hashlib
import os
from pathlib import Path
import plistlib
import secrets
import shutil
import subprocess
import sys
import tempfile
import uuid
import xml.etree.ElementTree as ET
import zipfile


def prepare_packaging_identity(directory, password):
    """Create a local identity for packaging. It grants no Apple device access."""
    key = directory / "packaging.key"
    cert = directory / "packaging.pem"
    cert_der = directory / "packaging.der"
    p12 = directory / "packaging.p12"
    profile_xml = directory / "packaging.plist"
    profile = directory / "packaging.mobileprovision"
    env = dict(os.environ, AQW_PACKAGING_PASSWORD=password)
    subprocess.run([
        "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
        "-keyout", str(key), "-out", str(cert), "-days", "7",
        "-subj", "/CN=Local IPA packaging/OU=LOCALBUILD/O=Personal build",
    ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    subprocess.run([
        "openssl", "x509", "-in", str(cert), "-outform", "DER", "-out", str(cert_der),
    ], check=True)
    subprocess.run([
        "openssl", "pkcs12", "-export", "-inkey", str(key), "-in", str(cert),
        "-out", str(p12), "-passout", "env:AQW_PACKAGING_PASSWORD",
    ], check=True, env=env)
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    profile_xml.write_bytes(plistlib.dumps({
        "AppIDName": "AQW local packaging",
        "ApplicationIdentifierPrefix": ["LOCALBUILD"],
        "CreationDate": now,
        "DeveloperCertificates": [cert_der.read_bytes()],
        "Entitlements": {
            "application-identifier": "LOCALBUILD.com.personal.aqwprobe",
            "com.apple.developer.team-identifier": "LOCALBUILD",
            "get-task-allow": True,
            "keychain-access-groups": ["LOCALBUILD.*"],
        },
        "ExpirationDate": now + datetime.timedelta(days=7),
        "Name": "Local packaging only",
        "Platform": ["iOS"],
        "ProvisionedDevices": ["0000000000000000000000000000000000000000"],
        "TeamIdentifier": ["LOCALBUILD"],
        "TeamName": "Local IPA packaging",
        "UUID": str(uuid.uuid4()).upper(),
        "Version": 1,
    }))
    subprocess.run([
        "openssl", "smime", "-sign", "-binary", "-nodetach", "-in", str(profile_xml),
        "-signer", str(cert), "-inkey", str(key), "-outform", "DER", "-out", str(profile),
    ], check=True)
    return p12, profile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    sdk = args.sdk.resolve()
    if sys.platform != "darwin" or not (sdk / "lib/aot").is_dir():
        parser.error("Use a macOS AIR SDK with iOS packaging components.")
    subprocess.run([sys.executable, str(root / "build.py"), "--sdk", str(sdk)], check=True)
    output = root / "output"
    output.mkdir(exist_ok=True)
    version = ET.parse(root / "build/Probe-app.xml").find("{*}versionNumber").text
    final_ipa = output / ("AQWorlds-Classic-" + version + ".ipa")
    final_ipa.unlink(missing_ok=True)
    with tempfile.TemporaryDirectory(prefix="aqw-packaging-") as temp:
        directory = Path(temp)
        password = secrets.token_urlsafe(24)
        if os.environ.get("GITHUB_ACTIONS"):
            print("::add-mask::" + password, flush=True)
        p12, profile = prepare_packaging_identity(directory, password)
        temporary_ipa = directory / "packaged.ipa"
        print("Packaging interpreter IPA with a temporary local identity.", flush=True)
        subprocess.run([
            "java", "-Xmx2048m", "-jar", str(sdk / "lib/adt.jar"),
            "-cfg", str(root / "adt.cfg"), "-package",
            "-target", "ipa-test-interpreter",
            "-storetype", "pkcs12",
            "-keystore", str(p12), "-storepass", password,
            "-provisioning-profile", str(profile),
            str(temporary_ipa), str(root / "build/Probe-app.xml"),
            "-extdir", str(root / "build/extensions"),
            "-C", str(root / "build"), "Probe.swf", "icons", "Background.jpg",
        ], check=True)
        unpacked = directory / "unpacked"
        subprocess.run(["unzip", "-q", str(temporary_ipa), "-d", str(unpacked)], check=True)
        apps = list((unpacked / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise RuntimeError("Expected exactly one app in the packaged IPA.")
        app = apps[0]
        info = plistlib.loads((app / "Info.plist").read_bytes())
        if info["CFBundleIdentifier"] != "com.personal.aqwprobe":
            raise RuntimeError("Bundle ID changed; this would prevent an in-place update.")
        if info["CFBundleDisplayName"] != "AQWorlds Classic":
            raise RuntimeError("The packaged display name is incorrect.")
        executable = app / info["CFBundleExecutable"]
        architectures = subprocess.check_output(["lipo", "-archs", str(executable)], text=True)
        if "arm64" not in architectures.split():
            raise RuntimeError("The packaged executable must support arm64 iPhones.")
        subprocess.run(["codesign", "--remove-signature", str(app)], check=True)
        for profile_path in app.rglob("embedded.mobileprovision"):
            profile_path.unlink()
        for signatures in app.rglob("_CodeSignature"):
            shutil.rmtree(signatures)
        subprocess.run(["zip", "-qry", str(final_ipa), "Payload"], cwd=unpacked, check=True)
    with zipfile.ZipFile(final_ipa) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("IPA archive failed its integrity check.")
        names = archive.namelist()
        if any("_CodeSignature/" in name or name.endswith("embedded.mobileprovision") for name in names):
            raise RuntimeError("Temporary signing material remains in the IPA.")
    print("Created " + final_ipa.name, flush=True)
    print("SHA256 " + hashlib.sha256(final_ipa.read_bytes()).hexdigest(), flush=True)
    print("Device installation and AQWorlds gameplay remain unverified.", flush=True)


if __name__ == "__main__":
    main()

