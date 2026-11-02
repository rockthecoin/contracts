"""Compare the existing mainnet controller with its published ELF; read RPC only."""
import argparse,base64,hashlib,json,pathlib,urllib.request
from solders.pubkey import Pubkey

parser=argparse.ArgumentParser()
parser.add_argument('--rpc',default='https://api.mainnet-beta.solana.com')
parser.add_argument('--output')
args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
manifest=json.loads((root/'deployments.json').read_text())
network=next(c for c in manifest['networks'] if c['family']=='solana')
program=network['contracts'][0]['address']
def rpc(method,params):
    body=json.dumps({'jsonrpc':'2.0','id':1,'method':method,'params':params}).encode()
    request=urllib.request.Request(args.rpc,data=body,headers={'Content-Type':'application/json','User-Agent':'RockTheCoin-contract-verifier'})
    response=json.load(urllib.request.urlopen(request,timeout=30))
    if 'error' in response:raise RuntimeError('Read RPC request was rejected: '+method)
    return response['result']
def account(address):
    result=rpc('getAccountInfo',[address,{'encoding':'base64','commitment':'finalized'}])
    assert result['value'] is not None,'Missing account'
    value=result['value'];return value,base64.b64decode(value['data'][0]),result['context']['slot']
account_info,data,slot=account(program)
loader='BPFLoaderUpgradeab1e11111111111111111111111'
assert account_info['executable'] and account_info['owner']==loader
assert len(data)==36 and int.from_bytes(data[:4],'little')==2
program_data=str(Pubkey.from_bytes(data[4:36]))
data_info,raw,data_slot=account(program_data)
assert data_info['owner']==loader and int.from_bytes(raw[:4],'little')==3 and len(raw)>=45
expected=(root/'contracts/solana-controller-v1/artifacts/rockthecoin_controller.so').read_bytes()
assert raw[45:45+len(expected)]==expected,'On-chain controller differs from the published executable'
assert not raw[45+len(expected):].strip(b'\0'),'Unexpected executable tail'
result={'program':program,'program_data':program_data,'finalized_slot':data_slot,'elf_sha256':hashlib.sha256(expected).hexdigest(),'executable_matches':True,'immutable':raw[12]==0,'upgrade_authority':None if raw[12]==0 else str(Pubkey.from_bytes(raw[13:45])),'broadcasts':0}
text=json.dumps(result,indent=2)+'\n'
if args.output:pathlib.Path(args.output).write_text(text)
else:print(text,end='')
