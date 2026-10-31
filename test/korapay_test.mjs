import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import {koraConfig,koraUrl,koraMinor,koraMatches,koraSignature} from '../supabase/functions/pulse-payments/korapay-rules.mjs';
import {makeKoraHandler} from '../supabase/functions/pulse-payments/korapay-handler.mjs';
if(!globalThis.crypto)Object.defineProperty(globalThis,'crypto',{value:webcrypto});
const user='11111111-1111-4111-8111-111111111111',id='22222222-2222-4222-8222-222222222222';
const key='sk_live_fixture_only';
const values={KORAPAY_SECRET_KEY:key,KORAPAY_MODE:'live',KORAPAY_LIVE_ENABLED:'true',KORAPAY_NGN_PER_USD:'1500',SUPABASE_URL:'https://example.supabase.co',SUPABASE_ANON_KEY:'anon',SUPABASE_SERVICE_ROLE_KEY:'service'};
const env=n=>values[n];
assert(koraConfig(env).enabled);
for(const patch of [{KORAPAY_SECRET_KEY:'sk_test_fixture'},{KORAPAY_MODE:'test'},{KORAPAY_LIVE_ENABLED:'false'}]){
 assert(!koraConfig(n=>({...values,...patch})[n]).enabled);
}
assert.equal(koraMinor('1500.20'),150020);assert.equal(koraMinor(1500),150000);
for(const v of [null,true,'1.001','1e3',-1,0,' 10','Infinity'])assert.equal(koraMinor(v),null);
assert(koraUrl('https://checkout.korapay.com/ref/pay'));
assert(!koraUrl('https://checkout.korapay.com.evil.test/ref'));
assert(!koraUrl('https://user@checkout.korapay.com/ref'));
assert(!koraUrl('https://test-checkout.korapay.com/ref'));
assert(koraUrl('https://test-checkout.korapay.com/ref',true));
let order={id,user_id:user,sku:'coins_100',coins:100,usd_cents:100,charge_minor:45000,currency:'NGN',state:'pending',checkout_url:null};
let receipt={reference:id,status:'success',currency:'NGN',amount:'450.00',amount_paid:'450.00'};
assert(koraMatches(receipt,order));
for(const patch of [{reference:'other'},{amount:'15.00'},{amount_paid:'1499.99'},{currency:'USD'},{status:'pending'},{amount_paid:undefined}])assert(!koraMatches({...receipt,...patch},order));
async function signature(data){
 const k=await crypto.subtle.importKey('raw',new TextEncoder().encode(key),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 return Buffer.from(await crypto.subtle.sign('HMAC',k,new TextEncoder().encode(JSON.stringify(data)))).toString('hex');
}
const sig=await signature(receipt);
assert(await koraSignature(receipt,sig,key));
assert(!await koraSignature({...receipt,amount:'1.00'},sig,key));
assert(!await koraSignature(receipt,'bad',key));
let fulfilments=0,providerCalls=0,quoteRate=null,posted=null;
const client={auth:{getUser:async()=>({data:{user:{id:user}}})},rpc:async()=>({data:{active:true},error:null})};
const service={rpc:async(name,args)=>{
 assert.equal(name,'pulse_kora_order_service');
 if(args.p_action==='quote'){quoteRate=args.p_rate;return{data:{...order},error:null};}
 if(args.p_action==='checkout'){order.checkout_url=args.p_url;return{data:{...order},error:null};}
 if(args.p_action==='fulfill'){assert.equal(args.p_amount,45000);fulfilments++;order.state='paid';}
 return{data:{...order},error:null};
}};
const factory=(_url,k)=>k==='service'?service:client;
const provider=async(url,options)=>{
 providerCalls++;
 if(url.endsWith('/initialize')){
  posted=JSON.parse(options.body);
  return new Response(JSON.stringify({status:true,data:{reference:posted.reference,checkout_url:'https://checkout.korapay.com/ref/pay'}}));
 }
 return new Response(JSON.stringify({status:true,data:receipt}));
};
const handler=makeKoraHandler(env,factory,provider);
const request=(body,headers={Authorization:'Bearer fixture'})=>new Request('https://example.supabase.co/functions/v1/pulse-payments',{method:'POST',headers,body:JSON.stringify(body)});
let response=await handler(request({action:'checkout',order_id:id,sku:'coins_100',email:'fixture@example.invalid'}));
assert.equal(response.status,200);let data=await response.json();
assert.equal(data.amount,45000);assert.equal(data.currency,'NGN');assert.equal(quoteRate,'450');
assert.equal(posted.amount,450);assert.equal(posted.merchant_bears_cost,true);assert.equal(fulfilments,0);
const count=providerCalls;
await handler(request({action:'checkout',order_id:id,sku:'coins_100',email:'fixture@example.invalid'}));
assert.equal(providerCalls,count,'retry must reuse checkout');
response=await handler(request({event:'charge.success',data:receipt},{'x-korapay-signature':'0'.repeat(64)}));
assert.equal(response.status,401);assert.equal(fulfilments,0);
receipt={...receipt,amount_paid:'1.00'};
response=await handler(request({event:'charge.success',data:{...receipt}},{'x-korapay-signature':await signature(receipt)}));
assert.equal(response.status,409);assert.equal(fulfilments,0,'signed notification alone must not fulfil');
receipt={...receipt,amount_paid:'450.00'};
response=await handler(request({event:'charge.success',data:receipt},{'x-korapay-signature':await signature(receipt)}));
assert.equal(response.status,200);assert.equal(fulfilments,1);
response=await handler(request({event:'charge.success',data:receipt},{'x-korapay-signature':await signature(receipt)}));
assert.equal(response.status,200);assert.equal(fulfilments,1,'duplicate webhook');
order.user_id='33333333-3333-4333-8333-333333333333';
response=await handler(request({action:'verify',reference:id}));assert.equal(response.status,403);
response=await handler(request({action:'start-test',email:'fixture@example.invalid'}));assert.equal(response.status,503,'live keys cannot test');
const testHandler=makeKoraHandler(n=>({...values,KORAPAY_SECRET_KEY:'sk_test_fixture_only',KORAPAY_MODE:'test'})[n],factory,provider);
response=await testHandler(request({action:'checkout',order_id:id,sku:'coins_100',email:'fixture@example.invalid'}));
assert.equal(response.status,503);assert.equal(fulfilments,1);
response=await testHandler(request({action:'health'}));data=await response.json();
assert.equal(data.purchases_enabled,false);assert.equal(data.provider_verified,false);
response=await handler(request({action:'checkout'},{}));assert.equal(response.status,401);
console.log('PASS Korapay mode gates, safe URLs, exact money, data-only HMAC, immutable quote reuse, signed webhook re-query, ownership and duplicate protection');

// Display pricing cannot call the payment API or service-role order RPC.
let priceCalls=0;
const priceHandler=makeKoraHandler(env,(_url,k)=>{assert.notEqual(k,'service');return client;},async(url,options)=>{
 priceCalls++;
 assert.equal(url,'https://api.frankfurter.dev/v2/rate/ngn/usd');
 assert.equal(options.headers.Authorization,undefined);
 return new Response(JSON.stringify({base:'NGN',quote:'USD',rate:.0007,date:new Date().toISOString().slice(0,10)}));
});
response=await priceHandler(request({action:'pricing',currency:'NGN'}));
assert.equal(response.status,200);data=await response.json();
assert.equal(data.ngn_per_catalog_usd,450);assert.equal(data.display.approximate,false);assert.equal(priceCalls,0);
response=await priceHandler(request({action:'pricing',currency:'USD'}));
assert.equal(response.status,200);data=await response.json();assert.equal(data.display.approximate,true);assert.equal(priceCalls,1);
response=await priceHandler(request({action:'pricing',currency:'USD/evil'}));assert.equal(response.status,400);assert.equal(priceCalls,1);
response=await priceHandler(request({action:'pricing',currency:'NGN'},{}));assert.equal(response.status,401);
console.log('PASS regional display authentication, approved price, no settlement side effects and no credential forwarding');

// Exercise the deployed entrypoint's provider decision, including stale settings.
const {readFileSync}=await import('node:fs');
const entry=readFileSync(new URL('../supabase/functions/pulse-payments/index.ts',import.meta.url),'utf8');
const route=entry.split('\n').find(line=>line.includes('return korapay(req);'));
assert(route,'entrypoint must route to Korapay');
const condition=route.trim().match(/^if \((.*)\) return korapay\(req\);$/)[1];
const choosesKora=new Function('req','Deno','return ('+condition+')');
for(const setting of [undefined,'squad','korapay']) {
 const runtime={env:{get:()=>setting}};
 for(const action of ['pricing','health','checkout','verify','start-test','verify-test'])
  assert.equal(choosesKora(request({action}),runtime),true,action+' must use Korapay');
 assert.equal(choosesKora(request({}, {'x-korapay-signature':'fixture'}),runtime),true);
 assert.equal(choosesKora(request({}, {'x-squad-encrypted-body':'fixture'}),runtime),false,'preserve legacy webhook verification');
}
console.log('PASS Korapay routing with missing/stale provider setting and legacy webhook compatibility');
