from pathlib import Path
import importlib.util
import plistlib
import struct
import tempfile
import unittest
import zipfile

class IPAAuditTests(unittest.TestCase):
    def test_package_images_framework_and_no_embedded_game(self):
        root=Path(__file__).resolve().parents[1]
        spec=importlib.util.spec_from_file_location('ipa_auditor',root/'tools/audit_ipa.py')
        tool=importlib.util.module_from_spec(spec);spec.loader.exec_module(tool)
        with tempfile.TemporaryDirectory() as temporary:
            path=Path(temporary)/'fixture.ipa'
            def fixture(include_framework=True, game=False, dotnet=False, native_host=True, missing_dependency=False):
                with zipfile.ZipFile(path,'w') as z:
                    info={'CFBundleExecutable':'player','MinimumOSVersion':'15.0'}
                    if dotnet:info['HollowDotnetRuntime']='10.0.15'
                    z.writestr('Payload/player.app/Info.plist',plistlib.dumps(info))
                    z.writestr('Payload/player.app/player',struct.pack('<8I',0xfeedfacf,0x100000c,0,2,0,0,0,0)+(b'HOLLOW_DOTNET:' if native_host else b''))
                    if include_framework:
                        info['CFBundleExecutable']='Godot3Runtime'
                        prefix='Payload/player.app/Frameworks/Godot3Runtime.framework/'
                        z.writestr(prefix+'Info.plist',plistlib.dumps(info))
                        z.writestr(prefix+'Godot3Runtime',struct.pack('<8I',0xfeedfacf,0x100000c,0,6,0,0,0,0))
                        for name in ['LICENSE.txt','COPYRIGHT.txt']:z.writestr(prefix+name,'preserved license fixture')
                    z.writestr('Payload/player.app/player.pck',b'game' if game else b'')
                    if dotnet:
                        for name in ['System.Private.CoreLib.dll','GodotSharp.dll']:
                            z.writestr('Payload/player.app/Managed/'+name,b'MZ'+bytes(126))
                        for component in ['Globalization.Native','IO.Compression.Native','Native','Net.Security.Native','Security.Cryptography.Native.Apple']:
                            if missing_dependency and component=='Native':continue
                            z.writestr('Payload/player.app/Frameworks/libSystem.'+component+'.dylib',struct.pack('<8I',0xfeedfacf,0x100000c,0,6,0,0,0,0))
                        for notice in ['Mono-LICENSE.TXT','Mono-THIRD-PARTY-NOTICES.TXT']:
                            z.writestr('Payload/player.app/'+notice,'preserved runtime license fixture')
            fixture();self.assertEqual(tool.audit(path)['package_checks'],'passed')
            fixture(include_framework=False)
            with self.assertRaises(KeyError):tool.audit(path)
            fixture(game=True)
            with self.assertRaisesRegex(RuntimeError,'Unexpected bundled game'):tool.audit(path)
            fixture(dotnet=True)
            self.assertEqual(tool.audit(path)['dotnet_runtime'],'10.0.15')
            fixture(dotnet=True,native_host=False)
            with self.assertRaisesRegex(RuntimeError,'without the native interpreter host'):tool.audit(path)
            fixture(dotnet=True,missing_dependency=True)
            with self.assertRaises(KeyError):tool.audit(path)
