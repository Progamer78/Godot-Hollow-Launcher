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
    # Fresh hosted CoreSimulator services can spend over two minutes mounting
    # runtime images on their first query (runner-images issue 15247).
    return subprocess.check_output(command, timeout=180, **kwargs)

def build(engine, output):
    output.mkdir(parents=True,exist_ok=True)
    with (output / 'simulator-prewarm.log').open('wb') as log:
        prewarm = subprocess.Popen(['xcrun','simctl','list','runtimes','--json'],stdout=log,stderr=subprocess.STDOUT)
    fixture = ROOT / 'runtime_dotnet/game-proof'
    compiled = output / 'Game'
    run(['dotnet','build',fixture / 'HollowDotnetProof.csproj','-c','Release','-o',compiled,
         '-p:BaseIntermediateOutputPath=' + str(output / 'Game-obj') + '/'])
    mono = stage(output / 'runtime', 'iossimulator-arm64', compiled / 'GodotSharp.dll')
    shutil.copytree(ROOT / 'runtime_shared/player_tools', engine / 'modules/player_tools')
    patch(engine, proof=True)
    flags = ['platform=ios','simulator=yes','arch=arm64','target=template_release','module_mono_enabled=yes',
             'cache_path=' + str(ROOT / '.cache/hollow-dotnet-proof-cache'),'cache_limit=2',
             'modules_enabled_by_default=no','module_player_tools_enabled=yes','module_bcdec_enabled=yes','vulkan=no','metal=no','opengl3=no','sdl=no',
             'disable_path_overrides=no','disable_3d=no','debug_symbols=no','optimize=none','lto=none','-j' + str(min(4,os.cpu_count() or 3))]
    run([sys.executable,'-m','SCons',*flags], cwd=engine, timeout=2400, env={**os.environ,'HOLLOW_MONO_NATIVE': mono['native']})
    libraries = list((engine / 'bin').glob('libgodot*.ios.template_release.arm64.simulator.a'))
    if len(libraries) != 1: raise RuntimeError('Expected exactly one experimental Godot simulator library: ' + str(libraries))
    app = output / 'HollowGodotProof.app'; shutil.copytree(mono['bundle'],app,dirs_exist_ok=True)
    frameworks = app / 'Frameworks'; frameworks.mkdir(exist_ok=True)
    for library in app.glob('libSystem.*.dylib'): shutil.move(str(library),frameworks / library.name)
    sdk = capture(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
    command = ['xcrun','--sdk','iphonesimulator','clang++','-target','arm64-apple-ios15.0-simulator','-isysroot',sdk,
               '-fobjc-arc',fixture / 'main.m',*mono['objects'],libraries[0],'-Wl,-ObjC','-Wl,-rpath,@executable_path/Frameworks','-lc++','-lz','-liconv']
    for library in mono['libraries']: command += ['-Wl,-force_load,' + library]
    for framework in ['UIKit','Foundation','AVFoundation','AudioToolbox','CoreAudio','CoreGraphics','CoreMedia','CoreMotion','CoreText','CoreVideo','GameController','QuartzCore','Security','SystemConfiguration','CoreHaptics','UniformTypeIdentifiers','MobileCoreServices']:
        command += ['-framework',framework]
    command += ['-o',app / 'HollowGodotProof']; run(command)
    (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.godotplayer.dotnetgameproof','CFBundleExecutable':'HollowGodotProof',
        'CFBundleName':'Godot CSharp Proof','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0',
        'MinimumOSVersion':'15.0','UIDeviceFamily':[1],'UILaunchScreen':{}}))
    for library in frameworks.glob('*.dylib'): run(['codesign','--force','--sign','-',library])
    run(['codesign','--force','--sign','-',app])
    try: prewarm.wait(timeout=180)
    except subprocess.TimeoutExpired:
        prewarm.terminate(); prewarm.wait(timeout=30)
        print('Simulator prewarming timed out; execution will retry with a bounded query.',flush=True)

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
    # The engine targets iOS 15. Prefer the oldest installed supported runtime
    # for the headless ABI test; newer simulator images have heavier migrations.
    runtime=sorted([r for r in runtimes if r.get('isAvailable') and '.iOS-' in r['identifier'] and int(r['version'].split('.')[0]) >= 15],key=lambda r:tuple(map(int,r['version'].split('.'))))[0]['identifier']
    devices=json.loads(capture(['xcrun','simctl','list','devices','available','--json'],text=True))['devices'][runtime]
    phone=next(d for d in devices if d['name'].startswith('iPhone') and d.get('deviceTypeIdentifier'))
    device=capture(['xcrun','simctl','create','HollowGodotCSharp',phone['deviceTypeIdentifier'],runtime],text=True).strip()
    container=None
    try:
        run(['xcrun','simctl','boot',device]);run(['xcrun','simctl','bootstatus',device,'-b'],timeout=300)
        run(['xcrun','simctl','install',device,app],timeout=300)
        container=Path(capture(['xcrun','simctl','get_app_container',device,'org.godotplayer.dotnetgameproof','data'],text=True).strip())
        documents=container / 'Documents'; documents.mkdir(exist_ok=True);shutil.copyfile(pack,documents / 'game.pck')
        run(['xcrun','simctl','launch','--stdout=' + str(output / 'stdout.log'),'--stderr=' + str(output / 'stderr.log'),device,'org.godotplayer.dotnetgameproof'],timeout=180)
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
