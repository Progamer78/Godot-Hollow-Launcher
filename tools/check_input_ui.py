"""Run the real input views in a disposable iPhone simulator before engine builds."""
import argparse
import json
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import time

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


def wait_for_result(source, output, timeout=120):
    deadline = time.monotonic() + timeout
    while not source.is_file() and time.monotonic() < deadline:
        time.sleep(0.25)
    if not source.is_file():
        (output / "run.log").write_text("Input app did not produce a completion record before the timeout. See launcher.log and diagnostics.log.\n")
        raise RuntimeError("Input app did not finish; no completion record. See input-ui diagnostics.")
    log = source.read_text(encoding="utf-8")
    (output / "run.log").write_text(log, encoding="utf-8")
    print(log)
    if "PLAYER_INPUT_UI_PASS:" not in log or "PLAYER_INPUT_UI_FAIL:" in log:
        raise RuntimeError("Input UIKit smoke test failed; see input-ui/run.log.")


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
    files = ["ios/ToolModels.swift", "ios/PinnedHUD.swift", "ios/ControllerProfile.swift", "ios/ControllerInput.swift", "ios/ControlProfile.swift", "ios/GameInput.swift", "ios/InputViews.swift", "ios/KeyboardInput.swift", "ios/Joystick.swift", "tests/input-ui/LifetimeAudit.swift", "tests/input-ui/main.swift"]
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
        # Fresh hosted simulators can spend over a minute starting installd and
        # FrontBoard even after bootstatus finishes. These are maximum limits;
        # healthy runners proceed as soon as each command returns.
        subprocess.run(["xcrun", "simctl", "install", device, str(app)], check=True, timeout=180)
        container = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", device, bundle, "data"], text=True, timeout=60).strip())
        # Console attachment can outlive a short-lived UIKit process on a busy
        # freshly booted runner. Require an atomic completion record from the
        # actual test app, without keeping its console connection open.
        try:
            result = subprocess.run(["xcrun", "simctl", "launch", device, bundle], capture_output=True, text=True, timeout=180)
        except subprocess.TimeoutExpired as error:
            partial = (error.stdout or b"") + (error.stderr or b"")
            if isinstance(partial, bytes): partial = partial.decode(errors="replace")
            (output / "launcher.log").write_text(partial)
            raise
        (output / "launcher.log").write_text(result.stdout + result.stderr)
        result.check_returncode()
        try:
            wait_for_result(container / "Documents/input-ui-result.log", output)
        finally:
            for name in ["hud-long-name-first.png", "hud-long-name-second.png"]:
                screenshot = container / "Documents" / name
                if screenshot.is_file(): shutil.copyfile(screenshot, output / name)
        (output / "results.json").write_text(json.dumps({"passed": True, "runtime": runtime, "sources": files,
              "scope": "Actual UIKit controls/keyboard/cursor updates and rendered SwiftUI long-name pin HUD regression; recorded engine endpoints, no Godot runtime or display-frame timing guarantee"}, indent=2) + "\n")
    except Exception:
        try:
            diagnostic = subprocess.run(["xcrun", "simctl", "spawn", device, "log", "show", "--last", "3m", "--style", "compact", "--predicate", "process == 'InputSmoke'"], capture_output=True, text=True, timeout=20)
            (output / "diagnostics.log").write_text(diagnostic.stdout + diagnostic.stderr)
        except (OSError, subprocess.TimeoutExpired):
            pass
        raise
    finally:
        cleanup_device(device)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    run(args.output.resolve())
