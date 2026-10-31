import {makeRegionalPricing} from './regional-pricing.mjs';
import {koraApi,koraConfig,koraUrl,koraMatches,koraSignature,koraUuid,koraTestRef} from './korapay-rules.mjs';
const json=(data,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
const emailOk=x=>typeof x==='string'&&x.length<=254&&/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(x);
export function makeKoraHandler(env,createClient,request=fetch) {
 const regionalPricing=makeRegionalPricing(request);
 return async(req)=>{
  if(req.method!=='POST')return json({error:'POST required'},405);
  const cfg=koraConfig(env),signed=req.headers.has('x-korapay-signature');
  if(Number(req.headers.get('content-length')??0)>(signed?20000:4096))return json({error:'Request too large'},413);
  const raw=await req.text();if(raw.length>(signed?20000:4096))return json({error:'Request too large'},413);
  let body;try{body=JSON.parse(raw);if(!body||typeof body!=='object'||Array.isArray(body))throw Error();}catch{return json({error:'Invalid JSON'},400);}
  try {
   let user=null,client=null;
   if(signed) {
    if(!cfg.live||!await koraSignature(body.data,req.headers.get('x-korapay-signature'),cfg.key))return json({error:'Invalid Korapay webhook'},401);
    if(body.event!=='charge.success')return json({ignored:true});
   } else {
    const authorization=req.headers.get('Authorization')??'';
    if(!authorization.startsWith('Bearer '))return json({error:'Sign in required'},401);
    client=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:authorization}},auth:{persistSession:false}});
    const auth=await client.auth.getUser(authorization.slice(7));user=auth.data?.user;
    if(auth.error||!user)return json({error:'Sign in required'},401);
    const account=await client.rpc('pulse_account_status');
    if(account.error||account.data?.active!==true)return json({error:'Active account required'},403);
    if(body.action==='health')return json({provider:'korapay',sandbox:cfg.test,configured:cfg.test||cfg.live,purchases_enabled:cfg.enabled,provider_verified:false,currency:'NGN'});
    if(body.action==='pricing') {
     if(typeof body.currency!=='string'||!/^[A-Z]{3}$/.test(body.currency))return json({error:'Select a currency'},400);
     const display=await regionalPricing(body.currency);
     return json({provider:'korapay',charge_currency:'NGN',ngn_per_catalog_usd:Number(cfg.rate),display,display_unavailable:display===null});
    }
   }
   if(!signed&&['start-test','verify-test'].includes(body.action)&&!cfg.test) {
    const reason=!cfg.key?'KORAPAY_SECRET_KEY is missing in Supabase. Save your Korapay test secret.':
     cfg.key.startsWith('sk_live_')?'A live Korapay key is configured. Sandbox requires the test secret.':
     !/^sk_test_[A-Za-z0-9_-]+$/.test(cfg.key)?'KORAPAY_SECRET_KEY must contain the Korapay test secret, not the public key.':
     'Set KORAPAY_MODE to test in Supabase to open the sandbox.';
    return json({error:reason,code:'korapay_test_configuration'},503);
   }
   if(!signed) {
    const limited=await client.rpc('pulse_live_probe');
    if(limited.error)return json({error:'Too many payment attempts. Wait one minute, then tap once.',code:'payment_rate_limited'},429);
   }
   const headers={Authorization:'Bearer '+cfg.key,'Content-Type':'application/json'};
   const provider=async(path,options={})=>{
    const r=await request(koraApi+path,{...options,headers,redirect:'error',signal:AbortSignal.timeout(15000)});
    const data=await r.json().catch(()=>({}));
    return {ok:r.ok&&data.status===true,status:r.status,data:data.data};
   };
   if(!signed&&['start-test','verify-test'].includes(body.action)) {

    if(body.action==='start-test'){
     if(!emailOk(body.email))return json({error:'Enter a valid receipt email'},400);
     const reference='KTEST'+user.id.replaceAll('-','')+crypto.randomUUID().replaceAll('-','');
     const result=await provider('/charges/initialize',{method:'POST',body:JSON.stringify({reference,amount:100,currency:'NGN',customer:{email:body.email},merchant_bears_cost:true})});
     const url=koraUrl(result.data?.checkout_url,true);
     if(!result.ok)return json({error:result.status===401||result.status===403?'Korapay rejected the test key or merchant access. Check the test secret in Supabase.':'Korapay could not create a test checkout. Check the merchant test settings.',code:result.status===401||result.status===403?'korapay_test_access':'korapay_test_checkout'},502);
     if(result.data?.reference!==reference||!url)return json({error:'Korapay returned an unexpected test checkout link or reference. No checkout was opened.',code:'korapay_test_response'},502);
     return json({sandbox:true,reference,checkout_url:url,currency:'NGN',amount:10000,purchases_enabled:false});
    }
    if(!koraTestRef(body.reference,user.id))return json({error:'Own test references only'},403);
    const result=await provider('/charges/'+encodeURIComponent(body.reference));
    const verified=result.ok&&koraMatches(result.data,{id:body.reference,charge_minor:10000});
    return json({sandbox:true,verified,purchases_enabled:false,status:verified?'Simulated payment verified. No coins or paid features were granted.':'Test payment is not confirmed.'});
   }
   if(!cfg.live)return json({error:'Korapay live configuration is not ready. No payment was started.'},503);
   if(!signed&&!['checkout','verify'].includes(body.action))return json({error:'Unknown payment action'},400);
   const service=createClient(env('SUPABASE_URL'),env('SUPABASE_SERVICE_ROLE_KEY'),{auth:{persistSession:false}});
   const orderRpc=async(args)=>service.rpc('pulse_kora_order_service',args);
   if(!signed&&body.action==='checkout') {
    if(!cfg.enabled)return json({error:'Korapay checkout awaits live enablement and a configured naira price. No payment was started.'},503);
    if(!koraUuid.test(body.order_id??'')||!emailOk(body.email))return json({error:'Valid order and receipt email required'},400);
    const quote=await orderRpc({p_id:body.order_id,p_action:'quote',p_user:user.id,p_sku:body.sku,p_rate:cfg.rate});
    if(quote.error||!quote.data)return json({error:'Order unavailable. Use a new order if switching payment providers.'},400);
    const order=quote.data;
    if(order.state==='paid')return json({paid:true,reference:order.id});
    let url=koraUrl(order.checkout_url);
    if(!url) {
     const result=await provider('/charges/initialize',{method:'POST',body:JSON.stringify({
      reference:order.id,amount:Number(order.charge_minor)/100,currency:'NGN',
      customer:{email:body.email},merchant_bears_cost:true,narration:'Pulse '+order.sku,
      notification_url:env('SUPABASE_URL')+'/functions/v1/pulse-payments'
     })});
     url=koraUrl(result.data?.checkout_url);
     if(!result.ok||result.data?.reference!==order.id||!url)return json({error:'Korapay could not create checkout. Keep your reference and verify an existing payment before retrying.',code:result.status===401?'korapay_key_rejected':'korapay_checkout_unavailable'},502);
     const saved=await orderRpc({p_id:order.id,p_action:'checkout',p_user:user.id,p_url:url});
     if(saved.error)return json({error:'Could not save checkout. Keep your reference and verify before paying again.'},503);
    }
    return json({provider:'korapay',sandbox:false,reference:order.id,checkout_url:url,currency:'NGN',amount:Number(order.charge_minor)});
   }
   const id=signed?body.data.reference:body.reference;
   if(!koraUuid.test(id??''))return json({error:'Invalid reference'},400);
   const lookup=await orderRpc({p_id:id,p_action:'get'});
   if(lookup.error||!lookup.data)return json({error:'Order unavailable'},404);
   const order=lookup.data;
   if(!signed&&order.user_id!==user.id)return json({error:'Own orders only'},403);
   if(order.state==='paid')return json({paid:true,reference:id});
   const result=await provider('/charges/'+encodeURIComponent(id));
   // A signed notification is still not proof: re-query Kora and match both amount and amount_paid.
   if(!result.ok||!koraMatches(result.data,order))return json({paid:false,status:'Payment is not confirmed or does not match this order.'},signed?409:200);
   const fulfilled=await orderRpc({p_id:id,p_action:'fulfill',p_amount:Number(order.charge_minor),p_currency:result.data.currency});
   if(fulfilled.error)return json({error:'Payment confirmed; delivery needs retry. Do not pay again.'},503);
   return json({paid:true,reference:id,status:'Payment verified and purchase delivered.'});
  } catch{return json({error:'Korapay is temporarily unavailable. Keep your reference and verify before paying again.'},503);}
 };
}

