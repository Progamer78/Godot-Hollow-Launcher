"""Link and package only the trusted Mono runtime staged during the IPA build."""
from pathlib import Path
import argparse
import json
import plistlib
import shutil
import subprocess

VERSION = '10.0.15'
NATIVE_LIBRARIES = (
    'libSystem.Globalization.Native.dylib',
    'libSystem.IO.Compression.Native.dylib',
    'libSystem.Native.dylib',
    'libSystem.Net.Security.Native.dylib',
    'libSystem.Security.Cryptography.Native.Apple.dylib',
)


def read_stage(path):
    stage = json.loads(path.read_text(encoding='utf-8'))
    if stage['version'] != VERSION or stage['rid'] != 'ios-arm64' or stage['godot_version'] != '4.7.2':
        raise RuntimeError('The device runtime does not match this launcher build')
    bundle = Path(stage['bundle'])
    for name in ['System.Private.CoreLib.dll', 'GodotSharp.dll', 'Hollow.MetadataBridge.dll']:
        if not (bundle / 'Managed' / name).is_file():
            raise RuntimeError('Missing trusted managed runtime component: ' + name)
    for name in [*NATIVE_LIBRARIES, 'Mono-LICENSE.TXT', 'Mono-THIRD-PARTY-NOTICES.TXT']:
        if not (bundle / name).is_file():
            raise RuntimeError('Missing trusted runtime component: ' + name)
    return stage, bundle


def prepare(export, stage_path):
    stage, _ = read_stage(stage_path)
    library = export / 'HollowDotnet/libhollow-mono.a'
    library.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(['xcrun', 'libtool', '-static', '-o', str(library),
                    *stage['objects'], *stage['libraries']], check=True, timeout=180)
    # Keep the working Xcode export's engine/framework settings. This one
    # archive includes Mono's runtime, component registrations and AOT support.
    (export / 'dotnet-link.xcconfig').write_text(
        'OTHER_LDFLAGS = $(inherited) -force_load "$(SRCROOT)/HollowDotnet/libhollow-mono.a" -liconv -lz\n'
        'LD_RUNPATH_SEARCH_PATHS = $(inherited) @executable_path/Frameworks\n', encoding='utf-8')
    info = export / 'player/player-Info.plist'
    metadata = plistlib.loads(info.read_bytes())
    metadata['HollowDotnetRuntime'] = VERSION
    metadata['HollowMetadataCompatibility'] = stage['metadata_compatibility']
    info.write_bytes(plistlib.dumps(metadata))


def install(payload, stage_path):
    _, bundle = read_stage(stage_path)
    apps = list(payload.glob('*.app'))
    if len(apps) != 1:
        raise RuntimeError('Expected exactly one packaged launcher app')
    app = apps[0]
    metadata = plistlib.loads((app / 'Info.plist').read_bytes())
    if metadata.get('HollowDotnetRuntime') != VERSION:
        raise RuntimeError('The launcher was not built with the matching managed runtime')
    if (app / 'Managed').exists():
        raise RuntimeError('The app already contains a managed runtime')
    shutil.copytree(bundle / 'Managed', app / 'Managed')
    frameworks = app / 'Frameworks'
    frameworks.mkdir(exist_ok=True)
    for name in NATIVE_LIBRARIES:
        shutil.copyfile(bundle / name, frameworks / name)
    for name in ['Mono-LICENSE.TXT', 'Mono-THIRD-PARTY-NOTICES.TXT']:
        shutil.copyfile(bundle / name, app / name)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=['prepare', 'install'])
    parser.add_argument('target', type=Path)
    parser.add_argument('stage', type=Path)
    args = parser.parse_args()
    (prepare if args.phase == 'prepare' else install)(args.target.resolve(), args.stage.resolve())
