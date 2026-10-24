import {createClient}from'npm:@supabase/supabase-js@2.99.1';
import {payoutsEnabled,payoutMatches,successfulDescription,quoteRate}from'./rules.mjs';
const json=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
let rateCache:{expires:number;value:any}|null=null;
Deno.serve(async(req:Request)=>{
 if(req.method!=='POST')return json({error:'POST required'},405);
 const auth=req.headers.get('Authorization')??'';
 if(!auth.startsWith('Bearer '))return json({error:'Sign in required'},401);
 const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
 const {data:{user},error:authError}=await client.auth.getUser(auth.slice(7));
 if(authError||!user)return json({error:'Sign in required'},401);
 const {data:account,error:accountError}=await client.rpc('pulse_account_status');
 if(accountError||account?.active!==true)return json({error:'Active account required'},403);
 try{
 const raw=await req.text();if(raw.length>4096)return json({error:'Request too large'},413);
 const body=JSON.parse(raw),env=(n:string)=>Deno.env.get(n);
 const enabled=payoutsEnabled(env);
 if(body.action==='health')return json({enabled,currency:'NGN',minimum_pcoins:100,hold_days:7});
 if(!enabled)return json({error:'Bank payouts are not enabled yet. Your P-coins remain in your wallet.'},503);
 const service=createClient(env('SUPABASE_URL')!,env('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
 const key=env('SQUAD_SECRET_KEY')!;
 const rpc=async(action:string,id:string|null=null,data:unknown={})=>{
  const {data:result,error}=await service.rpc('pulse_withdraw_service',{p_action:action,p_id:id,p_user:user.id,p_data:data});
  if(error)throw Error(error.message);return result;
 };
 const provider=async(path:string,data:unknown)=>{
  const r=await fetch('https://api-d.squadco.com'+path,{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify(data),signal:AbortSignal.timeout(12000)});
  return {status:r.status,body:await r.json()};
 };
 if(body.action==='quote'){
  const {error}=await client.rpc('pulse_live_probe');if(error)return json({error:'Please wait before requesting another quote.'},429);
  if(!Number.isSafeInteger(body.p_coins)||body.p_coins<100||body.p_coins>1000000||!/^\d{6}$/.test(body.bank_code??'')||!/^\d{10}$/.test(body.account_number??''))return json({error:'Choose an amount, six-digit NIP bank code and ten-digit account number.'},400);
  const bank=await provider('/payout/account/lookup',{bank_code:body.bank_code,account_number:body.account_number});
  if(bank.status!==200||bank.body.success!==true||bank.body.data?.account_number!==body.account_number||typeof bank.body.data?.account_name!=='string')return json({error:'The bank account could not be verified. Check the details.'},400);
  if(!rateCache||rateCache.expires<Date.now()){
   const r=await fetch('https://open.er-api.com/v6/latest/USD',{signal:AbortSignal.timeout(8000)});
   if(!r.ok)throw Error('Exchange quote unavailable');
   rateCache={value:quoteRate(await r.json()),expires:Date.now()+3600000};
  }
  const fee=Number(env('PAYOUT_FEE_KOBO')??'0');
  if(!Number.isSafeInteger(fee)||fee<0)throw Error('Payout fee configuration unavailable');
  const quote=await rpc('quote',null,{...rateCache.value,p_coins:body.p_coins,fee_kobo:fee,bank_code:body.bank_code,account_number:body.account_number,account_name:bank.body.data.account_name,reference:env('SQUAD_MERCHANT_ID')!+'_'+crypto.randomUUID()});
  return json({quote,source:'ExchangeRate-API daily reference rate',source_url:'https://www.exchangerate-api.com',review_required:true});
 }
 if(!uuid.test(body.id??''))return json({error:'Invalid withdrawal'},400);
 if(body.action==='confirm')return json({withdrawal:await rpc('confirm',body.id)});
 if(body.action==='status'){
  const quote=await rpc('get',body.id);
  if(quote.state!=='processing')return json({withdrawal:quote});
  const check=await provider('/payout/requery',{transaction_reference:quote.provider_reference});
  if(check.status===200&&check.body.success===true&&payoutMatches(check.body.data,quote)&&successfulDescription(check.body.data))return json({withdrawal:await rpc('paid',body.id)});
  return json({withdrawal:quote,message:'Payout confirmation is pending. Do not request a replacement transfer.'});
 }
 if(!['approve','decline','reconcile'].includes(body.action))return json({error:'Unknown action'},400);
 const {error:staffError}=await client.rpc('pulse_admin_overview');
 if(staffError)return json({error:'Staff required'},403);
 // Staff operations may inspect another user's request. The service boundary
 // still owns every amount, account and reference; client data cannot override them.
 const {data:request,error:readError}=await service.rpc('pulse_withdraw_service',{p_action:'get_admin',p_id:body.id,p_user:user.id,p_data:{}});
 if(readError||!request)return json({error:'Withdrawal unavailable'},404);
 if(body.action==='decline'){
  if(request.state!=='review')return json({error:'A dispatched payout cannot be declined. Reconcile its provider status.'},409);
  return json({withdrawal:await rpc('failed',body.id)});
 }
 const check=async()=>{
  const r=await provider('/payout/requery',{transaction_reference:request.provider_reference});
  if(r.status===200&&r.body.success===true&&payoutMatches(r.body.data,request)&&successfulDescription(r.body.data))return json({withdrawal:await rpc('paid',body.id)});
  if(r.status===412&&payoutMatches(r.body.data,request))return json({withdrawal:await rpc('reversed',body.id)});
  return json({withdrawal:request,message:'Provider confirmation is pending. No transfer was retried.'});
 };
 if(body.action==='reconcile'||request.state!=='review')return await check();
 const claim=await rpc('claim',body.id);
 if(!claim.claimed)return json({withdrawal:claim,message:'Already queued; check its status.'});
 // A timeout is NOT a failure. Leave funds reserved and never repeat transfer.
 const sent=await provider('/payout/transfer',{transaction_reference:claim.provider_reference,amount:String(claim.net_kobo),bank_code:claim.bank_code,account_number:claim.account_number,account_name:claim.account_name,currency_id:'NGN',remark:'Pulse creator earnings'});
 if(sent.status===200&&sent.body.success===true&&payoutMatches(sent.body.data,claim)&&successfulDescription(sent.body.data))return json({withdrawal:await rpc('paid',body.id)});
 if(sent.status===400&&sent.body.message==='Insufficient balance')return json({withdrawal:await rpc('failed',body.id),message:'Merchant payout balance unavailable. P-coins restored.'});
 return json({withdrawal:claim,message:'Transfer submitted or uncertain; check status. It will not be sent a second time.'});
 }catch{return json({error:'Could not finish this operation. If you confirmed a withdrawal, check its status; do not submit a replacement.'},503);}
});
