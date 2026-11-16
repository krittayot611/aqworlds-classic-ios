"""Package the Mono library in a native simulator app; never builds a game IPA."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import os

root = Path(__file__).resolve().parent
libs = list((root / 'bin/Release').rglob('libAqwManagedHost.dylib'))
if not libs:
    raise RuntimeError('Mono LibraryBuilder did not produce libAqwManagedHost.dylib')
lib = max(libs, key=lambda p: p.stat().st_mtime)
out = root / 'smoke/AqwScriptRuntimeCheck.app'
frameworks = out / 'Frameworks'
frameworks.mkdir(parents=True, exist_ok=True)
for source in lib.parent.glob('*.dylib'):
    shutil.copy2(source, frameworks / source.name)
configs = [p for base in (root / 'obj/Release', root / 'bin/Release')
           for p in base.rglob('*runtimeconfig*.bin')]
if not configs:
    raise RuntimeError('Mono binary runtime configuration missing from both build and publish outputs')
shutil.copy2(max(configs, key=lambda p: p.stat().st_mtime), frameworks / 'runtimeconfig.bin')
subprocess.run(['install_name_tool', '-id', '@rpath/libAqwManagedHost.dylib', str(frameworks / lib.name)], check=True)
metadata = out / 'metadata'
metadata.mkdir(exist_ok=True)
ref_root = Path(os.environ['DOTNET_ROOT']) / 'packs/Microsoft.NETCore.App.Ref'
refs = sorted(ref_root.glob('10.*/ref/net10.0'), key=lambda p: tuple(map(int, p.parents[1].name.split('.'))))
if not refs:
    raise RuntimeError('No .NET 10 reference metadata found')
for source in refs[-1].glob('*.dll'):
    shutil.copy2(source, metadata / source.name)
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
subprocess.run(['xcrun', 'clang', '-arch', 'arm64', '-isysroot', sdk, '-mios-simulator-version-min=15.0',
                '-fobjc-arc', str(root / 'HostSmoke.m'), '-L' + str(frameworks), '-lAqwManagedHost',
                '-Wl,-rpath,@executable_path/Frameworks', '-framework', 'UIKit', '-framework', 'Foundation',
                '-o', str(out / 'AqwScriptRuntimeCheck')], check=True)
with (out / 'Info.plist').open('wb') as f:
    plistlib.dump({'CFBundleIdentifier':'com.personal.aqw.scriptcheck', 'CFBundleExecutable':'AqwScriptRuntimeCheck',
                  'CFBundleName':'Native Host Check', 'CFBundlePackageType':'APPL', 'CFBundleVersion':'1',
                  'CFBundleShortVersionString':'1.0', 'MinimumOSVersion':'15.0', 'LSRequiresIPhoneOS':True,
                  'UIDeviceFamily':[1,2], 'UILaunchScreen':{}}, f)
for library in frameworks.glob('*.dylib'):
    subprocess.run(['codesign', '--force', '--sign', '-', str(library)], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', str(out)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(out)], check=True)
print(out, flush=True)
