"""Execute the compiled controller and native Token-2022 programs in memory. No RPC/node/broadcast."""
import base64,json,pathlib
from solders.litesvm import LiteSVM
from solders.pubkey import Pubkey
from solders.keypair import Keypair
from solders.instruction import Instruction,AccountMeta
from solders.message import Message
from solders.transaction import Transaction
from solders.clock import Clock
ROOT=pathlib.Path(__file__).resolve().parents[1]
fixtures=json.loads((ROOT/'tests/fixtures/solana-controller-v1.json').read_text())
key=lambda text:Pubkey.from_string(text)
wallet=lambda seed:Keypair.from_seed(bytes([seed])*32)
def ix(raw):return Instruction(key(raw['program']),base64.b64decode(raw['data']),[AccountMeta(key(a['key']),a['signer'],a['writable']) for a in raw['accounts']])
checks=0
for case in fixtures['cases']:
 vm=LiteSVM();vm.add_program(key(fixtures['program']),base64.b64decode(json.loads((ROOT/'contracts/solana-controller-v1/artifacts/controller.json').read_text())['elf_base64']))
 for name in ['owner','treasury','beneficiary','other']:vm.airdrop(key(fixtures[name]),10**11)
 def run(raws,signer_seed=3,initial=False,time=None,fail=False):
  global checks
  if time is not None:
   c=vm.get_clock();vm.set_clock(Clock(c.slot,c.epoch_start_timestamp,c.epoch,c.leader_schedule_epoch,time))
  payer=wallet(signer_seed);instructions=[ix(raw) for raw in raws];message=Message.new_with_blockhash(instructions,payer.pubkey(),vm.latest_blockhash());signers=[payer]
  if initial:signers.append(wallet(4))
  result=vm.send_transaction(Transaction(signers,message,vm.latest_blockhash()));failed=hasattr(result,'err');checks+=1
  assert failed==fail,(case['name'],'expected failure' if fail else 'expected success',str(result)[:4000]);vm.expire_blockhash()
 run(case['instructions'],initial=True,time=1000)
 for op in case['operations']:run(op['instructions'],op.get('signer',3),time=op.get('time'),fail=op.get('fail',False))
 mint=vm.get_account(key(fixtures['mint']));expected=case['expected'];data=bytes(mint.data)
 def authority(offset):return str(Pubkey.from_bytes(data[offset+4:offset+36])) if int.from_bytes(data[offset:offset+4],'little') else None
 assert authority(0)==expected['mint_authority'];assert authority(46)==expected['freeze_authority'];assert int.from_bytes(data[36:44],'little')==expected.get('supply',10000)
 assert case['q']['metadata_uri'].encode() in data
 for who in ['owner','beneficiary']:
  if who+'_balance' in expected:
   account=vm.get_account(key(fixtures[who+'_ata']));assert account is not None;assert int.from_bytes(bytes(account.data)[64:72],'little')==expected[who+'_balance']
   if who=='owner':assert (bytes(account.data)[108]==2)==expected.get('owner_frozen',False)
 if expected.get('vesting'):
  state=bytes(vm.get_account(key(expected['vesting'])).data);assert state[:4]==b'VST1';assert int.from_bytes(state[172:180],'little')==expected['released']
 print('PASS',case['name'],flush=True)
print(json.dumps({'result':'passed','cases':len(fixtures['cases']),'instruction_transactions':checks,'rpc_calls':0,'broadcasts':0}),flush=True)
