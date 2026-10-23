export function liveEnabled(key, env) {
 return env('SQUAD_MODE')==='live' && env('SQUAD_LIVE_ENABLED')==='true' && typeof key==='string' && /^sk_[A-Za-z0-9_-]+$/.test(key);
}
export function liveCheckoutUrl(value) {
 try {const u=new URL(value);return u.protocol==='https:'&&u.hostname==='pay.squadco.com'&&!u.username&&!u.password&&!u.port?u.href:null;}catch{return null;}
}
export function liveMatches(data, order) {
 return data?.transaction_ref===order.id && data?.transaction_status==='Success' && data?.transaction_currency_id===order.currency && Number.isSafeInteger(data?.transaction_amount) && data.transaction_amount===order.usd_cents;
}
export async function webhookValid(raw,signature,key) {
 if(!/^[0-9a-f]{128}$/i.test(signature??''))return false;
 const k=await crypto.subtle.importKey('raw',new TextEncoder().encode(key),{name:'HMAC',hash:'SHA-512'},false,['verify']);
 const bytes=Uint8Array.from(signature.match(/../g),x=>parseInt(x,16));
 return crypto.subtle.verify('HMAC',k,bytes,new TextEncoder().encode(raw));
}
