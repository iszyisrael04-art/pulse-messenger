import {pulseNgnPerCatalogUsd} from './regional-pricing.mjs';
export const koraApi='https://api.korapay.com/merchant/api/v1';
export const koraUuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function koraConfig(env) {
 const key=env('KORAPAY_SECRET_KEY')??'',mode=env('KORAPAY_MODE')??'';
 const live=mode==='live'&&/^sk_live_[A-Za-z0-9_-]+$/.test(key);
 const test=mode==='test'&&/^sk_test_[A-Za-z0-9_-]+$/.test(key);
 const rate=pulseNgnPerCatalogUsd;
 const rateReady=/^\d{1,6}(\.\d{1,6})?$/.test(rate)&&Number(rate)>0&&Number(rate)<=100000;
 return {key,live,test,rate,enabled:live&&env('KORAPAY_LIVE_ENABLED')==='true'&&rateReady};
}
export function koraUrl(value,test=false) {
 try{const u=new URL(value);return u.protocol==='https:'&&u.hostname===(test?'test-checkout.korapay.com':'checkout.korapay.com')&&!u.username&&!u.password&&!u.port?u.href:null;}catch{return null;}
}
export function koraMinor(value) {
 if(typeof value!=='number'&&typeof value!=='string')return null;
 const text=String(value);if(!/^\d{1,12}(\.\d{1,2})?$/.test(text))return null;
 const [major,fraction='']=text.split('.');const amount=Number(major)*100+Number(fraction.padEnd(2,'0'));
 return Number.isSafeInteger(amount)&&amount>0?amount:null;
}
export function koraMatches(data,order) {
 return data?.reference===order.id&&data?.status==='success'&&data?.currency==='NGN'
 &&koraMinor(data?.amount)===Number(order.charge_minor)
 &&koraMinor(data?.amount_paid)===Number(order.charge_minor);
}
export async function koraSignature(data,signature,key) {
 if(!data||typeof data!=='object'||Array.isArray(data)||!/^[0-9a-f]{64}$/i.test(signature??''))return false;
 const k=await crypto.subtle.importKey('raw',new TextEncoder().encode(key),{name:'HMAC',hash:'SHA-256'},false,['verify']);
 const bytes=Uint8Array.from(signature.match(/../g),x=>parseInt(x,16));
 return crypto.subtle.verify('HMAC',k,bytes,new TextEncoder().encode(JSON.stringify(data)));
}
export function koraTestRef(reference,user) {
 return typeof reference==='string'&&new RegExp('^KTEST'+user.replaceAll('-','')+'[a-f0-9]{32}$').test(reference);
}
