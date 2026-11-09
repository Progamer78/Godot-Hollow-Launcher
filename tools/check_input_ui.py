"""Run the real input views in a disposable iPhone simulator before engine builds."""
import argparse
import json
from pathlib import Path
import platform
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def forbidden_callbacks(source):
    callbacks = re.finditer(r"@objc(?:\(([^)]+)\))?\s+(?:(?:private|fileprivate|public|internal|final|dynamic|override)\s+)*func\s+(\w+)", source)
    reserved = {"release", "retain", "autorelease", "retainCount", "dealloc"}
    return [match.group(1) or match.group(2) for match in callbacks
            if (match.group(1) or match.group(2)) in reserved]


def audit_callbacks():
    for path in (ROOT / "ios").glob("*.swift"):
        unsafe = forbidden_callbacks(path.read_text(encoding="utf-8"))
        if unsafe:
            raise RuntimeError(f"Object-lifetime selector exposed by {path.name}: {unsafe}")


def cleanup_device(device):
    # Cleanup is best-effort on the disposable CI simulator. Preserve the
    # original test result if CoreSimulator is slow, and still attempt delete
    # even when shutdown timed out.
    for action in ["shutdown", "delete"]:
        try:
            result = subprocess.run(["xcrun", "simctl", action, device], capture_output=True, timeout=30)
            if result.returncode:
                print(f"Simulator cleanup {action} returned {result.returncode}; continuing.")
        except (subprocess.TimeoutExpired, OSError) as error:
            print(f"Simulator cleanup {action} could not finish: {error}")


def run(output):
    audit_callbacks()
    output.mkdir(parents=True, exist_ok=True)
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
    arch = "arm64" if platform.machine() == "arm64" else "x86_64"
    app = output / "InputSmoke.app"
    app.mkdir(exist_ok=True)
    bundle = "org.godotplayer.inputsmoke"
    (app / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": bundle, "CFBundleExecutable": "InputSmoke", "CFBundleName": "Input Smoke",
        "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
        "MinimumOSVersion": "15.0", "LSRequiresIPhoneOS": True, "UIDeviceFamily": [1],
        "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
        "UILaunchScreen": {}, "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
    }))
    files = ["ios/ControllerProfile.swift", "ios/ControllerInput.swift", "ios/ControlProfile.swift", "ios/GameInput.swift", "ios/InputViews.swift", "ios/KeyboardInput.swift", "ios/Joystick.swift", "tests/input-ui/LifetimeAudit.swift", "tests/input-ui/main.swift"]
    subprocess.run(["xcrun", "--sdk", "iphonesimulator", "swiftc", "-swift-version", "5", "-parse-as-library",
                    "-sdk", sdk, "-target", f"{arch}-apple-ios15.0-simulator",
                    *[str(ROOT / file) for file in files], "-o", str(app / "InputSmoke")], check=True, timeout=120)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, timeout=30)
    runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "--json"], text=True))["runtimes"]
    ios = sorted([r for r in runtimes if r.get("isAvailable") and ".iOS-" in r["identifier"]], key=lambda r: tuple(map(int, r["version"].split("."))))
    if not ios:
        raise RuntimeError("No available iOS simulator runtime on this runner.")
    runtime = ios[-1]["identifier"]
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))["devices"].get(runtime, [])
    phones = [d for d in devices if d["name"].startswith("iPhone") and d.get("deviceTypeIdentifier")]
    if not phones:
        raise RuntimeError("No iPhone simulator device type found for the installed runtime.")
    device = subprocess.check_output(["xcrun", "simctl", "create", "GodotPlayerInputSmoke", phones[0]["deviceTypeIdentifier"], runtime], text=True).strip()
    try:
        subprocess.run(["xcrun", "simctl", "boot", device], check=True, timeout=30)
        subprocess.run(["xcrun", "simctl", "bootstatus", device, "-b"], check=True, timeout=180)
        subprocess.run(["xcrun", "simctl", "install", device, str(app)], check=True, timeout=60)
        result = subprocess.run(["xcrun", "simctl", "launch", "--console", device, bundle], capture_output=True, text=True, timeout=60)
        log = result.stdout + result.stderr
        (output / "run.log").write_text(log)
        print(log)
        if result.returncode or "PLAYER_INPUT_UI_PASS" not in log or "PLAYER_INPUT_UI_FAIL" in log:
            raise RuntimeError("Input UIKit smoke test failed; see input-ui/run.log.")
        (output / "results.json").write_text(json.dumps({"passed": True, "runtime": runtime, "sources": files,
              "scope": "Actual UIKit controls/keyboard/cursor updates; recorded engine endpoints, no Godot runtime or display-frame timing guarantee"}, indent=2) + "\n")
    finally:
        cleanup_device(device)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    run(args.output.resolve())
