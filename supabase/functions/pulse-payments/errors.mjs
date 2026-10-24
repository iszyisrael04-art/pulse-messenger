// Do not forward provider payloads: they may contain merchant/customer data.
export function checkoutFailure(status, success, safeUrl) {
 if(status===401)return {code:'squad_key_rejected',error:'Squad rejected the live secret key. Check that it belongs to your approved live account.'};
 if(status===403)return {code:'squad_access_denied',error:'Squad denied merchant access. Ask Squad whether this live account can collect USD payments.'};
 if(status===429)return {code:'squad_rate_limit',error:'Squad is receiving too many requests. Wait before retrying.'};
 if(status>=500)return {code:'squad_unavailable',error:'Squad is temporarily unavailable. Try again later; do not pay twice.'};
 if(status<200||status>=300||success!==true)return {code:'squad_checkout_rejected',error:'Squad could not create this USD checkout. Ask Squad to check your merchant access and the order reference shown below.'};
 if(!safeUrl)return {code:'squad_checkout_address',error:'Squad returned an unsupported checkout address. Pulse did not open it. Keep your order reference for support.'};
 return null;
}
