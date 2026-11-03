#!/usr/bin/env python3
"""Read-only Cardano mainnet reference verification through the public Koios API."""
import datetime,hashlib,json,pathlib,time,urllib.request
root=pathlib.Path(__file__).resolve().parents[1];network=next(n for n in json.loads((root/'deployments.json').read_text())['networks'] if n['family']=='cardano');base='https://api.koios.rest/api/v1'
def read(path,body=None):
 request=urllib.request.Request(base+path,data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json','User-Agent':'RockTheCoin-contract-verification/1.2'})
 with urllib.request.urlopen(request,timeout=20) as response:return json.load(response)
genesis=read('/genesis')[0];assert str(genesis['networkmagic'])=='764824073' and genesis['networkid']=='Mainnet'
tip=read('/tip')[0];assert time.time()-tip['block_time']<180,'A fresh mainnet tip is required'
refs=[c['address'] for c in network['contracts']];rows=read('/utxo_info',{'_utxo_refs':refs,'_extended':True});by_ref={r['tx_hash']+'#'+str(r['tx_index']):r for r in rows};results=[]
for entry in network['contracts']:
 row=by_ref[entry['address']];assert row['is_spent'] is False
 script=json.loads((root/entry['artifact']).read_text())['scripts'][entry['script_id']];actual=row['reference_script'];assert actual['type']=='plutusV3' and actual['hash']==entry['script_hash']==script['hash'] and actual['bytes']==script['cbor'];assert hashlib.blake2b(b'\x03'+bytes.fromhex(actual['bytes']),digest_size=28).hexdigest()==script['hash']
 assert row['address']==entry['owner_address'];confirmations=tip['block_no']-row['block_height']+1;assert confirmations>=6
 results.append({'script_id':entry['script_id'],'reference':entry['address'],'script_hash':script['hash'],'block_height':row['block_height'],'confirmations':confirmations,'unspent':True,'exact_script_match':True})
print(json.dumps({'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'network':'Cardano mainnet','result':'passed','references':results,'broadcasts':0},indent=2))
