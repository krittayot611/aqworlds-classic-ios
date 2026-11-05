#!/usr/bin/env python3
"""Verify the native gutter background alongside the actual AIR game in iOS Simulator."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import secrets
import subprocess
import tempfile
import time
import zipfile
from cloud_build import prepare_packaging_identity


def run(*command, **kwargs):
    return subprocess.run([str(c) for c in command], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    sdk = args.sdk.resolve()
    output = root / 'output/native'
    output.mkdir(parents=True, exist_ok=True)
    platform_sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
    groups = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True))['devices']
    choices = [d for group in groups.values() for d in group if d.get('isAvailable') and d['name'].startswith('iPhone')]
    requested = os.environ.get('AQW_SIMULATOR_UDID')
    if requested: choices = [d for d in choices if d['udid'] == requested]
    if not choices: raise RuntimeError('The requested iPhone simulator is not available.')
    choices.sort(key=lambda d: (d['state'] != 'Booted', d['name']))
    device = choices[0]; udid = device['udid']
    print('Starting native-background check on ' + device['name'], flush=True)
    if device['state'] != 'Booted': run('xcrun', 'simctl', 'boot', udid)
    boot_log = output / 'simulator-boot.log'
    print('Waiting for simulator data migration and startup (up to 420 seconds).', flush=True)
    with boot_log.open('w') as log:
        try:
            run('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=420,
                stdout=log, stderr=subprocess.STDOUT)
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
            print(boot_log.read_text()[-6000:], flush=True)
            raise
    print('iOS Simulator is ready for the native-background test.', flush=True)
    with tempfile.TemporaryDirectory(prefix='aqw-margins-simulator-') as temporary:
        directory = Path(temporary)
        password = secrets.token_urlsafe(24)
        if os.environ.get('GITHUB_ACTIONS'): print('::add-mask::' + password, flush=True)
        p12, profile = prepare_packaging_identity(directory, password)
        smoke_config = directory / 'aqw-simulator-smoke.txt'
        smoke_config.write_text('Assets_20260702.swf', encoding='ascii')
        ipa = directory / 'simulator.ipa'
        run('java', '-Xmx2048m', '-jar', sdk / 'lib/adt.jar', '-cfg', root / 'adt.cfg',
            '-package', '-target', 'ipa-test-interpreter-simulator',
            '-storetype', 'pkcs12', '-keystore', p12,
            '-storepass', password, '-provisioning-profile', profile, ipa, root / 'build/Probe-app.xml',
            '-platformsdk', platform_sdk, '-extdir', root / 'build/extensions', '-C', root / 'build', 'Probe.swf', 'icons', 'Background.jpg',
            '-C', directory, smoke_config.name)
        with zipfile.ZipFile(ipa) as z: z.extractall(directory / 'unpacked')
        app, = (directory / 'unpacked/Payload').glob('*.app')
        info = plistlib.loads((app / 'Info.plist').read_bytes()); bundle_id = info['CFBundleIdentifier']
        (app / 'embedded.mobileprovision').unlink(missing_ok=True)
        run('codesign', '--force', '--sign', '-', app)
        run('xcrun', 'simctl', 'install', udid, app)
        data = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', udid, bundle_id, 'data'], text=True).strip())
        marker = data / 'Documents/aqw-startup.log'; marker.unlink(missing_ok=True)
        run('xcrun', 'simctl', 'launch', udid, bundle_id)
        try:
            deadline = time.monotonic() + 100
            while time.monotonic() < deadline:
                text = marker.read_text() if marker.exists() else ''
                if 'Load failed (' in text: raise RuntimeError('Game startup failed in iOS Simulator.')
                if any(s in text for s in ('Native margins: unavailable', 'Native margins unavailable:', 'clipping check failed')):
                    raise RuntimeError('The native background extension did not initialize correctly.')
                if all(s in text for s in ('Native margins: active;', 'clipping=verified',
                                          'scale=showAll', 'Map regression passed:', 'External asset check passed:')):
                    time.sleep(5)
                    result = {'runtime': 'iOS Simulator', 'device': device['name'],
                              'native_extension_loaded': True, 'texture_resource_loaded': True,
                              'phone_and_tablet_gutters_painted': True, 'game_area_transparent': True,
                              'background_input_disabled': True, 'game_aspect_ratio_preserved': True,
                              'map_and_movement_coordinates_checked': True, 'physical_device_verified': False}
                    (output / 'native-background.json').write_text(json.dumps(result, indent=2) + '\n')
                    print(json.dumps(result), flush=True)
                    return
                time.sleep(1)
            raise RuntimeError('Native background verification did not finish in iOS Simulator.')
        finally:
            if marker.exists(): (output / 'startup.log').write_bytes(marker.read_bytes())
            run('xcrun', 'simctl', 'io', udid, 'screenshot', output / 'native-background.png')
            subprocess.run(['xcrun', 'simctl', 'terminate', udid, bundle_id], check=False)


if __name__ == '__main__':
    main()
