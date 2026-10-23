export const sandboxBase = 'https://sandbox-api-d.squadco.com';
export const testAmount = 10000; // NGN 100 simulated; not a product price.
export function sandboxKey(key) { return typeof key === 'string' && /^sandbox_sk_[A-Za-z0-9_-]+$/.test(key); }
export function ownsReference(reference, user) {
  return typeof reference === 'string' && new RegExp('^PTEST' + user.replaceAll('-', '') + '[a-f0-9]{32}$').test(reference);
}
export function checkoutUrl(value) {
  try { const u = new URL(value); return u.protocol === 'https:' && u.hostname === 'sandbox-pay.squadco.com' && !u.username && !u.password && !u.port ? u.href : null; } catch { return null; }
}
export function verifiedTest(data, reference) {
  return data?.transaction_ref === reference && data?.transaction_status === 'Success' && data?.transaction_currency_id === 'NGN' && Number.isSafeInteger(data?.transaction_amount) && data.transaction_amount === testAmount;
}
