#!/usr/bin/env python3
"""Exercise automatic startup, official-game import and external asset loading in AIR on the macOS runner."""

import argparse
import json
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    output = root / 'output'
    output.mkdir(exist_ok=True)
    console_path = output / 'loader-smoke.log'
    startup = Path.home() / 'Documents/aqw-startup.log'
    startup.unlink(missing_ok=True)
    command = [str(args.sdk.resolve() / 'bin/adl'), '-profile', 'mobileDevice',
               # ADL expects portrait dimensions, then applies the descriptor's landscape orientation.
               '-screensize', '472x1024:472x1024',
               str(root / 'build/Probe-app.xml'), str(root / 'build'), '--',
               '--smoke-assets=Assets_20260702.swf']
    print('Checking automatic startup and official external assets in AIR.', flush=True)
    with console_path.open('wb') as console:
        process = subprocess.Popen(command, stdout=console, stderr=subprocess.STDOUT)
        try:
            attached_at = None
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                text = console_path.read_text(errors='replace')
                if startup.exists():
                    text += startup.read_text(errors='replace')
                if 'Load failed (' in text or 'SecurityError 2070' in text:
                    raise RuntimeError('The game loading check failed. See loader-smoke.log.')
                if ('Automatic game launch' in text and 'Game client attached' in text
                        and 'External asset check passed:' in text
                        and 'Viewport centred: align=; scale=showAll' in text):
                    if attached_at is None:
                        attached_at = time.monotonic()
                    if time.monotonic() - attached_at >= 8:
                        result = {'automatic_launch': True, 'game_imported': True, 'stage_access_passed': True,
                                  'viewport_centred': True, 'external_assets_loaded': True,
                                  'runtime': 'macOS AIR mobileDevice emulation',
                                  'physical_ios_gameplay_verified': False}
                        (output / 'loader-smoke.json').write_text(json.dumps(result, indent=2) + '\n')
                        subprocess.run(['screencapture', '-x', str(output / 'loader-smoke.png')], check=False)
                        print(json.dumps(result), flush=True)
                        return
                if process.poll() is not None:
                    raise RuntimeError('AIR exited before the game loaded. See loader-smoke.log.')
                time.sleep(1)
            raise RuntimeError('The game did not finish loading within 90 seconds. See loader-smoke.log.')
        finally:
            if startup.exists():
                (output / 'loader-smoke-startup.log').write_bytes(startup.read_bytes())
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()


if __name__ == '__main__':
    main()
