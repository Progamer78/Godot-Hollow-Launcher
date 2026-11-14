"""Reproduce the renderer-override failure using real iOS OpenGL contexts."""
from pathlib import Path
import argparse
import json
import platform
import plistlib
import subprocess
import time
from patch_ios_graphics import patch
from check_input_ui import cleanup_device

ROOT = Path(__file__).resolve().parents[1]


def run(engine, output):
    output.mkdir(parents=True, exist_ok=True)
    relative = Path('platform/ios/display_layer_ios.mm')
    original = (engine / relative).read_text(encoding='utf-8')
    # Compile both the unmodified and patched implementation. Only the heavy
    # engine headers are replaced with the saved Forward+ setting and FBO slot;
    # context creation, framebuffer allocation and Apple GL calls are original.
    staging = output / 'engine'
    target = staging / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(original, encoding='utf-8')
    patch(staging)
    fixed = target.read_text(encoding='utf-8')
    shared = '''#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#include <string>
#define GLOBAL_GET(name) std::string("forward_plus")
namespace GLES3 { struct TextureStorage { static inline GLuint system_fbo = 0; }; }
'''
    sources = []
    for name, text in [('HollowBaselineGL', original), ('HollowFixedGL', fixed)]:
        start = text.index('@implementation GDTOpenGLLayer')
        end = text.index('\n@end', start) + len('\n@end')
        declaration = f'@interface {name} : CAEAGLLayer\n@end\n'
        source = output / (name + '.mm')
        source.write_text(shared + declaration + text[start:end].replace('GDTOpenGLLayer', name), encoding='utf-8')
        sources.append(source)
    arch = 'arm64' if platform.machine() == 'arm64' else 'x86_64'
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
    app = output / 'GraphicsSmoke.app'
    app.mkdir(exist_ok=True)
    bundle = 'org.godotplayer.graphicssmoke'
    (app / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': bundle, 'CFBundleExecutable': 'GraphicsSmoke', 'CFBundleName': 'Graphics Smoke',
        'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0',
        'MinimumOSVersion': '15.0', 'LSRequiresIPhoneOS': True, 'UIDeviceFamily': [1],
        'CFBundleSupportedPlatforms': ['iPhoneSimulator'], 'UILaunchScreen': {},
    }))
    subprocess.run(['xcrun', '--sdk', 'iphonesimulator', 'clang++', '-std=c++17', '-fobjc-arc',
                    '-Wno-deprecated-declarations', '-target', f'{arch}-apple-ios15.0-simulator', '-isysroot', sdk,
                    *map(str, sources), str(ROOT / 'tests/ios-graphics/main.mm'),
                    '-framework', 'UIKit', '-framework', 'Foundation', '-framework', 'QuartzCore', '-framework', 'OpenGLES',
                    '-o', str(app / 'GraphicsSmoke')], check=True, timeout=120)
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True, timeout=30)
    def capture(*args):
        return subprocess.check_output(['xcrun', 'simctl', *args], text=True, timeout=180)
    runtimes = json.loads(capture('list', 'runtimes', '--json'))['runtimes']
    runtime = sorted([r for r in runtimes if r.get('isAvailable') and '.iOS-' in r['identifier']],
                     key=lambda r: tuple(map(int, r['version'].split('.'))))[0]['identifier']
    phones = json.loads(capture('list', 'devices', 'available', '--json'))['devices'][runtime]
    phone = next(d for d in phones if d['name'].startswith('iPhone') and d.get('deviceTypeIdentifier'))
    device = capture('create', 'HollowGraphicsSmoke', phone['deviceTypeIdentifier'], runtime).strip()
    try:
        capture('boot', device)
        subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True, timeout=300)
        subprocess.run(['xcrun', 'simctl', 'install', device, str(app)], check=True, timeout=300)
        container = Path(capture('get_app_container', device, bundle, 'data').strip())
        capture('launch', device, bundle)
        result_file = container / 'Documents/graphics-result.json'
        deadline = time.monotonic() + 90
        while not result_file.is_file() and time.monotonic() < deadline:
            time.sleep(0.25)
        if not result_file.is_file():
            raise RuntimeError('Graphics regression app did not complete')
        result = json.loads(result_file.read_text(encoding='utf-8'))
        (output / 'results.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        print(json.dumps(result, indent=2), flush=True)
        if not result.get('passed'):
            raise RuntimeError('Real iOS graphics context or framebuffer regression failed')
    finally:
        cleanup_device(device)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('engine', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    run(args.engine.resolve(), args.output.resolve())
