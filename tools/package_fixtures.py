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
