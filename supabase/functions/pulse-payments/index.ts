import {makeKoraHandler} from './korapay-handler.mjs';
import { checkout } from './checkout.ts';
import { liveEnabled, webhookValid } from './live.mjs';
import { createClient } from 'npm:@supabase/supabase-js@2.99.1';
import { sandboxBase, testAmount, sandboxKey, ownsReference, checkoutUrl, verifiedTest } from './rules.mjs';
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
const korapay=makeKoraHandler((name: string)=>Deno.env.get(name),createClient);
Deno.serve(async (req: Request) => {
  if (req.headers.has('x-korapay-signature') || (!req.headers.has('x-squad-encrypted-body') && Deno.env.get('PULSE_PAYMENT_PROVIDER')==='korapay')) return korapay(req);
  if (req.method !== 'POST') return json({error:'POST required'},405);
  const key = Deno.env.get('SQUAD_SECRET_KEY') ?? ''; 
  const live = liveEnabled(key, (name: string) => Deno.env.get(name));
  if (req.headers.has('x-squad-encrypted-body')) {
    if (!live) return json({error:'Live payments disabled'},503);
    const raw = await req.text();
    if (raw.length>20000 || !await webhookValid(raw,req.headers.get('x-squad-encrypted-body'),key)) return json({error:'Invalid webhook'},401);
    try { return await checkout(req,raw,key,null,null); } catch { return json({error:'Webhook processing unavailable'},503); }
  }
  const authorization = req.headers.get('Authorization') ?? '';
  if (!authorization.startsWith('Bearer ')) return json({error:'Sign in required'},401);
  const client = createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:authorization}},auth:{persistSession:false}});
  const {data:{user},error} = await client.auth.getUser(authorization.slice(7));
  if (error || !user) return json({error:'Sign in required'},401);
  const {data:account,error:accountError}=await client.rpc('pulse_account_status');
  if(accountError || account?.active !== true) return json({error:'Active account required'},403);

  try {
    if (Number(req.headers.get('content-length') ?? 0)>4096) return json({error:'Request too large'},413);
    const raw=await req.text();
    if(raw.length>4096)return json({error:'Request too large'},413);
    let body;
    try {body=JSON.parse(raw);}catch{return json({error:'Invalid JSON'},400);}
    if(body.action==='health')return json({sandbox:sandboxKey(key),configured:sandboxKey(key)||live,provider_verified:false,purchases_enabled:live});
    if (body.action === 'checkout' || body.action === 'verify') {
      if (!live) return json({error:'Live checkout is not enabled. No payment was started.'},503);
      const {error:limited}=await client.rpc('pulse_live_probe');
      if (limited) return json({error:'Please wait before trying again.'},429);
      return await checkout(req,raw,key,client,user);
    }
    if (!sandboxKey(key)) return json({error:'Save a sandbox secret to run simulated tests. Live keys cannot run sandbox tests.'},503);
    if(!['start-test','verify-test'].includes(body.action))return json({error:'Unknown action'},400);
    // Shared database rate limiter: no per-instance in-memory bypass.
    const {error:rateError}=await client.rpc('pulse_live_probe');
    if(rateError)return json({error:'Please wait before trying again.'},429);
    let reference: string;
    let response: Response;
    if(body.action==='start-test') {
      if(typeof body.email!=='string' || body.email.length>254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.email))return json({error:'Enter a valid receipt email'},400);
      reference='PTEST'+user.id.replaceAll('-','')+crypto.randomUUID().replaceAll('-','');
      response=await fetch(sandboxBase+'/transaction/initiate',{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({email:body.email,amount:testAmount,currency:'NGN',initiate_type:'inline',transaction_ref:reference,pass_charge:false}),signal:AbortSignal.timeout(15000)});
    } else {
      reference=body.reference;
      if(!ownsReference(reference,user.id))return json({error:'This test belongs to another account or has an invalid reference'},403);
      response=await fetch(sandboxBase+'/transaction/verify/'+encodeURIComponent(reference),{headers:{Authorization:`Bearer ${key}`},signal:AbortSignal.timeout(15000)});
    }
    if(response.status===401 || response.status===403) return json({error:'Squad rejected the sandbox key or merchant access. Check your sandbox dashboard.',code:'provider_access'},502);
    const result=await response.json();
    if(!response.ok || result.success!==true)return json({error:'Squad could not complete this test. Check the sandbox dashboard and retry.'},502);
    if(body.action==='start-test') {
      const url=checkoutUrl(result.data?.checkout_url);
      if(!url)return json({error:'Squad returned an unexpected checkout address; it was not opened'},502);
      return json({sandbox:true,reference,checkout_url:url,amount:testAmount,currency:'NGN'});
    }
    return json({sandbox:true,verified:verifiedTest(result.data,reference),status:verifiedTest(result.data,reference)?'Simulated payment verified. No paid features were unlocked.':'Not confirmed: payment is pending, failed or does not match the test amount.',purchases_enabled:false});
  } catch {return json({error:'Could not reach Squad. Please retry the test.'},502);}
});
