#!/usr/bin/env python3
"""Install the official checksum-pinned Linux x86-64 Sui CLI, never a wallet."""
import hashlib,json,os,pathlib,shutil,tarfile,tempfile,urllib.request
root=pathlib.Path(__file__).resolve().parents[1]
pins=json.loads((root/'toolchains/sui.json').read_text())
destination=root/'.toolchains/sui';destination.parent.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='rtc-sui-toolchain-') as folder:
 archive=pathlib.Path(folder)/'sui.tgz';digest=hashlib.sha256();size=0
 with urllib.request.urlopen(urllib.request.Request(pins['url'],headers={'User-Agent':'RockTheCoin-contract-verification'}),timeout=60) as source,archive.open('wb') as out:
  while chunk:=source.read(1024*1024):
   size+=len(chunk)
   if size>1_300_000_000:raise RuntimeError('Archive size limit exceeded')
   digest.update(chunk);out.write(chunk)
 assert digest.hexdigest()==pins['archive_sha256'],'Archive checksum mismatch'
 binary=pathlib.Path(folder)/'sui';matches=0
 with tarfile.open(archive,'r:gz') as tar:
  for entry in tar:
   if pathlib.PurePosixPath(entry.name).name!='sui' or not entry.isfile():continue
   matches+=1;assert entry.size<300_000_000,'Executable size limit exceeded'
   with tar.extractfile(entry) as source,binary.open('wb') as out:shutil.copyfileobj(source,out)
 assert matches==1,'Expected one Sui executable'
 assert hashlib.sha256(binary.read_bytes()).hexdigest()==pins['binary_sha256'],'Executable checksum mismatch'
 os.chmod(binary,0o755);os.replace(binary,destination)
print('Installed checksum-pinned Sui CLI at .toolchains/sui')
