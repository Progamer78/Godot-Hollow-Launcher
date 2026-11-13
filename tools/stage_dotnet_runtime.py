"""Stage signed-build Mono components; never accepts a game runtime package."""
from pathlib import Path
import argparse
import json
import os
import shutil
import subprocess
import urllib.request
import zipfile
from prove_dotnet_ios import VERSION, run

def package(name, output):
    archive = output / (name + '.nupkg')
    if not archive.is_file():
        with urllib.request.urlopen(f'https://api.nuget.org/v3-flatcontainer/{name}/{VERSION}/{name}.{VERSION}.nupkg', timeout=90) as source, archive.open('wb') as target:
            shutil.copyfileobj(source, target)
    root = output / name
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            if not (root / info.filename).resolve().is_relative_to(root.resolve()): raise RuntimeError('Unsafe runtime ZIP path')
        z.extractall(root)
    return root

def stage(output, rid, api):
    output.mkdir(parents=True, exist_ok=True)
    runtime = package('microsoft.netcore.app.runtime.mono.' + rid, output)
    native = runtime / 'runtimes' / rid / 'native'
    bundle = output / 'bundle'; managed = bundle / 'Managed'; managed.mkdir(parents=True, exist_ok=True)
    for folder in [runtime / 'runtimes' / rid / 'lib/net10.0', native]:
        for dll in folder.glob('*.dll'): shutil.copyfile(dll, managed / dll.name)
    shutil.copyfile(api, managed / 'GodotSharp.dll')
    for dylib in native.glob('libSystem.*.dylib'): shutil.copyfile(dylib, bundle / dylib.name)
    for name in ['LICENSE.TXT', 'THIRD-PARTY-NOTICES.TXT']:
        source = next(runtime.rglob(name), None)
        if source: shutil.copyfile(source, bundle / ('Mono-' + name))
    compiler_root = package('microsoft.netcore.app.runtime.aot.osx-arm64.cross.' + rid, output)
    compiler = next(compiler_root.rglob('mono-aot-cross')); compiler.chmod(0o755)
    sdk = 'iphonesimulator' if 'simulator' in rid else 'iphoneos'
    triple = 'arm64-apple-ios15.0' + ('-simulator' if 'simulator' in rid else '')
    sdk_path = subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'], text=True).strip()
    objects = []
    for name in ['System.Private.CoreLib', 'GodotSharp']:
        asm = output / (name + '.s'); obj = asm.with_suffix('.o')
        run([compiler, '--aot=static,asmonly,interp,outfile=' + str(asm), managed / (name + '.dll')], env={**os.environ, 'MONO_PATH': str(managed)})
        run(['xcrun','--sdk',sdk,'clang','-target',triple,'-isysroot',sdk_path,'-c',asm,'-o',obj]); objects.append(str(obj))
    libraries = [native / 'libmonosgen-2.0.a', native / 'libmono-component-marshal-ilgen-static.a']
    libraries += [native / ('libmono-component-' + name + '-stub-static.a') for name in ['debugger','diagnostics_tracing','hot_reload']]
    result = {'version': VERSION, 'rid': rid, 'native':str(native), 'bundle':str(bundle), 'objects':objects, 'libraries':list(map(str,libraries))}
    (output / 'stage.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    return result

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('output',type=Path);parser.add_argument('api',type=Path);parser.add_argument('--rid',default='iossimulator-arm64')
    args=parser.parse_args(); stage(args.output.resolve(),args.rid,args.api.resolve())
