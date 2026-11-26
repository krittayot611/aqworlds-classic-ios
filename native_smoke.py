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
from cloud_build import prepare_packaging_identity


def map_observations(log, expected):
    if 'MAP_ERROR ' in log or 'Map reader unavailable:' in log:
        raise RuntimeError('Map reader failed:\n' + log[-3000:])
    live = [json.loads(line.split('MAP_LIVE ', 1)[1]) for line in log.splitlines() if 'MAP_LIVE ' in line]
    samples = [json.loads(line.split('MAP_SAMPLE ', 1)[1]) for line in log.splitlines() if 'MAP_SAMPLE ' in line]
    if len(samples) < 3 or any(marker not in log for marker in ('BOT_CHECK passed:', 'PROFILE_CHECK passed:', 'RULE_CHECK passed:', 'STEP_CHECK passed:', 'MAP_TOOLS_CHECK passed:', 'TIMING_CHECK passed:')):
        return None
    if len(live) != 1 or (live[0] is not None and not isinstance(live[0], str)) or samples != [*expected, None]:
        raise RuntimeError(f'Incorrect map readings: live={live!r}, samples={samples!r}')
    return {'client_attached': True, 'client_map_at_startup': live[0], 'fixture_readings': samples,
            'bot_drawer_layout_and_controls': True, 'skill_rotation_fixture': True,
            'account_bags_profile_storage_and_editor': True, 'conditional_skill_fixture': True,
            'right_edge_phone_and_tablet': True, 'inclusive_resource_and_party_rules': True, 'named_aura_stacks': True,
            'cooldown_switch_and_new_step_defaults': True, 'swipe_delete_skill_rows': True, 'neutral_stop_controls': True,
            'target_reset_and_skill_timing': True, 'bookmark_pad_correction': True,
            'independent_map_controls': True, 'one_tap_remote_spawn_fixture': True,
            'online_map_transition_tested': False, 'physical_device_tested': False}


