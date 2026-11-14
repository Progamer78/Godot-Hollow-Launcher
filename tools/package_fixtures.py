"""Create APK import fixtures from the original desktop proof PCK only."""
from pathlib import Path
import struct
import zipfile

def apk(pack, destination):
    with pack.open('rb') as source, zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED) as output:
        magic,version,major,minor,patch=struct.unpack('<5I',source.read(20))
        assert magic==0x43504447 and version in [1,2,3,4]
        base=0
        if version>=2:
            flags,base=struct.unpack('<IQ',source.read(12));assert flags&1==0
        if version>=3:
            directory,=struct.unpack('<Q',source.read(8));source.seek(directory)
        else:source.seek(84 if version==1 else 96)
        count,=struct.unpack('<I',source.read(4))
        entries=[]
        for _ in range(count):
            length,=struct.unpack('<I',source.read(4));name=source.read(length).rstrip(b'\0').decode().removeprefix('res://')
            offset,size=struct.unpack('<QQ',source.read(16));source.read(16)
            if version>=2:assert source.read(4)==b'\0'*4
            entries.append((name,base+offset,size))
        for name,offset,size in entries:
            assert size<16*1024*1024,'Fixture is intended only for the small original proof games'
            source.seek(offset);output.writestr('assets/'+name,source.read(size))
        output.writestr('assets/_cl_',b'ignored exporter arguments')
        output.writestr('lib/arm64-v8a/libgame.so',b'fixture: must never be imported or executed')

if __name__=='__main__':
    output=Path('build/archive-tests');output.mkdir(parents=True,exist_ok=True)
    apk(Path('build/proof/movement.pck'),output/'movement-assets.apk')
    import base64, hashlib, importlib.util
    spec=importlib.util.spec_from_file_location('exe_fixture',Path(__file__).resolve().parents[1]/'tests/test_executable.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    (output/'original-fixture.exe').write_bytes(module.fixture())
    original4=module.fixture()
    original4[0x600:0x640]=bytes(64)
    anchor=b'PackedSourcePCK::try_open_pack\0'
    original4[0x600:0x600+len(anchor)]=anchor
    (output/'original4-fixture.exe').write_bytes(original4)
    encrypted=base64.b64decode('R0RFQwEAAAARnnc/7CJArt7Q9wRTTsAaDAAAAAAAAACQ/7fMiwOnJmMloYFnmBpl')
    payloads=[('res://project.godot',b'config_version=4\n'),('res://proof.gde',encrypted)]
    header=b'GDPC'+struct.pack('<IIII',1,3,6,3)+bytes(64)
    offset=84+4+sum(4+len(name.encode())+32 for name,_ in payloads)
    directory=struct.pack('<I',len(payloads))
    for name,data in payloads:
        name=name.encode();directory+=struct.pack('<I',len(name))+name+struct.pack('<QQ',offset,len(data))+hashlib.md5(data).digest();offset+=len(data)
    (output/'encrypted-fixture.pck').write_bytes(header+directory+b''.join(data for _,data in payloads))
