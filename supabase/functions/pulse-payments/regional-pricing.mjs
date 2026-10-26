// Display estimates only. Never use this FX feed to settle or fulfill an order.
export const pulseNgnPerCatalogUsd = '450'; // Owner-approved: 100 coins = NGN 450.
const freshFor = 6 * 60 * 60 * 1000;
export function makeRegionalPricing(request = fetch, clock = Date.now) {
 const cache = new Map();
 const inFlight = new Map();
 return async function regionalPricing(currency) {
  if (typeof currency !== 'string' || !/^[A-Z]{3}$/.test(currency)) return null;
  if (currency === 'NGN') return {currency, rate: 1, date: null, approximate: false};
  const hit = cache.get(currency);
  if (hit && clock() - hit.fetched < freshFor && clock() - Date.parse(hit.value.date + 'T00:00:00Z') <= 7 * 86400000) return hit.value;
  if (inFlight.has(currency)) return inFlight.get(currency);
  const pending = (async () => {
   try {
    // No payment credentials, user IDs, phone numbers or location leave this service.
    const r = await request('https://api.frankfurter.dev/v2/rate/ngn/' + currency.toLowerCase(), {
     redirect: 'error', signal: AbortSignal.timeout(5000), headers: {Accept: 'application/json'},
    });
    if (!r.ok) return null;
    const d = await r.json();
    const date = typeof d.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(d.date) ? Date.parse(d.date + 'T00:00:00Z') : NaN;
    if (d.base !== 'NGN' || d.quote !== currency || typeof d.rate !== 'number' || !Number.isFinite(d.rate) || d.rate <= 0
        || !Number.isFinite(date) || date > clock() + 86400000 || clock() - date > 7 * 86400000) return null;
    const value = {currency, rate: d.rate, date: d.date, approximate: true};
    if (cache.size >= 256) cache.delete(cache.keys().next().value);
    cache.set(currency, {fetched: clock(), value});
    return value;
   } catch { return null; }
  })();
  inFlight.set(currency, pending);
  try { return await pending; } finally { inFlight.delete(currency); }
 };
}
