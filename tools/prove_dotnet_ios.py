"""Standalone interpreter/interop experiment. Does not enable C# in Hollow."""
from pathlib import Path
import argparse
import json
import platform
import plistlib
import shutil
import subprocess
import time
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "10.0.15"


def run(command, **kwargs):
    print(" ".join(map(str, command)), flush=True)
    return subprocess.run(list(map(str, command)), check=True, timeout=240, **kwargs)


def prove(output):
    output.mkdir(parents=True, exist_ok=True)
    sources = ROOT / "runtime_dotnet/probe"
    for project in ["Host", "Game"]:
        run(["dotnet", "build", sources / (project + ".csproj"), "-c", "Release", "-o", output / project,
             "-p:BaseIntermediateOutputPath=" + str(output / (project + "-obj")) + "/"])
    for rid, sdk, triple in [("ios-arm64", "iphoneos", "arm64-apple-ios15.0"),
                              ("iossimulator-arm64", "iphonesimulator", "arm64-apple-ios15.0-simulator")]:
        package = "microsoft.netcore.app.runtime.mono." + rid
        archive = output / (package + ".nupkg")
        if not archive.is_file():
            with urllib.request.urlopen(f"https://api.nuget.org/v3-flatcontainer/{package}/{VERSION}/{package}.{VERSION}.nupkg", timeout=90) as response, archive.open("wb") as target:
                shutil.copyfileobj(response, target)
        unpacked = output / rid
        with zipfile.ZipFile(archive) as z:
            for member in z.infolist():
                path = (unpacked / member.filename).resolve()
                if not path.is_relative_to(unpacked.resolve()): raise RuntimeError("Unsafe runtime package path")
            z.extractall(unpacked)
        native = unpacked / "runtimes" / rid / "native"
        app = output / (rid + ".app"); app.mkdir(exist_ok=True)
        managed = app / "Managed"; managed.mkdir(exist_ok=True)
        for dll in (unpacked / "runtimes" / rid / "lib/net10.0").glob("*.dll"): shutil.copyfile(dll, managed / dll.name)
        shutil.copyfile(output / "Host/HollowManagedProbe.dll", managed / "HollowManagedProbe.dll")
        shutil.copyfile(output / "Game/IndependentGame.dll", app / "IndependentGame.dll")
        for library in native.glob("libSystem.*.dylib"):
            target = app / library.name; shutil.copyfile(library, target)
            if rid == "iossimulator-arm64": run(["codesign", "--force", "--sign", "-", target])
        sdk_path = subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True).strip()
        libraries = [native / "libmonosgen-2.0.a", native / "libmono-component-marshal-ilgen-static.a"]
        libraries += [native / ("libmono-component-" + name + "-stub-static.a") for name in ["debugger", "diagnostics_tracing", "hot_reload"]]
        command = ["xcrun", "--sdk", sdk, "clang", "-target", triple, "-isysroot", sdk_path, "-fobjc-arc", "-O1",
                   "-I" + str(native / "include/mono-2.0"), sources / "main.m"]
        for library in libraries: command += ["-Wl,-force_load," + str(library)]
        command += ["-lc++", "-lz", "-liconv", "-framework", "UIKit", "-framework", "Foundation", "-framework", "Security", "-framework", "SystemConfiguration", "-o", app / "HollowMonoProbe"]
        run(command)
        (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "org.godotplayer.monoprobe", "CFBundleExecutable": "HollowMonoProbe", "CFBundleName": "Mono Probe", "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0", "MinimumOSVersion": "15.0", "UIDeviceFamily": [1], "UILaunchScreen": {}}))
        if rid == "iossimulator-arm64": run(["codesign", "--force", "--sign", "-", app])
    runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "--json"], text=True))["runtimes"]
    runtime = sorted([r for r in runtimes if r.get("isAvailable") and ".iOS-" in r["identifier"]], key=lambda r: tuple(map(int, r["version"].split("."))))[-1]["identifier"]
    devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"], text=True))["devices"][runtime]
    phone = next(d for d in devices if d["name"].startswith("iPhone") and d.get("deviceTypeIdentifier"))
    device = subprocess.check_output(["xcrun", "simctl", "create", "HollowMonoProbe", phone["deviceTypeIdentifier"], runtime], text=True).strip()
    try:
        run(["xcrun", "simctl", "boot", device]); run(["xcrun", "simctl", "bootstatus", device, "-b"])
        run(["xcrun", "simctl", "install", device, output / "iossimulator-arm64.app"])
        container = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", device, "org.godotplayer.monoprobe", "data"], text=True).strip())
        run(["xcrun", "simctl", "launch", device, "org.godotplayer.monoprobe"])
        record = container / "Documents/probe-result.json"; deadline = time.monotonic() + 90
        while not record.is_file() and time.monotonic() < deadline: time.sleep(0.25)
        if not record.is_file(): raise RuntimeError("Interpreter process produced no completion record")
        shutil.copyfile(record, output / "results.json")
        result = json.loads(record.read_text())
        if not result["passed"]: raise RuntimeError(result["message"])
    finally:
        logs = subprocess.run(["xcrun", "simctl", "spawn", device, "log", "show", "--last", "4m", "--style", "compact", "--predicate", "process == 'HollowMonoProbe'"], capture_output=True, text=True, timeout=30)
        (output / "simulator.log").write_text(logs.stdout + logs.stderr)
        from check_input_ui import cleanup_device
        cleanup_device(device)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument("output", type=Path)
    prove(parser.parse_args().output.resolve())
