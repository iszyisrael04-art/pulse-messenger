export function payoutsEnabled(env){return env('SQUAD_MODE')==='live'&&env('SQUAD_PAYOUTS_ENABLED')==='true'&&/^sk_[A-Za-z0-9_-]+$/.test(env('SQUAD_SECRET_KEY')??'')&&/^[A-Za-z0-9-]{3,40}$/.test(env('SQUAD_MERCHANT_ID')??'');}
export function payoutMatches(data,quote){return data?.transaction_reference===quote.provider_reference&&data?.currency_id==='NGN'&&String(data?.amount)===String(quote.net_kobo)&&data?.account_number===quote.account_number&&typeof data?.nip_transaction_reference==='string'&&data.nip_transaction_reference.length>0;}
export function successfulDescription(data){return ['Transaction Success','Approved or completed successfully'].includes(data?.response_description);}
export function quoteRate(data,now=Date.now()){
 const rate=data?.rates?.NGN,asOf=Number(data?.time_last_update_unix)*1000;
 if(data?.result!=='success'||data?.base_code!=='USD'||!Number.isFinite(rate)||rate<=0||rate>1000000||!Number.isFinite(asOf)||now-asOf>36*3600000||asOf>now+300000)throw Error('Exchange quote unavailable');
 return {rate_kobo_per_usd:Math.round(rate*100),rate_as_of:new Date(asOf).toISOString()};
}
