//! Immutable, non-custodial mint caps, transfer-fee ceilings and token vesting.
//! All keys are supplied by creators. There is no platform administrator or withdrawal key.
use solana_program::{account_info::{next_account_info,AccountInfo},clock::Clock,entrypoint,entrypoint::ProgramResult,instruction::{AccountMeta,Instruction},program::{invoke,invoke_signed},program_error::ProgramError,pubkey::Pubkey,rent::Rent,system_instruction,system_program,sysvar::Sysvar};
entrypoint!(process_instruction);
const CLASSIC:Pubkey=solana_program::pubkey!("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
const EXTENSIONS:Pubkey=solana_program::pubkey!("TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb");
fn invalid()->ProgramError{ProgramError::InvalidInstructionData}
struct Reader<'a>{data:&'a[u8],at:usize}
impl<'a> Reader<'a>{
 fn take(&mut self,n:usize)->Result<&'a[u8],ProgramError>{let end=self.at.checked_add(n).ok_or_else(invalid)?;let value=self.data.get(self.at..end).ok_or_else(invalid)?;self.at=end;Ok(value)}
 fn key(&mut self)->Result<Pubkey,ProgramError>{Ok(Pubkey::new_from_array(self.take(32)?.try_into().map_err(|_|invalid())?))}
 fn u64(&mut self)->Result<u64,ProgramError>{Ok(u64::from_le_bytes(self.take(8)?.try_into().map_err(|_|invalid())?))}
 fn u16(&mut self)->Result<u16,ProgramError>{Ok(u16::from_le_bytes(self.take(2)?.try_into().map_err(|_|invalid())?))}
 fn byte(&mut self)->Result<u8,ProgramError>{Ok(self.take(1)?[0])}
 fn done(&self)->ProgramResult{if self.at==self.data.len(){Ok(())}else{Err(invalid())}}
}
fn append_key(out:&mut Vec<u8>,key:&Pubkey){out.extend_from_slice(key.as_ref());}
fn append_u64(out:&mut Vec<u8>,value:u64){out.extend_from_slice(&value.to_le_bytes());}
fn signer(account:&AccountInfo)->ProgramResult{if account.is_signer{Ok(())}else{Err(ProgramError::MissingRequiredSignature)}}
fn token_mint(mint:&AccountInfo,token:&AccountInfo)->ProgramResult{
 if (*token.key!=CLASSIC&&*token.key!=EXTENSIONS)||mint.owner!=token.key||mint.data_len()<82{return Err(ProgramError::IncorrectProgramId)}
 if mint.try_borrow_data()?[45]==0{return Err(ProgramError::UninitializedAccount)}Ok(())
}
fn mint_supply(mint:&AccountInfo)->Result<u64,ProgramError>{Ok(u64::from_le_bytes(mint.try_borrow_data()?[36..44].try_into().map_err(|_|invalid())?))}
fn create_state<'a>(program:&Pubkey,payer:&AccountInfo<'a>,state:&AccountInfo<'a>,system:&AccountInfo<'a>,seeds:&[&[u8]],size:usize)->ProgramResult{
 signer(payer)?;if system.key!=&system_program::id()||state.owner!=system.key||state.data_len()!=0{return Err(ProgramError::AccountAlreadyInitialized)}
 if Pubkey::create_program_address(seeds,program).map_err(|_|invalid())?!=*state.key{return Err(ProgramError::InvalidSeeds)}
 let rent=Rent::get()?.minimum_balance(size);
 if state.lamports()==0{invoke_signed(&system_instruction::create_account(payer.key,state.key,rent,size as u64,program),&[payer.clone(),state.clone(),system.clone()],&[seeds])?;}
 else{
  if state.lamports()<rent{invoke(&system_instruction::transfer(payer.key,state.key,rent-state.lamports()),&[payer.clone(),state.clone(),system.clone()])?;}
  invoke_signed(&system_instruction::allocate(state.key,size as u64),&[state.clone(),system.clone()],&[seeds])?;
  invoke_signed(&system_instruction::assign(state.key,program),&[state.clone(),system.clone()],&[seeds])?;
 }Ok(())
}
fn set_authority<'a>(mint:&AccountInfo<'a>,current:&AccountInfo<'a>,token:&AccountInfo<'a>,kind:u8,next:Option<&Pubkey>,seeds:Option<&[&[u8]]>)->ProgramResult{
 let mut data=vec![6,kind,if next.is_some(){1}else{0}];data.extend_from_slice(next.unwrap_or(&Pubkey::default()).as_ref());
 let ix=Instruction{program_id:*token.key,accounts:vec![AccountMeta::new(*mint.key,false),AccountMeta::new_readonly(*current.key,true)],data};
 if let Some(seeds)=seeds{invoke_signed(&ix,&[mint.clone(),current.clone(),token.clone()],&[seeds])}else{invoke(&ix,&[mint.clone(),current.clone(),token.clone()])}
}
fn state_reader<'a>(data:&'a[u8],magic:&[u8])->Result<Reader<'a>,ProgramError>{let mut r=Reader{data,at:0};if r.take(4)?!=magic{return Err(ProgramError::InvalidAccountData)}Ok(r)}
fn process_instruction(program:&Pubkey,accounts:&[AccountInfo],data:&[u8])->ProgramResult{
 let mut r=Reader{data,at:0};match r.byte()?{
  0=>init_cap(program,accounts,&mut r),1=>mint_capped(program,accounts,&mut r),2=>cap_owner(program,accounts,&mut r),
  3=>init_vesting(program,accounts,&mut r),4=>release_vesting(program,accounts,&mut r),
  5=>init_fee(program,accounts,&mut r),6=>set_fee(program,accounts,&mut r),7=>fee_owner(program,accounts,&mut r),
  _=>Err(invalid())
 }
}
fn init_cap(program:&Pubkey,accounts:&[AccountInfo],r:&mut Reader)->ProgramResult{
 let owner=r.key()?;let maximum=r.u64()?;let lifetime=r.byte()?;r.done()?;if owner==Pubkey::default()||maximum==0||lifetime>1{return Err(invalid())}
 let a=&mut accounts.iter();let payer=next_account_info(a)?;let mint=next_account_info(a)?;let state=next_account_info(a)?;let system=next_account_info(a)?;let token=next_account_info(a)?;
 token_mint(mint,token)?;let supply=mint_supply(mint)?;if maximum<supply{return Err(invalid())}
 let (expected,bump)=Pubkey::find_program_address(&[b"cap",mint.key.as_ref()],program);if expected!=*state.key{return Err(ProgramError::InvalidSeeds)}
 let seed_bump=[bump];let seeds:&[&[u8]]=&[b"cap",mint.key.as_ref(),&seed_bump];create_state(program,payer,state,system,seeds,117)?;
 set_authority(mint,payer,token,0,Some(state.key),None)?;
 let mut out=b"CAP1".to_vec();append_key(&mut out,mint.key);append_key(&mut out,token.key);append_key(&mut out,&owner);append_u64(&mut out,maximum);append_u64(&mut out,supply);out.push(lifetime);state.try_borrow_mut_data()?.copy_from_slice(&out);Ok(())
}
fn read_cap(program:&Pubkey,state:&AccountInfo)->Result<(Pubkey,Pubkey,Pubkey,u64,u64,u8,u8),ProgramError>{
 if state.owner!=program{return Err(ProgramError::IllegalOwner)}let data=state.try_borrow_data()?;let mut r=state_reader(&data,b"CAP1")?;
 let mint=r.key()?;let token=r.key()?;let owner=r.key()?;let maximum=r.u64()?;let issued=r.u64()?;let lifetime=r.byte()?;r.done()?;
 let (expected,bump)=Pubkey::find_program_address(&[b"cap",mint.as_ref()],program);if expected!=*state.key{return Err(ProgramError::InvalidSeeds)}Ok((mint,token,owner,maximum,issued,lifetime,bump))
}
fn mint_capped(program:&Pubkey,accounts:&[AccountInfo],r:&mut Reader)->ProgramResult{
 let amount=r.u64()?;r.done()?;if amount==0{return Err(invalid())}
 let a=&mut accounts.iter();let authority=next_account_info(a)?;let state=next_account_info(a)?;let mint=next_account_info(a)?;let destination=next_account_info(a)?;let token=next_account_info(a)?;
 signer(authority)?;let (key,token_key,owner,maximum,issued,lifetime,bump)=read_cap(program,state)?;token_mint(mint,token)?;
 if key!=*mint.key||token_key!=*token.key||owner!=*authority.key{return Err(ProgramError::IllegalOwner)}
 let used=if lifetime==1{issued}else{mint_supply(mint)?};if amount>maximum.checked_sub(used).ok_or_else(invalid)?{return Err(ProgramError::InsufficientFunds)}
 let mut data=vec![14];append_u64(&mut data,amount);data.push(mint.try_borrow_data()?[44]);let bump=[bump];
 invoke_signed(&Instruction{program_id:*token.key,accounts:vec![AccountMeta::new(*mint.key,false),AccountMeta::new(*destination.key,false),AccountMeta::new_readonly(*state.key,true)],data},&[mint.clone(),destination.clone(),state.clone(),token.clone()],&[&[b"cap",mint.key.as_ref(),&bump]])?;
 if lifetime==1{state.try_borrow_mut_data()?[108..116].copy_from_slice(&issued.checked_add(amount).ok_or_else(invalid)?.to_le_bytes());}Ok(())
}
fn cap_owner(program:&Pubkey,accounts:&[AccountInfo],r:&mut Reader)->ProgramResult{
 let next=r.key()?;r.done()?;let a=&mut accounts.iter();let authority=next_account_info(a)?;let state=next_account_info(a)?;let mint=next_account_info(a)?;let token=next_account_info(a)?;
 signer(authority)?;let (key,token_key,owner,_,_,_,bump)=read_cap(program,state)?;if key!=*mint.key||token_key!=*token.key||owner!=*authority.key{return Err(ProgramError::IllegalOwner)}
 if next==Pubkey::default(){let bump=[bump];set_authority(mint,state,token,0,None,Some(&[b"cap",mint.key.as_ref(),&bump]))?;}
 state.try_borrow_mut_data()?[68..100].copy_from_slice(next.as_ref());Ok(())
}
fn init_vesting(program:&Pubkey,accounts:&[AccountInfo],r:&mut Reader)->ProgramResult{
 let nonce=r.key()?;let beneficiary=r.key()?;let amount=r.u64()?;let start=r.u64()?;let cliff=r.u64()?;let end=r.u64()?;r.done()?;
 if beneficiary==Pubkey::default()||amount==0||start==0||start>cliff||cliff>end{return Err(invalid())}
 let a=&mut accounts.iter();let payer=next_account_info(a)?;let mint=next_account_info(a)?;let state=next_account_info(a)?;let system=next_account_info(a)?;let token=next_account_info(a)?;token_mint(mint,token)?;
 let (expected,bump)=Pubkey::find_program_address(&[b"vest",mint.key.as_ref(),payer.key.as_ref(),nonce.as_ref()],program);if expected!=*state.key{return Err(ProgramError::InvalidSeeds)}let bump=[bump];
 create_state(program,payer,state,system,&[b"vest",mint.key.as_ref(),payer.key.as_ref(),nonce.as_ref(),&bump],204)?;
 let mut out=b"VST1".to_vec();for key in [mint.key,token.key,&beneficiary,payer.key,&nonce]{append_key(&mut out,key)}for v in [amount,0,start,cliff,end]{append_u64(&mut out,v)}state.try_borrow_mut_data()?.copy_from_slice(&out);Ok(())
}
fn release_vesting(program:&Pubkey,accounts:&[AccountInfo],r:&mut Reader)->ProgramResult{
 r.done()?;let a=&mut accounts.iter();let state=next_account_info(a)?;let mint=next_account_info(a)?;let source=next_account_info(a)?;let destination=next_account_info(a)?;let token=next_account_info(a)?;token_mint(mint,token)?;
 if state.owner!=program{return Err(ProgramError::IllegalOwner)}let data=state.try_borrow_data()?;let mut s=state_reader(&data,b"VST1")?;
 let key=s.key()?;let token_key=s.key()?;let beneficiary=s.key()?;let creator=s.key()?;let nonce=s.key()?;let amount=s.u64()?;let released=s.u64()?;let start=s.u64()?;let cliff=s.u64()?;let end=s.u64()?;s.done()?;drop(data);
 if key!=*mint.key||token_key!=*token.key||source.owner!=token.key||destination.owner!=token.key||destination.data_len()<165{return Err(ProgramError::InvalidAccountData)}
 {let d=destination.try_borrow_data()?;if &d[0..32]!=mint.key.as_ref()||&d[32..64]!=beneficiary.as_ref(){return Err(ProgramError::IllegalOwner)}}
 let (expected,bump)=Pubkey::find_program_address(&[b"vest",mint.key.as_ref(),creator.as_ref(),nonce.as_ref()],program);if expected!=*state.key{return Err(ProgramError::InvalidSeeds)}
 let now=Clock::get()?.unix_timestamp;if now<0||(now as u64)<cliff{return Err(ProgramError::InsufficientFunds)}let now=now as u64;
 let vested=if now>=end{amount}else{((amount as u128)*((now-start)as u128)/((end-start)as u128))as u64};let payout=vested.checked_sub(released).ok_or_else(invalid)?;if payout==0{return Err(ProgramError::InsufficientFunds)}
 let mut data=vec![12];append_u64(&mut data,payout);data.push(mint.try_borrow_data()?[44]);
 let mut metas=vec![AccountMeta::new(*source.key,false),AccountMeta::new_readonly(*mint.key,false),AccountMeta::new(*destination.key,false),AccountMeta::new_readonly(*state.key,true)];
 for extra in a{metas.push(if extra.is_writable{AccountMeta::new(*extra.key,extra.is_signer)}else{AccountMeta::new_readonly(*extra.key,extra.is_signer)})}
 let bump=[bump];invoke_signed(&Instruction{program_id:*token.key,accounts:metas,data},accounts,&[&[b"vest",mint.key.as_ref(),creator.as_ref(),nonce.as_ref(),&bump]])?;
 state.try_borrow_mut_data()?[172..180].copy_from_slice(&vested.to_le_bytes());Ok(())
}
fn init_fee(program:&Pubkey,accounts:&[AccountInfo],r:&mut Reader)->ProgramResult{
 let owner=r.key()?;let maximum_bps=r.u16()?;let maximum_fee=r.u64()?;r.done()?;if owner==Pubkey::default()||maximum_bps>10000{return Err(invalid())}
 let a=&mut accounts.iter();let payer=next_account_info(a)?;let mint=next_account_info(a)?;let state=next_account_info(a)?;let system=next_account_info(a)?;let token=next_account_info(a)?;token_mint(mint,token)?;if *token.key!=EXTENSIONS{return Err(ProgramError::IncorrectProgramId)}
 {let data=mint.try_borrow_data()?;let mut at=166;let mut found=false;while at+4<=data.len(){let kind=u16::from_le_bytes(data[at..at+2].try_into().map_err(|_|invalid())?);let size=u16::from_le_bytes(data[at+2..at+4].try_into().map_err(|_|invalid())?)as usize;at+=4;let d=data.get(at..at+size).ok_or_else(invalid)?;if kind==1{if d.len()!=108{return Err(invalid())}for offset in [72,90]{let fee=u64::from_le_bytes(d[offset+8..offset+16].try_into().map_err(|_|invalid())?);let bps=u16::from_le_bytes(d[offset+16..offset+18].try_into().map_err(|_|invalid())?);if fee>maximum_fee||bps>maximum_bps{return Err(invalid())}}found=true;break}at+=size;}if !found{return Err(invalid())}}
 let (expected,bump)=Pubkey::find_program_address(&[b"fee",mint.key.as_ref()],program);if expected!=*state.key{return Err(ProgramError::InvalidSeeds)}let bump=[bump];create_state(program,payer,state,system,&[b"fee",mint.key.as_ref(),&bump],110)?;set_authority(mint,payer,token,4,Some(state.key),None)?;
 let mut out=b"FEE1".to_vec();for key in [mint.key,token.key,&owner]{append_key(&mut out,key)}out.extend_from_slice(&maximum_bps.to_le_bytes());append_u64(&mut out,maximum_fee);state.try_borrow_mut_data()?.copy_from_slice(&out);Ok(())
}
fn read_fee(program:&Pubkey,state:&AccountInfo)->Result<(Pubkey,Pubkey,Pubkey,u16,u64,u8),ProgramError>{
 if state.owner!=program{return Err(ProgramError::IllegalOwner)}let data=state.try_borrow_data()?;let mut r=state_reader(&data,b"FEE1")?;let mint=r.key()?;let token=r.key()?;let owner=r.key()?;let bps=r.u16()?;let maximum=r.u64()?;r.done()?;let (expected,bump)=Pubkey::find_program_address(&[b"fee",mint.as_ref()],program);if expected!=*state.key{return Err(ProgramError::InvalidSeeds)}Ok((mint,token,owner,bps,maximum,bump))
}
fn set_fee(program:&Pubkey,accounts:&[AccountInfo],r:&mut Reader)->ProgramResult{
 let bps=r.u16()?;let maximum=r.u64()?;r.done()?;let a=&mut accounts.iter();let authority=next_account_info(a)?;let state=next_account_info(a)?;let mint=next_account_info(a)?;let token=next_account_info(a)?;signer(authority)?;
 let (key,token_key,owner,cap_bps,cap_fee,bump)=read_fee(program,state)?;if key!=*mint.key||token_key!=*token.key||owner!=*authority.key||bps>cap_bps||maximum>cap_fee{return Err(invalid())}
 let mut data=vec![26,5];data.extend_from_slice(&bps.to_le_bytes());append_u64(&mut data,maximum);let bump=[bump];
 invoke_signed(&Instruction{program_id:*token.key,accounts:vec![AccountMeta::new(*mint.key,false),AccountMeta::new_readonly(*state.key,true)],data},&[mint.clone(),state.clone(),token.clone()],&[&[b"fee",mint.key.as_ref(),&bump]])
}
fn fee_owner(program:&Pubkey,accounts:&[AccountInfo],r:&mut Reader)->ProgramResult{
 let next=r.key()?;r.done()?;let a=&mut accounts.iter();let authority=next_account_info(a)?;let state=next_account_info(a)?;let mint=next_account_info(a)?;let token=next_account_info(a)?;signer(authority)?;
 let (key,token_key,owner,_,_,bump)=read_fee(program,state)?;if key!=*mint.key||token_key!=*token.key||owner!=*authority.key{return Err(ProgramError::IllegalOwner)}
 if next==Pubkey::default(){let bump=[bump];set_authority(mint,state,token,4,None,Some(&[b"fee",mint.key.as_ref(),&bump]))?}state.try_borrow_mut_data()?[68..100].copy_from_slice(next.as_ref());Ok(())
}
