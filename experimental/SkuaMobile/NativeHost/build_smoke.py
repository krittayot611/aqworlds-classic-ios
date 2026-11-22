"""Package the Mono library in a native simulator app; never builds a game IPA."""
from pathlib import Path
import plistlib
import shutil
import subprocess
from map_payload import stage_managed

root = Path(__file__).resolve().parent
out = root / 'smoke/AqwScriptRuntimeCheck.app'
frameworks = out / 'Frameworks'
lib = stage_managed('iossimulator-arm64', frameworks, out / 'metadata')
for source in lib.parent.glob('*.dylib'):
    shutil.copy2(source, frameworks / source.name)
subprocess.run(['install_name_tool', '-id', '@rpath/libAqwManagedHost.dylib', str(frameworks / lib.name)], check=True)
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
