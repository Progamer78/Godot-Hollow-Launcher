"""Export a Godot 3 PCK and verify independent launch, input and save reload."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ASSETS = {
    "darwin": ("Godot_v3.6.3-stable_osx.universal.zip", "5324c4ef7105e6f60a0efb91d448ed36747694821eac091b29104a470d197497", "Godot.app/Contents/MacOS/Godot"),
    "win32": ("Godot_v3.6.3-stable_win64.exe.zip", "80616a2621025b508a5ed14a5066630fb6c0c384ecab87277bf33569e965eec3", "Godot_v3.6.3-stable_win64.exe"),
}


def download():
    filename, digest, binary = ASSETS[sys.platform]
    folder = ROOT / ".cache/godot3-desktop"
    folder.mkdir(parents=True, exist_ok=True)
    archive = folder / filename
    if not archive.exists():
        urllib.request.urlretrieve("https://github.com/godotengine/godot-builds/releases/download/3.6.3-stable/" + filename, archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
        raise RuntimeError("Official Godot 3 desktop checksum mismatch")
    executable = folder / binary
    if not executable.exists():
        with zipfile.ZipFile(archive) as z:
            z.extractall(folder)
        executable.chmod(0o755)
    return executable


def proof(engine):
    output = ROOT / "build/godot3-proof"
    output.mkdir(parents=True, exist_ok=True)
    data = output / "appdata"
    data.mkdir(exist_ok=True)
    env = os.environ.copy()
    if os.name == "nt":
        env["APPDATA"] = str(data)
        env["LOCALAPPDATA"] = str(data)
    pack = output / "godot3.pck"
    def run(arguments, cwd, name):
        result = subprocess.run([str(engine), "--no-window", "--audio-driver", "Dummy", "--video-driver", "GLES2", *map(str, arguments)], cwd=cwd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
        text = result.stdout + result.stderr
        (output / (name + ".log")).write_text(text, encoding="utf-8")
        if result.returncode or re.search(r"SCRIPT ERROR|Parse Error|Assertion failed|ERROR:", text):
            raise RuntimeError(f"Godot 3 proof failed: {name}\n{text}")
        return text
    project = ROOT / "samples/godot3"
    run(["--path", project, "--editor", "--quit"], ROOT, "import")
    run(["--path", project, "--export-pack", "PCK", pack], ROOT, "export")
    loaded = []
    with tempfile.TemporaryDirectory(prefix="godot3-player-") as empty:
        for attempt in range(2):
            text = run(["--main-pack", pack, "--", "--player-proof"], empty, f"run-{attempt + 1}")
            match = re.search(r"PLAYER_PROOF godot3 PASS loaded=(\d+)", text)
            if not match:
                raise RuntimeError("Godot 3 did not execute the proof script")
            loaded.append(int(match[1]))
    if loaded[1] != loaded[0] + 1:
        raise RuntimeError("Godot 3 save did not persist across launches")
    result = {"runtime": "Godot 3.6.3 official desktop", "frames_each_launch": 90, "loaded_counts": loaded,
              "pack_bytes": pack.stat().st_size, "keyboard_input": "passed", "animation": "passed", "save_reload": "passed",
              "ios_execution": "not tested"}
    (output / "results.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", nargs="?", type=Path)
    parser.add_argument("--download", action="store_true")
    args = parser.parse_args()
    if not args.engine and not args.download:
        parser.error("Choose an engine executable or --download")
    proof(download() if args.download else args.engine.resolve())
