"""Compile the archive bridge/CLI for native macOS tests or Windows proof."""
from pathlib import Path
import argparse
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def build(engine, output):
    output.mkdir(parents=True, exist_ok=True)
    mac = sys.platform == "darwin"
    tool = ROOT / ".cache/llvm-mingw-20261104-ucrt-x86_64/bin"
    cc = ["xcrun", "clang"] if mac else [str(tool / "clang.exe")]
    cxx = ["xcrun", "clang++"] if mac else [str(tool / "clang++.exe")]
    ar = ["xcrun", "ar"] if mac else [str(tool / "llvm-ar.exe")]
    include = ["-I", str(engine), "-I", str(engine / "thirdparty/zlib"), "-I", str(ROOT / "ios")]
    sources = [engine / ("thirdparty/minizip/" + name + ".c") for name in ["ioapi", "unzip", "zip"]]
    if not mac:
        sources += [engine / ("thirdparty/zlib/" + name + ".c") for name in ["adler32", "crc32", "deflate", "inffast", "inflate", "inftrees", "trees", "zutil", "compress", "uncompr"]]
    objects = []
    for source in sources:
        obj = output / (source.stem + ".o")
        subprocess.run(cc + include + ["-O1", "-c", str(source), "-o", str(obj)], check=True)
        objects.append(str(obj))
    executable = output / ("archive-tests" if mac else "archive-tests.exe")
    libs = ["-lz"] if mac else ["-static"]
    archive_flags = ["-std=gnu++17", "-Os", "-fno-exceptions", "-fno-modules", "-fno-cxx-modules"]
    subprocess.run(cxx + include + archive_flags + [str(ROOT / "tests/archive_core.cpp"), *objects, *libs, "-o", str(executable)], check=True)
    if mac:
        bridge = output / "ArchiveSupport.o"
        subprocess.run(cxx + include + archive_flags + ["-fobjc-arc", "-c", str(ROOT / "ios/ArchiveSupport.mm"), "-o", str(bridge)], check=True)
        subprocess.run(ar + ["rcs", str(output / "libplayer_archive.a"), str(bridge), *objects], check=True)
    return executable

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(build(args.engine.resolve(), args.output.resolve()))
