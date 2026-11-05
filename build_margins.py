#!/usr/bin/env python3
"""Build the iOS gutter-background native extension and its desktop fallback."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile


def run(*args):
    subprocess.run([str(a) for a in args], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', required=True, type=Path)
    args = parser.parse_args()
    sdk = args.sdk.resolve()
    root = Path(__file__).resolve().parent
    build = root / 'build'
    build.mkdir(exist_ok=True)
    swc = build / 'Margins.swc'
    run('java', '-Dflexlib=' + str(sdk / 'frameworks'), '-jar', sdk / 'lib/compc-cli.jar',
        '+configname=air', '-swf-version=14', '-source-path=' + str(root / 'native'),
        '-include-classes=NativeMargins', '-output=' + str(swc))
    extension_dir = build / 'extensions'
    extension_dir.mkdir(exist_ok=True)
    default = build / 'margin-default'
    default.mkdir(exist_ok=True)
    with zipfile.ZipFile(swc) as z:
        (default / 'library.swf').write_bytes(z.read('library.swf'))
    command = ['java', '-jar', str(sdk / 'lib/adt.jar'), '-package', '-target', 'ane',
               str(extension_dir / 'AQWMargins.ane'), str(root / 'native/extension.xml'), '-swc', str(swc)]
    # Linux can compile the ActionScript surface; native compilation runs on macOS.
    if sys.platform != 'darwin':
        return
    for platform, sdk_name, target in [('iPhone-ARM', 'iphoneos', 'arm64-apple-ios12.0'),
                                       ('iPhone-x86', 'iphonesimulator', 'x86_64-apple-ios12.0-simulator')]:
        directory = build / ('margin-' + platform)
        directory.mkdir(exist_ok=True)
        shutil.copy2(default / 'library.swf', directory / 'library.swf')
        system_sdk = subprocess.check_output(['xcrun', '--sdk', sdk_name, '--show-sdk-path'], text=True).strip()
        run('xcrun', 'clang', '-target', target, '-isysroot', system_sdk,
            '-fobjc-arc', '-fmodules', '-I', sdk / 'include', '-c', root / 'native/MarginBackdrop.m',
            '-o', directory / 'Margins.o')
        run('xcrun', 'libtool', '-static', '-o', directory / 'libAQWMargins.a', directory / 'Margins.o')
        if platform == 'iPhone-x86':
            # Current AIR simulator runtimes contain both Intel and Apple Silicon slices.
            run('xcrun', 'clang', '-target', 'arm64-apple-ios14.0-simulator', '-isysroot', system_sdk,
                '-fobjc-arc', '-fmodules', '-I', sdk / 'include', '-c', root / 'native/MarginBackdrop.m',
                '-o', directory / 'Margins-arm64.o')
            run('xcrun', 'libtool', '-static', '-o', directory / 'libAQWMargins-arm64.a', directory / 'Margins-arm64.o')
            run('xcrun', 'lipo', '-create', directory / 'libAQWMargins.a', directory / 'libAQWMargins-arm64.a',
                '-output', directory / 'libAQWMargins-universal.a')
            (directory / 'libAQWMargins-universal.a').replace(directory / 'libAQWMargins.a')
            run('xcrun', 'lipo', directory / 'libAQWMargins.a', '-verify_arch', 'x86_64', 'arm64')
        command += ['-platform', platform, '-platformoptions', str(root / 'native/platform-ios.xml'), '-C', str(directory), 'library.swf', 'libAQWMargins.a']
    command += ['-platform', 'default', '-C', str(default), 'library.swf']
    run(*command)
    unpacked = build / 'unpacked-extensions' / 'AQWMargins.ane'
    unpacked.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(extension_dir / 'AQWMargins.ane') as z:
        z.extractall(unpacked)
    print('Native gutter background compiled for arm64 iOS and universal x86_64/arm64 iOS Simulator.')


if __name__ == '__main__':
    main()
