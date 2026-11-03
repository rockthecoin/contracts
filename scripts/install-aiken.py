#!/usr/bin/env python3
"""Install the checksum-pinned official Aiken Linux x86-64 binary."""
import hashlib,io,json,os,pathlib,sys,tarfile,urllib.request
root=pathlib.Path(__file__).resolve().parents[1];pin=json.loads((root/'toolchains/aiken.json').read_text());target=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else root/'.toolchains/aiken')
if target.exists() and hashlib.sha256(target.read_bytes()).hexdigest()==pin['binary_sha256']:print(target.resolve());raise SystemExit(0)
with urllib.request.urlopen(pin['url'],timeout=60) as response:data=response.read(50_000_001)
if len(data)>50_000_000 or hashlib.sha256(data).hexdigest()!=pin['archive_sha256']:raise SystemExit('Aiken release archive checksum mismatch')
with tarfile.open(fileobj=io.BytesIO(data),mode='r:gz') as archive:
 candidates=[m for m in archive.getmembers() if m.isfile() and pathlib.PurePosixPath(m.name).name=='aiken'];assert len(candidates)==1
 stream=archive.extractfile(candidates[0]);assert stream is not None;binary=stream.read(50_000_001)
assert hashlib.sha256(binary).hexdigest()==pin['binary_sha256'],'Aiken binary checksum mismatch'
target.parent.mkdir(parents=True,exist_ok=True);temporary=target.with_suffix('.download');temporary.write_bytes(binary);temporary.chmod(0o755);os.replace(temporary,target);print(target.resolve())
