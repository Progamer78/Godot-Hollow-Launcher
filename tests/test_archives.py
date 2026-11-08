from pathlib import Path
import importlib.util
import os
import struct
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]

class ArchiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        engine = ROOT / ".cache/godot-source"
        if not (engine / "thirdparty/minizip").is_dir(): engine = ROOT / ".cache/godot-4.7.2-stable"
        spec = importlib.util.spec_from_file_location("archive_builder", ROOT / "tools/build_archive_support.py")
        builder = importlib.util.module_from_spec(spec); spec.loader.exec_module(builder)
        cls.executable = builder.build(engine, ROOT / "build/archive-tests")

    def call(self, *args):
        return subprocess.run([str(self.executable), *map(str,args)], capture_output=True)

    def test_stored_deflated_zip64_and_apk(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for method in [zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED]:
                archive = root / "game.apk"
                payload = b"unchanged game asset" * 100000
                with zipfile.ZipFile(archive, "w", compression=method) as z:
                    with z.open("assets/game.pck", "w", force_zip64=True) as f: f.write(payload)
                self.assertEqual(self.call("list",archive).returncode,0)
                output = root / "result.pck"
                self.assertEqual(self.call("extract",archive,"assets/game.pck",output,len(payload)).returncode,0)
                self.assertEqual(output.read_bytes(),payload)
                output.unlink()
                self.assertNotEqual(self.call("extract",archive,"assets/game.pck",output,len(payload)-1).returncode,0)
                self.assertFalse(output.exists())

    def test_unsafe_duplicate_and_symlink_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary)/"bad.zip"
            for name in ["../escape", "/absolute", "a/../b", "a\\b", "C:/x", "a//b"]:
                info = zipfile.ZipInfo(); info.filename = name
                with zipfile.ZipFile(archive,"w") as z:z.writestr(info,b"bad")
                self.assertNotEqual(self.call("list",archive).returncode,0,name)
            with zipfile.ZipFile(archive,"w") as z:
                z.writestr("same",b"a"); z.writestr("same",b"b")
            self.assertNotEqual(self.call("list",archive).returncode,0)
            info=zipfile.ZipInfo("link");info.create_system=3;info.external_attr=0o120777<<16
            with zipfile.ZipFile(archive,"w") as z:z.writestr(info,"../../target")
            self.assertNotEqual(self.call("list",archive).returncode,0)

    def test_crc_failure_removes_partial_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);archive=root/"crc.zip"
            with zipfile.ZipFile(archive,"w",compression=zipfile.ZIP_STORED) as z:z.writestr("save.dat",b"original content")
            data=bytearray(archive.read_bytes());data[data.index(b"original content")]=ord('X');archive.write_bytes(data)
            output=root/"out"
            self.assertNotEqual(self.call("extract",archive,"save.dat",output,1024).returncode,0)
            self.assertFalse(output.exists())

    def test_save_zip_round_trip(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);source=root/"save.json";source.write_bytes(b'{"money":55}')
            archive=root/"saves.zip"
            result=self.call("create",archive,root,"empty/",source,"slot/save.json")
            self.assertEqual(result.returncode,0,result.stderr)
            with zipfile.ZipFile(archive) as z:
                self.assertIsNone(z.testzip());self.assertEqual(z.read("slot/save.json"),source.read_bytes());self.assertTrue(z.getinfo("empty/").is_dir())
            self.assertEqual(self.call("list",archive).returncode,0)

    def test_indexed_extraction_checks_entry_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);archive=root/'many-assets.apk'
            with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED) as z:
                for i in range(500):z.writestr('assets/file-'+str(i),str(i).encode())
            listed=self.call('list',archive)
            self.assertEqual(listed.returncode,0,listed.stderr)
            rows=[line.split(b'\t',3) for line in listed.stdout.splitlines()]
            size,position,index,name=rows[-1]
            output=root/'asset'
            result=self.call('extract_at',archive,name.decode(),output,1024,position.decode(),index.decode())
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(output.read_bytes(),b'499')
            result=self.call('extract_at',archive,'assets/file-0',root/'wrong',1024,position.decode(),index.decode())
            self.assertNotEqual(result.returncode,0)
            self.assertFalse((root/'wrong').exists())
