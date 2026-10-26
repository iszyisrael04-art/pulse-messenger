import assert from 'node:assert/strict';
import {makeRegionalPricing, pulseNgnPerCatalogUsd} from '../supabase/functions/pulse-payments/regional-pricing.mjs';
import {koraConfig} from '../supabase/functions/pulse-payments/korapay-rules.mjs';

assert.equal(pulseNgnPerCatalogUsd, '450');
assert.equal(koraConfig(() => undefined).rate, '450');
assert.equal(koraConfig(n => n === 'KORAPAY_NGN_PER_USD' ? '1500' : undefined).rate, '450', 'old configuration must not silently override approved pricing');
for (const [cents, naira] of [[100,450], [200,900], [500,2250], [1000,4500]]) {
 assert.equal(Math.ceil(cents * Number(pulseNgnPerCatalogUsd)) / 100, naira);
}
const today = Date.parse('2026-10-26T12:00:00Z');
let now = today, calls = 0;
let row = {date:'2026-10-26',base:'NGN',quote:'USD',rate:0.0007};
const fx = makeRegionalPricing(async (url, options) => {
 calls++;
 assert.equal(url, 'https://api.frankfurter.dev/v2/rate/ngn/usd');
 assert.equal(options.headers.Authorization, undefined, 'payment secrets must never reach the FX provider');
 assert.equal(options.redirect, 'error');
 return new Response(JSON.stringify(row));
}, () => now);
assert.equal((await fx('NGN')).rate, 1);assert.equal(calls, 0);
assert.equal(await fx('USD/../../steal'), null);assert.equal(calls, 0);
const pair = await Promise.all([fx('USD'), fx('USD')]);
assert.equal(pair[0].rate, .0007);assert.equal(calls, 1, 'coalesce simultaneous requests');
await fx('USD');assert.equal(calls, 1);
now += 6 * 3600000 + 1;await fx('USD');assert.equal(calls, 2);
now += 6 * 3600000 + 1;row = {...row,date:'2026-01-01'};
assert.equal(await fx('USD'), null, 'never serve expired FX as current');
for (const patch of [{date:'nonsense'},{date:'2026-11-20'},{rate:-1},{rate:'0.001'},{rate:0},{base:'USD'},{quote:'EUR'}]) {
 const invalid = makeRegionalPricing(async () => new Response(JSON.stringify({date:'2026-10-26',base:'NGN',quote:'USD',rate:1,...patch})), () => today);
 assert.equal(await invalid('USD'), null);
}
assert.equal(await makeRegionalPricing(async () => {throw Error('offline');})('GBP'), null);
assert.equal(await makeRegionalPricing(async () => new Response('', {status:422}))('XXX'), null);
console.log('Regional pricing: merchant price, cache, freshness, failure fallback and credential isolation passed');
