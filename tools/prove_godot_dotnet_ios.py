"""Execute an independently supplied original C# scene in real Godot on iOS Simulator."""
from pathlib import Path
import argparse
import json
import os
import plistlib
import shutil
import subprocess
import sys
import time
from prove_dotnet_ios import run
from stage_dotnet_runtime import stage
from patch_dotnet import patch

ROOT = Path(__file__).resolve().parents[1]

def capture(command, **kwargs):
    return subprocess.check_output(command, timeout=60, **kwargs)

def build(engine, output):
    output.mkdir(parents=True,exist_ok=True)
    fixture = ROOT / 'runtime_dotnet/game-proof'
    compiled = output / 'Game'
    run(['dotnet','build',fixture / 'HollowDotnetProof.csproj','-c','Release','-o',compiled,
         '-p:BaseIntermediateOutputPath=' + str(output / 'Game-obj') + '/'])
    mono = stage(output / 'runtime', 'iossimulator-arm64', compiled / 'GodotSharp.dll')
    patch(engine, proof=True)
    flags = ['platform=ios','simulator=yes','arch=arm64','target=template_release','module_mono_enabled=yes',
             'modules_enabled_by_default=no','vulkan=no','metal=no','opengl3=no','sdl=no',
             'disable_3d=yes','debug_symbols=no','optimize=none','lto=none','-j8']
    run([sys.executable,'-m','SCons',*flags], cwd=engine, timeout=2400, env={**os.environ,'HOLLOW_MONO_NATIVE': mono['native']})
    libraries = list((engine / 'bin').glob('libgodot*.ios.template_release.arm64.simulator.a'))
    if len(libraries) != 1: raise RuntimeError('Expected exactly one experimental Godot simulator library: ' + str(libraries))
    app = output / 'HollowGodotProof.app'; shutil.copytree(mono['bundle'],app,dirs_exist_ok=True)
    sdk = capture(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
    command = ['xcrun','--sdk','iphonesimulator','clang++','-target','arm64-apple-ios15.0-simulator','-isysroot',sdk,
               '-fobjc-arc',fixture / 'main.m',*mono['objects'],libraries[0],'-Wl,-ObjC','-lc++','-lz','-liconv']
    for library in mono['libraries']: command += ['-Wl,-force_load,' + library]
    for framework in ['UIKit','Foundation','AVFoundation','AudioToolbox','CoreAudio','CoreGraphics','CoreMedia','CoreMotion','CoreText','CoreVideo','GameController','QuartzCore','Security','SystemConfiguration','CoreHaptics','UniformTypeIdentifiers','MobileCoreServices']:
        command += ['-framework',framework]
    command += ['-o',app / 'HollowGodotProof']; run(command)
    (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.godotplayer.dotnetgameproof','CFBundleExecutable':'HollowGodotProof',
        'CFBundleName':'Godot CSharp Proof','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0',
        'MinimumOSVersion':'15.0','UIDeviceFamily':[1],'UILaunchScreen':{}}))
    for library in app.glob('*.dylib'): run(['codesign','--force','--sign','-',library])
    run(['codesign','--force','--sign','-',app])

def execute(output):
    fixture = ROOT / 'runtime_dotnet/game-proof'
    compiled = output / 'Game'
    app = output / 'HollowGodotProof.app'
    # Built after the native app and never linked/AOT-compiled into it.
    pack = output / 'independent-csharp.pck'
    run(['godot','--headless','--path',fixture,'--script','pack.gd','--',pack,compiled / 'HollowDotnetProof.dll'])
    inspector = output / 'dotnet-import-tests'
    run(['swiftc','-swift-version','5',ROOT / 'ios/PCKInspector.swift',ROOT / 'tests/dotnet/main.swift','-o',inspector])
    run([inspector,pack])
    runtimes=json.loads(capture(['xcrun','simctl','list','runtimes','--json'],text=True))['runtimes']
    runtime=sorted([r for r in runtimes if r.get('isAvailable') and '.iOS-' in r['identifier']],key=lambda r:tuple(map(int,r['version'].split('.'))))[-1]['identifier']
    devices=json.loads(capture(['xcrun','simctl','list','devices','available','--json'],text=True))['devices'][runtime]
    phone=next(d for d in devices if d['name'].startswith('iPhone') and d.get('deviceTypeIdentifier'))
    device=capture(['xcrun','simctl','create','HollowGodotCSharp',phone['deviceTypeIdentifier'],runtime],text=True).strip()
    container=None
    try:
        run(['xcrun','simctl','boot',device]);run(['xcrun','simctl','bootstatus',device,'-b'],timeout=600)
        run(['xcrun','simctl','install',device,app])
        container=Path(capture(['xcrun','simctl','get_app_container',device,'org.godotplayer.dotnetgameproof','data'],text=True).strip())
        documents=container / 'Documents'; documents.mkdir(exist_ok=True);shutil.copyfile(pack,documents / 'game.pck')
        run(['xcrun','simctl','launch','--stdout=' + str(output / 'stdout.log'),'--stderr=' + str(output / 'stderr.log'),device,'org.godotplayer.dotnetgameproof'])
        complete=documents / 'native-result.json';deadline=time.monotonic()+120
        while not complete.is_file() and time.monotonic()<deadline:time.sleep(0.25)
        if not complete.is_file():raise RuntimeError('Godot C# game did not complete; see native logs')
        shutil.copyfile(complete,output / 'native-result.json')
        native_result=json.loads(complete.read_text(encoding='utf-8'))
        if native_result.get('native_result')!=0:raise RuntimeError('Godot startup/loop failed: ' + str(native_result))
        results=list(container.rglob('dotnet-proof.json'))
        if len(results)!=1:raise RuntimeError('Original game did not write its gameplay proof record')
        result=json.loads(results[0].read_text(encoding='utf-8'));result['scope']='Real Godot headless scene execution on ARM64 iOS Simulator; physical device and launcher integration untested'
        (output / 'results.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
        if not result.get('passed') or not result.get('godot_game_execution') or result.get('frames')!=8:raise RuntimeError('Original C# game reported a failed assertion')
    finally:
        if container:
            for source in (container / 'Documents').glob('*.log'):shutil.copyfile(source,output / source.name)
        for source in (Path.home() / 'Library/Logs/DiagnosticReports').glob('HollowGodotProof*'):shutil.copyfile(source,output / ('crash-' + source.name))
        from check_input_ui import cleanup_device
        cleanup_device(device)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('engine',type=Path);parser.add_argument('output',type=Path)
    parser.add_argument('--phase',choices=['build','run','all'],default='all')
    args=parser.parse_args()
    if args.phase in ['build','all']: build(args.engine.resolve(),args.output.resolve())
    if args.phase in ['run','all']: execute(args.output.resolve())
