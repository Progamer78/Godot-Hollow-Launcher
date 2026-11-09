from pathlib import Path
import platform
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]

def fixture():
    b=bytearray(0xc00)
    b[:2]=b'MZ'; struct.pack_into('<I',b,60,0x80)
    b[0x80:0x84]=b'PE\0\0'; struct.pack_into('<HHIIIHH',b,0x84,0x8664,4,0,0,0,0xf0,0)
    struct.pack_into('<H',b,0x98,0x20b)
    for i,(name,rva,offset) in enumerate([(b'.text',0x1000,0x400),(b'.rdata',0x2000,0x600),(b'.data',0x3000,0x800),(b'.pdata',0x4000,0xa00)]):
        at=0x188+i*40; b[at:at+len(name)]=name
        struct.pack_into('<IIII',b,at+8,0x200,rva,0x200,offset)
    name=b'GDScript::load_byte_code\0'; b[0x600:0x600+len(name)]=name
    b[0x410:0x417]=b'\x48\x8d\x0d'+struct.pack('<i',0x2000-0x1017)
    b[0x420:0x427]=b'\x48\x8d\x05'+struct.pack('<i',0x3000-0x1027)
    b[0x800:0x820]=bytes(range(32))
    struct.pack_into('<III',b,0xa00,0x1000,0x1100,0)
    return b

class ExecutableTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        out=ROOT/'build/executable-tests'; out.mkdir(parents=True,exist_ok=True)
        compiler=['xcrun','clang++'] if sys.platform=='darwin' else [str(ROOT/'.cache/llvm-mingw-20261104-ucrt-x86_64/bin/clang++.exe')]
        cls.exe=out/('executable-tests' if sys.platform=='darwin' else 'executable-tests.exe')
        subprocess.run(compiler+['-std=c++17','-Os','-I',str(ROOT/'ios'),str(ROOT/'tests/executable_core.cpp'),* ([] if sys.platform=='darwin' else ['-static']),'-o',str(cls.exe)],check=True)
    def test_generic_loader_reference_discovery(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'original.exe'; path.write_bytes(fixture())
            result=subprocess.run([str(self.exe),str(path),str(0x800)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn('candidates=1 expected_location_matches=1',result.stdout)
    def test_malformed_and_unsupported_executables(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'bad.exe'
            samples=[bytearray(),bytearray(b'MZ')]
            for at,value in [(60,0xffffffff),(0x84,0x14c),(0x86,255),(0x188+20,0xfffffffe)]:
                b=fixture(); struct.pack_into('<I',b,at,value); samples.append(b)
            b=fixture(); b[0x600:0x620]=bytes(32); samples.append(b)
            for b in samples:
                path.write_bytes(b)
                self.assertNotEqual(subprocess.run([str(self.exe),str(path)],capture_output=True).returncode,0)
