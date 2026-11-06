"""Read-only verification of deployed Algorand programs and canonical creation IDs."""
import argparse,base64,hashlib,json,pathlib,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--rpc',default='https://mainnet-api.algonode.cloud');p.add_argument('--indexer',default='https://mainnet-idx.algonode.cloud');args=p.parse_args()
def get(base,path):
 with urllib.request.urlopen(base.rstrip('/')+path,timeout=30) as r:return json.load(r)
def address(raw):
 key=base64.b64decode(raw,validate=True);assert len(key)==32
 return base64.b32encode(key+hashlib.new('sha512_256',key).digest()[-4:]).decode().rstrip('=')
mapping=json.loads((ROOT/'deployments.json').read_text());network=next(n for n in mapping['networks'] if n['family']=='algorand')
params=get(args.rpc,'/v2/transactions/params');assert params['genesis-hash']==network['genesis_hash'] and params['genesis-id']==network['genesis_id']
report={'network':network['genesis_id'],'current_round':params['last-round'],'applications':[],'broadcasts':0}
for item in network['contracts']:
 app=get(args.rpc,'/v2/applications/'+item['application_id']);state=app['params'];artifact=json.loads((ROOT/item['artifact']).read_text())
 program=artifact['apps'][item['kind']] if 'apps' in artifact else artifact
 assert str(app['id'])==item['application_id']
 assert state['approval-program']==program['approval_program'] and state['clear-state-program']==program['clear_program']
 assert state.get('extra-program-pages',0)==program['extra_pages']
 assert state['global-state-schema']=={'num-uint':program['schema']['global']['ints'],'num-byte-slice':program['schema']['global']['bytes']}
 assert state['local-state-schema']=={'num-uint':0,'num-byte-slice':0}
 assert state['creator']==item['owner']
 globals={base64.b64decode(k['key']).decode():k['value'] for k in state['global-state']}
 for key in ('owner','treasury'):assert address(globals[key]['bytes'])==item[key],key+' mismatch'
 assert address(globals['signer']['bytes'])==item['quote_signer']
 assert globals['version']['uint']==item['version'] and globals.get('paused',{}).get('uint',0)==0
 tx=get(args.indexer,'/v2/transactions/'+item['transaction_hash'])['transaction'];round=tx['confirmed-round']
 assert str(tx['created-application-index'])==item['application_id'] and tx['sender']==item['owner']
 txids=get(args.rpc,'/v2/blocks/'+str(round)+'/txids')['blockTxids'];position=txids.index(item['transaction_hash'])
 block=get(args.rpc,'/v2/blocks/'+str(round))['block'];assert str(block['txns'][position]['apid'])==item['application_id']
 report['applications'].append({'kind':item['kind'],'application_id':item['application_id'],'version':item['version'],'approval_sha256':program['approval_sha256'],'owner':item['owner'],'deployment_round':round,'canonical_creation':True,'verified':True})
print(json.dumps(report,indent=2))
