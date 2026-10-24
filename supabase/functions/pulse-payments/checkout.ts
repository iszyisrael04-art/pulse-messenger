import {createClient} from 'npm:@supabase/supabase-js@2.99.1';
import {liveCheckoutUrl,liveMatches,webhookValid} from './live.mjs';
import {checkoutFailure} from './errors.mjs';
const json=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Only invoked after the main handler has checked mode and authenticated a user,
// or validated a webhook signature. All quotes and grants come from the database.
export async function checkout(req:Request, raw:string, key:string, userClient:any, user:any) {
 const service=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
 const body=JSON.parse(raw);
 let id=body.reference;
 if(body.action==='checkout') {
  if(typeof body.email!=='string'||body.email.length>254||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.email)||!uuid.test(body.order_id??''))return json({error:'Valid order and receipt email required'},400);
  const {data:order,error}=await userClient.rpc('pulse_payment_order',{p_id:body.order_id,p_sku:body.sku});
  if(error)return json({error:'Order unavailable. Check the product and retry.'},400);
  if(order.state==='paid')return json({paid:true,reference:order.id});
  const r=await fetch('https://api-d.squadco.com/transaction/initiate',{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({email:body.email,amount:order.usd_cents,currency:'USD',initiate_type:'inline',transaction_ref:order.id,pass_charge:false,webhook_url:Deno.env.get('SUPABASE_URL')!+'/functions/v1/pulse-payments'}),signal:AbortSignal.timeout(15000)});
  const data=await r.json().catch(()=>({}));
  const url=liveCheckoutUrl(data.data?.checkout_url);
  const failure=checkoutFailure(r.status,data.success,url);
  if(failure)return json(failure,502);
  return json({sandbox:false,reference:order.id,checkout_url:url,currency:'USD',amount:order.usd_cents});
 }
 const webhook=body.Event==='charge_successful';
 if(webhook){
  if(!await webhookValid(raw,req.headers.get('x-squad-encrypted-body'),key))return json({error:'Invalid webhook signature'},401);
  id=body.TransactionRef;
 }
 if(!uuid.test(id??''))return json({error:'Invalid reference'},400);
 const {data:order,error}=await service.rpc('pulse_payment_order_service',{p_id:id,p_action:'get'});
 if(error||!order)return json({error:'Order unavailable'},404);
 if(!webhook&&order.user_id!==user?.id)return json({error:'Own orders only'},403);
 // A redirect or signed webhook is never itself treated as proof of payment.
 const r=await fetch('https://api-d.squadco.com/transaction/verify/'+encodeURIComponent(id),{headers:{Authorization:`Bearer ${key}`},signal:AbortSignal.timeout(15000)});
 const data=await r.json();
 if(!r.ok||data.success!==true||!liveMatches(data.data,order))return json({paid:false,status:'Payment has not been confirmed.'},webhook?409:200);
 const {error:fulfillError}=await service.rpc('pulse_payment_order_service',{p_id:id,p_action:'fulfill',p_amount:data.data.transaction_amount,p_currency:data.data.transaction_currency_id});
 if(fulfillError)return json({error:'Payment confirmed but fulfilment needs retry. Do not pay again.'},503);
 return json({paid:true,reference:id,status:'Payment verified and purchase delivered.'});
}
