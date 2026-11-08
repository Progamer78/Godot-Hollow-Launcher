"""Link the actual archive bridge for iPhone before either long engine build."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def commands(engine, output, sdk):
    driver = engine / "drivers/apple_embedded"
    common = ["-target", "arm64-apple-ios14.0", "-isysroot", str(sdk), "-Os",
              "-I", str(engine), "-I", str(engine / "thirdparty/zlib")]
    result = []
    objects = []
    for name in ["ioapi", "unzip", "zip"]:
        obj = output / (name + ".o")
        result.append(["xcrun", "--sdk", "iphoneos", "clang", *common, "-c",
                       str(engine / "thirdparty/minizip" / (name + ".c")), "-o", str(obj)])
        objects.append(str(obj))
    bridge = output / "ArchiveSupport.o"
    # Match the engine's optimization, exception and ARC settings. Only this
    # source opts out of modules, exactly as its cloned SCons environment does.
    result.append(["xcrun", "--sdk", "iphoneos", "clang++", *common,
                   "-std=gnu++17", "-fno-exceptions", "-fno-rtti", "-fobjc-arc",
                   "-fno-modules", "-fno-cxx-modules", "-c",
                   str(driver / "ArchiveSupport.mm"), "-o", str(bridge)])
    result.append(["xcrun", "--sdk", "iphoneos", "clang++", *common,
                   "-dynamiclib", str(bridge), *objects, "-framework", "Foundation",
                   "-lz", "-lc++", "-Wl,-undefined,error",
                   "-Wl,-install_name,@rpath/ArchiveLinkProof.dylib",
                   "-o", str(output / "ArchiveLinkProof.dylib")])
    return result


def check(engine, output):
    output.mkdir(parents=True, exist_ok=True)
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
    driver = engine / "drivers/apple_embedded"
    scsub = (driver / "SCsub").read_text()
    if 'env_archive.Append(CCFLAGS=["-fno-modules", "-fno-cxx-modules"])' not in scsub:
        raise RuntimeError("Archive bridge SCons module isolation is missing; update tools/patch_engine.py.")
    steps = commands(engine, output, sdk)
    for step in steps:
        subprocess.run(step, check=True)
    report = {"target": "arm64-apple-ios14.0", "sdk": sdk, "linked": True,
              "scope": "Foundation archive bridge only; not the complete app",
              "sources": {name: hashlib.sha256((driver / name).read_bytes()).hexdigest()
                          for name in ["ArchiveSupport.mm", "ArchiveSupport.h", "ArchiveCore.inc", "ArchiveCore.h"]},
              "commands": steps}
    (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print("iPhone archive bridge compiled and linked with all symbols resolved.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    check(args.engine.resolve(), args.output.resolve())
