"""Export independent PCKs, launch outside project roots, verify input and saves."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(engine, args, cwd, log):
    env = os.environ.copy()
    # Keep even desktop save/editor state inside the workspace on Windows.
    if os.name == "nt":
        data = ROOT / "build/proof/appdata"
        data.mkdir(parents=True, exist_ok=True)
        env["APPDATA"] = str(data)
    result = subprocess.run([str(engine), *map(str, args)], cwd=cwd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
    log.write_text(result.stdout + result.stderr, encoding="utf-8")
    if result.returncode or re.search(r"SCRIPT ERROR|Parse Error|Assertion failed|ERROR:", result.stdout + result.stderr):
        raise RuntimeError(f"Godot failed: {log}\n{result.stdout}\n{result.stderr}")
    return result.stdout + result.stderr


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("godot", type=Path)
    parser.add_argument("--visible", action="store_true", help="Also run each proof using a native graphics window")
    args = parser.parse_args()
    engine = args.godot.resolve()
    out = ROOT / "build/proof"
    out.mkdir(parents=True, exist_ok=True)
    results = {}
    for name in ["movement", "counter"]:
        project = ROOT / "samples" / name
        run(engine, ["--headless", "--path", project, "--editor", "--import"], ROOT, out / f"{name}-import.log")
        pack = out / f"{name}.pck"
        run(engine, ["--headless", "--path", project, "--export-pack", "PCK", pack], ROOT, out / f"{name}-export.log")
        # No project.godot, scene files, or loose scripts in the working directory.
        with tempfile.TemporaryDirectory(prefix="godot-player-") as empty:
            texts = []
            for attempt in range(2):
                text = run(engine, ["--headless", "--main-pack", pack, "--", "--player-proof"], empty, out / f"{name}-run-{attempt+1}.log")
                assert f"PLAYER_PROOF {name} PASS" in text, text
                texts.append(text)
            loaded = [int(re.search(r"loaded=(\d+)", text)[1]) for text in texts]
            assert loaded[1] == loaded[0] + 1, loaded
            if args.visible:
                run(engine, ["--main-pack", pack, "--rendering-method", "gl_compatibility", "--", "--player-proof"], empty, out / f"{name}-graphics.log")
        results[name] = {"pack_bytes": pack.stat().st_size, "loaded_counts": loaded, "headless": "passed", "graphics": "passed" if args.visible else "not tested"}
    (out / "results.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