def run(*command, **kwargs):
    return subprocess.run([str(c) for c in command], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', required=True, type=Path)
    parser.add_argument('--map-runtime', type=Path, help='Run the AIR/C# map check in the game app')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    sdk = args.sdk.resolve()
    output = root / 'output/native'
    output.mkdir(parents=True, exist_ok=True)
    platform_sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
    groups = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True))['devices']
    choices = [d for group in groups.values() for d in group if d.get('isAvailable') and d['name'].startswith('iPhone')]
    requested = os.environ.get('AQW_SIMULATOR_UDID')
    if args.map_runtime and not requested:
        from experimental.SkuaMobile.run_ios_check import choose_phone
        runtimes = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'runtimes', '-j'], text=True))
        sdk_version = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], text=True).strip()
        requested = choose_phone(groups, runtimes['runtimes'], sdk_version)['udid']
    if requested: choices = [d for d in choices if d['udid'] == requested]
    if not choices: raise RuntimeError('The requested iPhone simulator is not available.')
    choices.sort(key=lambda d: (d['state'] != 'Booted', d['name']))
    devices = [choices[0]]
    if args.map_runtime:
        runtime = next(key for key, names in groups.items() if any(d['udid'] == choices[0]['udid'] for d in names))
        tablets = [d for d in groups[runtime] if d.get('isAvailable') and d['name'].startswith('iPad')]
        if not tablets:
            raise RuntimeError('No iPad is available on the selected iOS simulator runtime.')
        devices.append(min(tablets, key=lambda d: (d['state'] != 'Booted', '11-inch' not in d['name'], d['name'])))
    with tempfile.TemporaryDirectory(prefix='aqw-margins-simulator-') as temporary:
        directory = Path(temporary)
        password = secrets.token_urlsafe(24)
        if os.environ.get('GITHUB_ACTIONS'): print('::add-mask::' + password, flush=True)
        p12, profile = prepare_packaging_identity(directory, password)
        expected = None
        if args.map_runtime:
            expected = ['map-' + secrets.token_hex(6), 'map-' + secrets.token_hex(6)]
            smoke_config = directory / 'aqw-map-check.json'
            smoke_config.write_text(json.dumps(expected), encoding='ascii')
        else:
            smoke_config = directory / 'aqw-simulator-smoke.txt'
            smoke_config.write_text('Assets_20260702.swf', encoding='ascii')
        ipa = directory / 'simulator.ipa'
        run('java', '-Xmx2048m', '-jar', sdk / 'lib/adt.jar', '-cfg', root / 'adt.cfg',
            '-package', '-target', 'ipa-test-interpreter-simulator',
            '-storetype', 'pkcs12', '-keystore', p12,
            '-storepass', password, '-provisioning-profile', profile, ipa, root / 'build/Probe-app.xml',
            '-platformsdk', platform_sdk, '-extdir', root / 'build/extensions', '-C', root / 'build', 'Probe.swf', 'icons', 'Background.jpg',
            '-C', directory, smoke_config.name)
        run('ditto', '-x', '-k', ipa, directory / 'unpacked')
        app, = (directory / 'unpacked/Payload').glob('*.app')
        info = plistlib.loads((app / 'Info.plist').read_bytes()); bundle_id = info['CFBundleIdentifier']
        (app / 'embedded.mobileprovision').unlink(missing_ok=True)
        if args.map_runtime:
            from experimental.SkuaMobile.NativeHost.map_payload import embed
            embed(args.map_runtime, app, simulator=True)
        run('codesign', '--force', '--sign', '-', app)
        for device in devices:
            is_tablet = device['name'].startswith('iPad')
            folder = output / 'ipad' if is_tablet else output
            folder.mkdir(parents=True, exist_ok=True)
            try:
                check_device(device, folder, app, bundle_id, expected)
            finally:
                if args.map_runtime and device['state'] != 'Booted':
                    subprocess.run(['xcrun', 'simctl', 'shutdown', device['udid']], check=False, timeout=90)


def check_device(device, output, app, bundle_id, expected):
    udid = device['udid']
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
    run('xcrun', 'simctl', 'install', udid, app)
    data = Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', udid, bundle_id, 'data'], text=True).strip())
    marker = data / 'Documents/aqw-startup.log'; marker.unlink(missing_ok=True)
    run('xcrun', 'simctl', 'launch', udid, bundle_id)
    try:
        deadline = time.monotonic() + (180 if expected else 100)
        while time.monotonic() < deadline:
            text = marker.read_text() if marker.exists() else ''
            if 'Load failed (' in text: raise RuntimeError('Game startup failed in iOS Simulator:\n' + text[-2400:])
            if expected:
                evidence = map_observations(text, expected)
                if evidence:
                    evidence['device'] = device['name']
                    for name in ('condition-editor', 'skill-options', 'running-controls', 'rail-phone', 'rail-tablet',
                                 'set-editor', 'aura-editor', 'mobs', 'bookmarks'):
                        preview = data / f'Documents/aqw-{name}.png'
                        (output / f'{name}.png').write_bytes(preview.read_bytes())
                    (output / 'map-readings.json').write_text(json.dumps(evidence, indent=2) + '\n')
                    print(json.dumps(evidence), flush=True)
                    return
                time.sleep(1)
                continue
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
        raise RuntimeError('The requested verification did not finish in iOS Simulator:\n' + text[-3000:])
    finally:
        if marker.exists(): (output / 'startup.log').write_bytes(marker.read_bytes())
        try:
            subprocess.run(['xcrun', 'simctl', 'io', udid, 'screenshot', output / 'native-background.png'],
                           check=False, timeout=30)
        except subprocess.TimeoutExpired:
            pass
        subprocess.run(['xcrun', 'simctl', 'terminate', udid, bundle_id], check=False, timeout=30)


if __name__ == '__main__':
    main()
