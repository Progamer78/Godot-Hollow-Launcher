"""Embed the trusted build-time framework and audit engine symbol isolation."""
from pathlib import Path
import argparse
import plistlib
import shutil
import subprocess


def install(payload, framework):
    apps = list(payload.glob("*.app"))
    if len(apps) != 1 or not (framework / "Godot3Runtime").is_file():
        raise RuntimeError("Expected one archived application and a linked Godot 3 framework.")
    app = apps[0]
    executable = app / plistlib.loads((app / "Info.plist").read_bytes())["CFBundleExecutable"]
    host = subprocess.check_output(["xcrun", "nm", "-a", str(executable)], text=True)
    guest = subprocess.check_output(["xcrun", "nm", "-a", str(framework / "Godot3Runtime")], text=True)
    # Objective-C class and protocol registration is process-wide even when
    # C++ symbols are image-local. Reject shared definitions before packaging.
    def objc_names(text):
        return {line.split()[-1] for line in text.splitlines() if " U " not in line and
                ("_OBJC_CLASS_$_" in line or "__OBJC_PROTOCOL_$_" in line)}
    common = objc_names(host) & objc_names(guest)
    if common:
        raise RuntimeError(f"Runtime Objective-C symbol collisions: {sorted(common)}")
    destination = app / "Frameworks" / framework.name
    destination.parent.mkdir(exist_ok=True)
    shutil.copytree(framework, destination)
    print("Embedded Godot 3 framework; no Objective-C definitions shared with Godot 4.")
    print("Personal signing must sign the application and its embedded framework.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("payload", type=Path)
    parser.add_argument("framework", type=Path)
    args = parser.parse_args()
    install(args.payload.resolve(), args.framework.resolve())
