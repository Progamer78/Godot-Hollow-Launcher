"""Stage the official, statically linked Spine module in a clean Godot tree.

Spine is separately licensed. Preserve its source headers and ship the exact
selected revision's license with the resulting application.
"""
from pathlib import Path
import argparse
import json
import re
import shutil
import subprocess


REVISIONS = {
    "4.1": "77a5db0ec6d16331f5efbaa7662bba9355bd3424",
    "4.2": "5cb78e77d3711ddcd80c7bd043bb11cf70fcc88c",
    "4.3": "175a1e05073a406f305bde2621c065b8c2256c42",
    "none": "",
}
REQUIRED_CLASSES = (
    "SpineSprite", "SpineAnimation", "SpineAnimationState", "SpineTrackEntry",
    "SpineSkeleton", "SpineSkeletonDataResource",
)


def prepare(engine, source, version, report, notice, *, verify_revision=True):
    if version not in REVISIONS:
        raise ValueError(f"Unsupported Spine runtime version: {version}")
    target = engine / "modules/spine_godot"
    if target.exists():
        raise RuntimeError("Spine module already exists; use a clean engine tree to avoid mixing versions.")
    metadata = {"version": version, "revision": REVISIONS[version], "linkage": "static built-in module"}
    if version != "none":
        if verify_revision:
            actual = subprocess.check_output([
                "git", "-c", "safe.directory=" + source.resolve().as_posix(),
                "-C", str(source), "rev-parse", "HEAD",
            ], text=True).strip()
            if actual != REVISIONS[version]:
                raise RuntimeError(f"Unexpected Spine source revision: {actual}")
        module = source / "spine-godot/spine_godot"
        cpp = source / "spine-cpp/spine-cpp"
        version_header = (cpp / "include/spine/Version.h").read_text(encoding="utf-8")
        if not re.search(r'#define\s+SPINE_VERSION_STRING\s+"' + re.escape(version) + '"', version_header):
            raise RuntimeError("Spine C++ source version does not match the selected module.")
        registration = (module / "register_types.cpp").read_text(encoding="utf-8")
        for name in REQUIRED_CLASSES:
            if not re.search(r"GDREGISTER_CLASS\(\s*" + name + r"\s*\)", registration):
                raise RuntimeError(f"Missing required Spine class registration: {name}")
        scsub = (module / "SCsub").read_text(encoding="utf-8")
        old_include = "#../spine_godot/spine-cpp/include"
        if scsub.count(old_include) != 2:
            raise RuntimeError("Unexpected official Spine include configuration.")
        license_text = (source / "LICENSE").read_text(encoding="utf-8")
        if "Spine Runtimes License Agreement" not in license_text:
            raise RuntimeError("Official Spine runtime license is missing.")
        shutil.copytree(module, target)
        shutil.copytree(cpp, target / "spine-cpp")
        # Upstream places the module beside its engine checkout. We put it in
        # modules/ so Godot's normal module discovery and registration apply.
        (target / "SCsub").write_text(scsub.replace(old_include, "#modules/spine_godot/spine-cpp/include"), encoding="utf-8")
        (target / "LICENSE").write_text(license_text, encoding="utf-8")
        notice.parent.mkdir(parents=True, exist_ok=True)
        notice.write_text(license_text, encoding="utf-8")
        metadata["classes"] = list(REQUIRED_CLASSES)
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Bundled Spine: {version} ({REVISIONS[version] or 'disabled'})")
    return metadata


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", type=Path)
    parser.add_argument("source", type=Path)
    parser.add_argument("--version", choices=REVISIONS, default="4.2")
    parser.add_argument("--report", type=Path, default=Path("build/spine-build.json"))
    parser.add_argument("--notice", type=Path, default=Path("build/SPINE-RUNTIMES-LICENSE.txt"))
    args = parser.parse_args()
    prepare(args.engine.resolve(), args.source.resolve(), args.version, args.report, args.notice)
