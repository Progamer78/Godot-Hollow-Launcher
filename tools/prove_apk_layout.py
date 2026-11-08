"""Prove loose-APK asset packaging with native extraction and stock engines.

This independently verifies the pack layout, not the uncompiled Swift importer.
Only the original sample game packs are used.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import struct
import subprocess
import zipfile
from package_fixtures import apk

ROOT=Path(__file__).resolve().parents[1]

def prove(editor,major):
    source=ROOT/('build/proof/movement.pck' if major==4 else 'build/godot3-proof/godot3.pck')
    output=ROOT/'build/apk-layout-proof'/str(major);output.mkdir(parents=True,exist_ok=True)
    archive=output/'game.apk';apk(source,archive)
    cli=ROOT/'build/archive-tests'/('archive-tests.exe' if os.name=='nt' else 'archive-tests')
    listing=subprocess.check_output([str(cli),'list',str(archive)]).decode().splitlines()
    positions={row.split('\t',3)[3]:row.split('\t',3)[1:3] for row in listing}
    with zipfile.ZipFile(archive) as z:
        entries=[(i.filename.removeprefix('assets/'),i.file_size) for i in z.infolist() if i.filename.startswith('assets/') and i.filename!='assets/_cl_']
    header_size=96 if major==4 else 84
    directory_size=4+sum(4+6+len(n.encode())+(36 if major==4 else 32) for n,s in entries)
    pack=output/'wrapped.pck';offset=header_size+directory_size;checksums=[];total=0
    with pack.open('wb+') as file:
        header=struct.pack('<5I',0x43504447,2 if major==4 else 1,major,0,0)
        file.write(header+b'\0'*(header_size-len(header)));file.write(struct.pack('<I',len(entries)))
        for name,size in entries:
            encoded=('res://'+name).encode();file.write(struct.pack('<I',len(encoded))+encoded+struct.pack('<QQ',offset,size))
            checksums.append(file.tell());file.write(b'\0'*(20 if major==4 else 16));offset+=size
        for index,(name,size) in enumerate(entries):
            temp=output/'asset.tmp'
            entry_position,entry_number=positions['assets/'+name]
            subprocess.run([str(cli),'extract_at',str(archive),'assets/'+name,str(temp),str(16<<30),entry_position,entry_number],check=True,capture_output=True)
            digest=hashlib.md5()
            with temp.open('rb') as asset:
                while block:=asset.read(1024*1024):digest.update(block);file.write(block);total+=len(block)
            position=file.tell();file.seek(checksums[index]);file.write(digest.digest());file.seek(position);temp.unlink()
    env=os.environ.copy()
    for key in ['APPDATA','LOCALAPPDATA']:
        directory=output/key.lower();directory.mkdir(exist_ok=True);env[key]=str(directory)
    args=['--headless','--main-pack',str(pack),'--','--player-proof'] if major==4 else ['--no-window','--audio-driver','Dummy','--video-driver','GLES2','--main-pack',str(pack),'--','--player-proof']
    result=subprocess.run([str(editor.resolve()),*args],cwd=output,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=90)
    text=result.stdout+result.stderr;(output/'run.log').write_text(text,encoding='utf-8')
    if result.returncode or 'SCRIPT ERROR' in text or 'Failed to load' in text or 'PROOF FAIL' in text:raise RuntimeError(text[-4000:])
    if major==3 and 'PLAYER_PROOF godot3 PASS' not in text:raise RuntimeError('Godot 3 proof did not execute')
    if major==4 and 'PLAYER_PROOF movement PASS' not in text:raise RuntimeError('Godot 4 proof did not execute')
    report={'engine_major':major,'exit':result.returncode,'asset_bytes':total,'assets':len(entries),'native_zip_extraction':'passed','pack_layout_execution':'passed','swift_importer':'not run; requires macOS/iOS tests','original_assets':'unchanged'}
    (output/'results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('editor',type=Path);parser.add_argument('--major',type=int,choices=[3,4],required=True);args=parser.parse_args();prove(args.editor,args.major)
