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
            def fixture(include_framework=True, game=False):
                with zipfile.ZipFile(path,'w') as z:
                    info={'CFBundleExecutable':'player','MinimumOSVersion':'15.0'}
                    z.writestr('Payload/player.app/Info.plist',plistlib.dumps(info))
                    z.writestr('Payload/player.app/player',struct.pack('<8I',0xfeedfacf,0x100000c,0,2,0,0,0,0))
                    if include_framework:
                        info['CFBundleExecutable']='Godot3Runtime'
                        prefix='Payload/player.app/Frameworks/Godot3Runtime.framework/'
                        z.writestr(prefix+'Info.plist',plistlib.dumps(info))
                        z.writestr(prefix+'Godot3Runtime',struct.pack('<8I',0xfeedfacf,0x100000c,0,6,0,0,0,0))
                        for name in ['LICENSE.txt','COPYRIGHT.txt']:z.writestr(prefix+name,'preserved license fixture')
                    z.writestr('Payload/player.app/player.pck',b'game' if game else b'')
            fixture();self.assertEqual(tool.audit(path)['package_checks'],'passed')
            fixture(include_framework=False)
            with self.assertRaises(KeyError):tool.audit(path)
            fixture(game=True)
            with self.assertRaisesRegex(RuntimeError,'Unexpected bundled game'):tool.audit(path)
