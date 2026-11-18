"""Export an original test PCK and execute the compiled engine's live tools."""
from pathlib import Path
import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def prove(editor, runtime, major, adjacent=False):
    output = ROOT / "build/tools-proof" / str(major)
    output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    for key in ["APPDATA", "LOCALAPPDATA"]:
        folder = output / key.lower(); folder.mkdir(exist_ok=True); env[key] = str(folder)
    base = ["--headless"] if major == 4 else ["--no-window", "--audio-driver", "Dummy", "--video-driver", "GLES2"]
    def run(executable, args, cwd, name):
        result = subprocess.run([str(executable), *base, *map(str, args)], cwd=cwd, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
        text = result.stdout + result.stderr
        (output / (name + ".log")).write_text(text, encoding="utf-8")
        if result.returncode or "SCRIPT ERROR" in text or "PLAYER_TOOLS_PROOF FAIL" in text:
            raise RuntimeError(f"Tools proof failed ({name}, exit {result.returncode}):\n{text[-6000:]}")
        return text
    with tempfile.TemporaryDirectory(dir=output, prefix="project-") as temporary:
        project = Path(temporary)
        for name in ["project.godot", "Main.gd", "Main.tscn", "Stats.gd", "Gone.gd", "export_presets.cfg"]:
            shutil.copy2(ROOT / "samples/tools-proof" / name, project / name)
        if major == 3:
            shutil.copy2(ROOT / "samples/godot3/project.godot", project / "project.godot")
            shutil.copy2(ROOT / "samples/godot3/export_presets.cfg", project / "export_presets.cfg")
            (project / "Main.tscn").write_text('[gd_scene load_steps=2 format=2]\n[ext_resource path="res://Main.gd" type="Script" id=1]\n[node name="ToolsProof" type="Node"]\nscript = ExtResource( 1 )\n')
            script = (project / "Main.gd").read_text()
            script = script.replace('ClassDB.call("instantiate",', 'ClassDB.call("instance",')
            script = script.replace('button.connect("pressed", Callable(self, "test_signal"))', 'button.connect("pressed", self, "test_signal")')
            script = script.replace("Time.get_ticks_usec()", "OS.get_ticks_usec()")
            script = script.replace("JSON.parse_string", "parse_json_wire").replace("JSON.stringify", "write_json_wire")
            script += '\nfunc parse_json_wire(text):\n    return JSON.parse(text).result\n\nfunc write_json_wire(value):\n    return JSON.print(value)\n'
            (project / "Main.gd").write_text(script)
        pack = output / "tools.pck"
        run(editor, ["--path", project, "--editor", "--import"] if major == 4 else ["--path", project, "--editor", "--quit"], output, "import")
        run(editor, ["--path", project, "--export-pack", "PCK", pack], output, "export")
        if adjacent:
            # Only use explicitly opted-in, private workspace compiler outputs.
            # Preserve any prior adjacent pack (including fixture hard links).
            runtime = runtime.resolve()
            if not runtime.is_relative_to(ROOT / ".cache"):
                raise RuntimeError("Adjacent fixture mode is restricted to workspace .cache runtimes")
            link = runtime.with_suffix(".pck")
            backup = runtime.with_suffix(".tools-proof-backup.pck")
            if backup.exists(): raise RuntimeError("A previous fixture backup needs recovery")
            existed = link.exists()
            if existed: link.rename(backup)
            try:
                os.link(pack, link)
                text = run(runtime, [], output, "run")
            finally:
                if link.exists(): link.unlink()
                if existed: backup.rename(link)
        else:
            with tempfile.TemporaryDirectory(dir=output, prefix="empty-") as empty:
                text = run(runtime, ["--main-pack", pack], empty, "run")
        match = re.search(r"PLAYER_TOOLS_PROOF PASS checks=(\d+)", text)
        if not match: raise RuntimeError("Compiled native tools did not execute the checks")
        timings = [json.loads(line.split("PLAYER_SEARCH_TIMING ", 1)[1]) for line in text.splitlines() if line.startswith("PLAYER_SEARCH_TIMING ")]
        result = {"search_timings": timings, "engine_major": major, "checks_passed": int(match[1]), "runtime": "locally compiled official release plus PlayerTools", "result": "passed", "ios_ui": "not tested"}
        (output / "results.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("editor", type=Path)
    parser.add_argument("runtime", type=Path)
    parser.add_argument("--major", type=int, choices=[3, 4], required=True)
    parser.add_argument("--adjacent-pack", action="store_true")
    args = parser.parse_args()
    prove(args.editor.resolve(), args.runtime.resolve(), args.major, args.adjacent_pack)
