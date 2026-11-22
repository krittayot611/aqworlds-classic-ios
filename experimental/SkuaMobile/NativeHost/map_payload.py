"""Prepare a platform-specific Mono framework and the map reader's app resources."""
import argparse
from pathlib import Path
import os
import plistlib
import shutil
import subprocess


ROOT = Path(__file__).resolve().parent
FRAMEWORK = Path("Frameworks/AqwManagedHost.framework")
RESOURCES = Path("AqwMapRuntime")


def stage_managed(rid, managed, metadata):
    build = ROOT / "bin/Release/net10.0" / rid
    products = list(build.rglob("libAqwManagedHost.dylib"))
    if not products:
        raise RuntimeError(f"Publish NativeHost for {rid} before packaging")
    staged = ROOT / "obj/host-managed" / rid
    for name in ("System.Private.CoreLib.dll", "AqwManagedHost.dll", "Runtime.dll"):
        if not (staged / name).is_file():
            raise RuntimeError(f"Missing staged runtime assembly: {staged / name}")
    managed.mkdir(parents=True, exist_ok=True)
    for assembly in staged.glob("*.dll"):
        shutil.copy2(assembly, managed / assembly.name)
    configs = [file for parent in (ROOT / "obj/Release", ROOT / "bin/Release")
               for file in parent.rglob("*runtimeconfig*.bin") if rid in file.parts]
    if not configs:
        raise RuntimeError(f"Missing binary runtime configuration for {rid}")
    shutil.copy2(max(configs, key=lambda p: p.stat().st_mtime), managed / "runtimeconfig.bin")
    pack = Path(os.environ["DOTNET_ROOT"]) / "packs/Microsoft.NETCore.App.Ref"
    refs = sorted(pack.glob("10.*/ref/net10.0"), key=lambda p: tuple(map(int, p.parents[1].name.split("."))))
    if not refs:
        raise RuntimeError("The .NET 10 compiler reference pack is missing")
    metadata.mkdir(parents=True, exist_ok=True)
    for reference in refs[-1].glob("*.dll"):
        shutil.copy2(reference, metadata / reference.name)
    return max(products, key=lambda p: p.stat().st_mtime)


def prepare(rid, dest):
    resources = dest / RESOURCES
    metadata = resources / "metadata"
    product = stage_managed(rid, resources / "managed", metadata)
    # Roslyn needs the public API built against the same .NET reference pack.
    # The Mono implementation in managed/ has been relinked against private CoreLib.
    host_api = ROOT / "bin/Release/net10.0" / rid / "ref/AqwManagedHost.dll"
    shutil.copy2(host_api, metadata / host_api.name)
    scripts = resources / "scripts"
    scripts.mkdir(exist_ok=True)
    shutil.copy2(ROOT / "ReadMap.cs.txt", scripts / "ReadMap.cs")
    framework = dest / FRAMEWORK
    framework.mkdir(parents=True, exist_ok=True)
    image = framework / "AqwManagedHost"
    shutil.copy2(product, image)
    simulator = rid == "iossimulator-arm64"
    platform = "IOSSIMULATOR" if simulator else "IOS"
    subprocess.run(["xcrun", "lipo", image, "-verify_arch", "arm64"], check=True)
    info = subprocess.check_output(["xcrun", "vtool", "-show-build", image], text=True)
    fields = dict(row.split() for row in info.splitlines() if len(row.split()) == 2)
    if fields.get("platform", "").upper() != platform:
        raise RuntimeError(f"Expected {platform} in the native image:\n{info}")
    symbols = subprocess.check_output(["xcrun", "nm", "-gjU", image], text=True).splitlines()
    if "_aqw_read_current_map" not in symbols:
        raise RuntimeError("The native image does not export the C# map entry point")
    subprocess.run(["xcrun", "strip", "-S", image], check=True)
    subprocess.run(["xcrun", "install_name_tool", "-id", "@rpath/AqwManagedHost.framework/AqwManagedHost", image], check=True)
    (framework / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "com.personal.aqwprobe.map-runtime", "CFBundleExecutable": image.name,
        "CFBundleName": image.name, "CFBundlePackageType": "FMWK", "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0", "MinimumOSVersion": fields["minos"],
        "CFBundleSupportedPlatforms": ["iPhoneSimulator" if simulator else "iPhoneOS"],
    }))


def embed(payload, app, simulator):
    details = plistlib.loads((payload / FRAMEWORK / "Info.plist").read_bytes())
    expected = "iPhoneSimulator" if simulator else "iPhoneOS"
    if details["CFBundleSupportedPlatforms"] != [expected]:
        raise RuntimeError(f"Expected a {expected} payload")
    shutil.copytree(payload / FRAMEWORK, app / FRAMEWORK)
    shutil.copytree(payload / RESOURCES, app / RESOURCES)
    info_path = app / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    minimum = max((details["MinimumOSVersion"], info.get("MinimumOSVersion", "0")),
                  key=lambda version: tuple(map(int, version.split("."))))
    info["MinimumOSVersion"] = minimum
    info_path.write_bytes(plistlib.dumps(info))
    if simulator:
        subprocess.run(["codesign", "--force", "--sign", "-", app / FRAMEWORK], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rid", choices=["ios-arm64", "iossimulator-arm64"])
    parser.add_argument("dest", type=Path)
    args = parser.parse_args()
    prepare(args.rid, args.dest)
