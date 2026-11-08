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
COMPATIBILITY_REVISION = "godot-4.7-module-api-v1"


def adapt_godot47(module):
    # Godot 4.7 removed transitive includes and moved rendering constants/types
    # out of RenderingServer. Adapt only our staged built-in module, preserving
    # the pinned upstream checkout and the Spine 4.2 animation/data format.
    common = module / "SpineCommon.h"
    text = common.read_text(encoding="utf-8")
    anchor = '#include "core/error/error_macros.h"'
    if text.count(anchor) != 1:
        raise RuntimeError("Unexpected SpineCommon.h layout for Godot header adaptation.")
    text = text.replace(anchor, anchor + '\n#include <cfloat>\n#include "core/object/callable_mp.h"\n#include "core/templates/local_vector.h"\n#include "scene/main/scene_tree.h"\n#include "servers/rendering/rendering_server.h"')
    common.write_text(text, encoding="utf-8")
    replacements = {
        "get_singleton": "RenderingServer::get_singleton",
        "SurfaceData": "RenderingServerTypes::SurfaceData",
        "ARRAY_COLOR": "RenderingServerEnums::ARRAY_COLOR",
        "ARRAY_MAX": "RenderingServerEnums::ARRAY_MAX",
        "ARRAY_TEX_UV": "RenderingServerEnums::ARRAY_TEX_UV",
        "ARRAY_VERTEX": "RenderingServerEnums::ARRAY_VERTEX",
        "ArrayFormat": "RenderingServerEnums::ArrayFormat",
        "PrimitiveType": "RenderingServerEnums::PrimitiveType",
    }
    for path in sorted(module.iterdir()):
        if path.suffix not in (".cpp", ".h"):
            continue
        text = path.read_text(encoding="utf-8")
        def replace(match):
            name = match.group(1)
            if name not in replacements:
                raise RuntimeError(f"Unmapped Spine rendering API in {path.name}: RS::{name}")
            return replacements[name]
        updated = re.sub(r"\bRS::(\w+)", replace, text)
        updated = updated.replace("RenderingServer::get_singleton()->free(", "RenderingServer::get_singleton()->free_rid(")
        if path.name == "SpineAnimationTrack.cpp":
            old = ("List<StringName> animation_libraries;\n"
                   "\t\tanimation_player->get_animation_library_list(&animation_libraries);\n"
                   "\t\tfor (auto iter = animation_libraries.front(); iter; iter = iter->next()) {\n"
                   "\t\t\tanimation_player->remove_animation_library(iter->get());\n\t\t}")
            new = ("LocalVector<StringName> animation_libraries;\n"
                   "\t\tanimation_player->get_animation_library_list(&animation_libraries);\n"
                   "\t\tfor (const StringName &name : animation_libraries) {\n"
                   "\t\t\tanimation_player->remove_animation_library(name);\n\t\t}")
            if updated.count(old) != 1:
                raise RuntimeError("Unexpected Spine animation-library enumeration for Godot 4.7.")
            updated = updated.replace(old, new)
        if path.name == "SpineAtlasResource.cpp":
            # JSON is RefCounted; memnew returns Ref<JSON> in Godot 4.7.
            if updated.count("JSON *json = memnew(JSON);") != 2 or updated.count("memdelete(json);") != 3:
                raise RuntimeError("Unexpected Spine atlas JSON ownership for Godot 4.7.")
            updated = updated.replace("JSON *json = memnew(JSON);", "Ref<JSON> json;\n\tjson.instantiate();")
            updated = updated.replace("memdelete(json);", "// JSON is released by its Ref when this scope ends.")
        if path.name == "register_types.cpp":
            # Keep strong references while registered, and release them during
            # module shutdown rather than from process-global destructors.
            loaders = {
                "atlas_loader": ("SpineAtlasResourceFormatLoader", "ResourceLoader", "loader"),
                "atlas_saver": ("SpineAtlasResourceFormatSaver", "ResourceSaver", "saver"),
                "skeleton_file_loader": ("SpineSkeletonFileResourceFormatLoader", "ResourceLoader", "loader"),
                "skeleton_file_saver": ("SpineSkeletonFileResourceFormatSaver", "ResourceSaver", "saver"),
            }
            for variable, (kind, server, role) in loaders.items():
                old = f"static {kind} *{variable};"
                if updated.count(old) != 1:
                    raise RuntimeError(f"Unexpected Spine registration ownership: {variable}")
                updated = updated.replace(old, f"static Ref<{kind}> {variable};")
                old = f"{server}::remove_resource_format_{role}({variable});"
                if updated.count(old) != 1:
                    raise RuntimeError(f"Unexpected Spine shutdown ownership: {variable}")
                updated = updated.replace(old, old + f"\n\t{variable}.unref();")
        if updated != text:
            path.write_text(updated, encoding="utf-8")


def prepare(engine, source, version, report, notice, *, verify_revision=True, engine_major=4):
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
        if engine_major == 4:
            adapt_godot47(target)
        elif engine_major != 3:
            raise ValueError("Spine staging supports Godot 3 or 4 only")
        # Upstream places the module beside its engine checkout. We put it in
        # modules/ so Godot's normal module discovery and registration apply.
        (target / "SCsub").write_text(scsub.replace(old_include, "#modules/spine_godot/spine-cpp/include"), encoding="utf-8")
        (target / "LICENSE").write_text(license_text, encoding="utf-8")
        notice.parent.mkdir(parents=True, exist_ok=True)
        notice.write_text(license_text, encoding="utf-8")
        metadata["classes"] = list(REQUIRED_CLASSES)
        metadata["godot_compatibility"] = COMPATIBILITY_REVISION if engine_major == 4 else "upstream-godot3-api"
        metadata["engine_major"] = engine_major
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Bundled Spine: {version} ({REVISIONS[version] or 'disabled'})")
    if version != "none":
        print(f"Spine engine adaptation: {metadata['godot_compatibility']}")
    return metadata


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", type=Path)
    parser.add_argument("source", type=Path)
    parser.add_argument("--version", choices=REVISIONS, default="4.2")
    parser.add_argument("--engine-major", type=int, choices=[3, 4], default=4)
    parser.add_argument("--report", type=Path, default=Path("build/spine-build.json"))
    parser.add_argument("--notice", type=Path, default=Path("build/SPINE-RUNTIMES-LICENSE.txt"))
    args = parser.parse_args()
    prepare(args.engine.resolve(), args.source.resolve(), args.version, args.report, args.notice, engine_major=args.engine_major)
