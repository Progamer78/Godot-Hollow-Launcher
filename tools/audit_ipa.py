"""Check the packaged device IPA before calling the build successful."""
from pathlib import Path
import argparse
import json
import plistlib
import struct
import zipfile

def audit(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        apps = [name for name in names if name.startswith('Payload/') and name.count('/') == 2 and name.endswith('.app/Info.plist')]
        if len(apps) != 1: raise RuntimeError('IPA must contain exactly one app')
        app = apps[0].removesuffix('Info.plist')
        info = plistlib.loads(archive.read(app + 'Info.plist'))
        def image(prefix, metadata, kind):
            executable = metadata['CFBundleExecutable']
            if '/' in executable or '\\' in executable: raise RuntimeError('Unsafe bundle executable')
            data = archive.read(prefix + executable)
            if len(data) < 32 or struct.unpack_from('<III', data) != (0xfeedfacf, 0x100000c, 0):
                # ARM64 subtype can include ABI capability bits on newer tools.
                if len(data) < 32 or struct.unpack_from('<II', data) != (0xfeedfacf, 0x100000c):
                    raise RuntimeError('Expected a thin ARM64 device image: ' + executable)
            if struct.unpack_from('<I', data, 12)[0] != kind: raise RuntimeError('Wrong Mach-O image kind: ' + executable)
            if float(metadata.get('MinimumOSVersion','0').split('.')[0]) < 15: raise RuntimeError('Bundle deployment target must be iOS 15 or later')
            return len(data)
        host = image(app, info, 2)
        framework = app + 'Frameworks/Godot3Runtime.framework/'
        guest = image(framework, plistlib.loads(archive.read(framework + 'Info.plist')), 6)
        for notice in ['LICENSE.txt', 'COPYRIGHT.txt']:
            if len(archive.read(framework + notice)) < 10: raise RuntimeError('Missing Godot 3 notice')
        dotnet = info.get('HollowDotnetRuntime')
        if dotnet:
            if dotnet != '10.0.15': raise RuntimeError('Unexpected bundled managed runtime version')
            for assembly in ['System.Private.CoreLib.dll', 'GodotSharp.dll']:
                data = archive.read(app + 'Managed/' + assembly)
                if len(data) < 128 or data[:2] != b'MZ': raise RuntimeError('Invalid bundled managed assembly: ' + assembly)
            for component in ['Globalization.Native', 'IO.Compression.Native', 'Native', 'Net.Security.Native', 'Security.Cryptography.Native.Apple']:
                library = 'libSystem.' + component + '.dylib'
                image(app + 'Frameworks/', {'CFBundleExecutable':library, 'MinimumOSVersion':'15.0'}, 6)
            for notice in ['Mono-LICENSE.TXT', 'Mono-THIRD-PARTY-NOTICES.TXT']:
                if len(archive.read(app + notice)) < 10: raise RuntimeError('Missing Mono runtime notice')
            if b'HOLLOW_DOTNET:' not in archive.read(app + info['CFBundleExecutable']):
                raise RuntimeError('Managed resources were packaged without the native interpreter host')
        bundled_packs = [name for name in names if name.startswith(app) and name.lower().endswith('.pck') and archive.getinfo(name).file_size > 0]
        if bundled_packs: raise RuntimeError('Unexpected bundled game PCK; launcher must select the imported main project')
        if archive.testzip() is not None: raise RuntimeError('IPA CRC check failed')
        return {'app_arm64_bytes':host,'godot3_arm64_bytes':guest,'dotnet_runtime':dotnet or 'none','bundled_games':0,'package_checks':'passed','device_execution':'not established by package checks'}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa',type=Path)
    parser.add_argument('--report',type=Path,default=Path('build/ipa-audit.json'))
    args=parser.parse_args(); result=audit(args.ipa)
    args.report.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8'); print(json.dumps(result,indent=2))
