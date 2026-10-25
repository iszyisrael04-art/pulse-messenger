import {PGlite} from '@electric-sql/pglite';
import {pgcrypto} from '@electric-sql/pglite/contrib/pgcrypto';
import {pg_trgm} from '@electric-sql/pglite/contrib/pg_trgm';
import fs from 'node:fs';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../../',import.meta.url));
const db=new PGlite({extensions:{pgcrypto,pg_trgm}});
try{
await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create schema storage;create schema extensions;
create extension pgcrypto with schema extensions;
create function auth.uid() returns uuid language sql stable as $$select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
create function auth.role() returns text language sql stable as $$select nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role'$$;
create table auth.users(id uuid primary key,email text,phone text,email_confirmed_at timestamptz,phone_confirmed_at timestamptz,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}',aud text,role text,encrypted_password text,created_at timestamptz default now());
create table auth.sessions(id uuid primary key,user_id uuid not null references auth.users on delete cascade,not_after timestamptz);
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid() primary key,bucket_id text references storage.buckets,name text,metadata jsonb,owner uuid,created_at timestamptz default now());
alter table storage.objects enable row level security;
grant usage on schema auth,storage to authenticated,anon,service_role;
grant select,insert,update,delete on storage.objects to authenticated;
create function storage.foldername(text) returns text[] language sql immutable as $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;
create publication supabase_realtime;`);
for(const f of fs.readdirSync(root+'/supabase/schema').filter(x=>x.endsWith('.sql') && x<'025_').sort()){
 try{await db.exec(fs.readFileSync(root+'/supabase/schema/'+f,'utf8'));console.log('SCHEMA PASS',f);}catch(e){console.log('SCHEMA FAIL',f,e.message,e.where??'');process.exit(1);}
}
for(const f of ['requests_privacy_premium_security.sql','profile_identity_security.sql','activity_security.sql','control_security.sql','channel_verification_security.sql','channels_security.sql','live_controls_security.sql','community_channel_updates_security.sql','live_party_security.sql','status_replies_security.sql','channel_media_security.sql','chat_forwarding_security.sql']){
 if(!fs.existsSync(root+'/test/'+f))continue;
 try{await db.exec(fs.readFileSync(root+'/test/'+f,'utf8'));console.log('TEST PASS',f);}catch(e){console.log('TEST FAIL',f,e.message,e.where??'');process.exit(1);}
}
await db.exec(fs.readFileSync(root+'/supabase/schema/025_creator_access.sql','utf8'));
console.log('SCHEMA PASS 025_creator_access.sql');
await db.exec(fs.readFileSync(root+'/test/creator_access_security.sql','utf8'));
console.log('TEST PASS creator_access_security.sql');
await db.exec(fs.readFileSync(root+'/supabase/schema/026_composer_download_privacy.sql','utf8'));
console.log('SCHEMA PASS 026_composer_download_privacy.sql');
await db.exec(fs.readFileSync(root+'/test/composer_privacy_security.sql','utf8'));
console.log('TEST PASS composer_privacy_security.sql');
await db.exec(fs.readFileSync(root+'/supabase/schema/027_active_status.sql','utf8'));
console.log('SCHEMA PASS 027_active_status.sql');
await db.exec(fs.readFileSync(root+'/test/presence_security.sql','utf8'));
console.log('TEST PASS presence_security.sql');
await db.exec(fs.readFileSync(root+'/supabase/schema/028_gifts_calls_shop.sql','utf8'));
console.log('SCHEMA PASS 028_gifts_calls_shop.sql');
await db.exec(fs.readFileSync(root+'/test/gifts_calls_security.sql','utf8'));
console.log('TEST PASS gifts_calls_security.sql');
await db.exec(fs.readFileSync(root+'/supabase/schema/029_payment_orders.sql','utf8'));
console.log('SCHEMA PASS 029_payment_orders.sql');
await db.exec(fs.readFileSync(root+'/test/payment_orders_security.sql','utf8'));
console.log('TEST PASS payment_orders_security.sql');
await db.exec(fs.readFileSync(root+'/supabase/schema/030_pcoin_withdrawals.sql','utf8'));
console.log('SCHEMA PASS 030_pcoin_withdrawals.sql');
await db.exec(fs.readFileSync(root+'/test/withdrawals_security.sql','utf8'));
console.log('TEST PASS withdrawals_security.sql');
for(const f of ['031_decimal_gift_pricing.sql','032_channel_quotes.sql','033_channel_responses.sql','034_gifter_ranks_feed.sql']) {
 await db.exec(fs.readFileSync(root+'/supabase/schema/'+f,'utf8'));
 console.log('SCHEMA PASS',f);
}
await db.exec(fs.readFileSync(root+'/test/decimal_gifts_security.sql','utf8'));
console.log('TEST PASS decimal_gifts_security.sql');
await db.exec(fs.readFileSync(root+'/test/channel_quotes_security.sql','utf8'));
console.log('TEST PASS channel_quotes_security.sql');
await db.exec(fs.readFileSync(root+'/test/gifter_ranks_security.sql','utf8'));
console.log('TEST PASS gifter_ranks_security.sql');
await db.exec(fs.readFileSync(root+'/supabase/schema/035_test_coins_session_guard.sql','utf8'));
console.log('SCHEMA PASS 035_test_coins_session_guard.sql');
await db.exec(fs.readFileSync(root+'/test/test_coins_security.sql','utf8'));
console.log('TEST PASS test_coins_security.sql');
await db.exec(fs.readFileSync(root+'/test/session_revocation_security.sql','utf8'));
console.log('TEST PASS session_revocation_security.sql');
await db.exec(fs.readFileSync(root+'/supabase/schema/037_extra_live_gifts.sql','utf8'));
const extra=await db.query("select count(*)::int n from pulse_private.gift_catalog where sku in('saturn','trophy','butterfly','castle','fireworks','pearl')");
if(extra.rows[0].n!==6)throw Error('Missing new gifts');
console.log('TEST PASS six additive gifts');
await db.exec(fs.readFileSync(root+'/supabase/schema/038_free_video_banners.sql','utf8'));
console.log('SCHEMA PASS 038_free_video_banners.sql');
await db.exec(fs.readFileSync(root+'/supabase/schema/039_admin_reward_codes.sql','utf8'));
console.log('SCHEMA PASS 039_admin_reward_codes.sql');
await db.exec(fs.readFileSync(root+'/test/reward_codes_security.sql','utf8'));
console.log('TEST PASS reward_codes_security.sql');
await db.exec(fs.readFileSync(root+'/supabase/schema/040_event_branding_reward_mail.sql','utf8'));
console.log('SCHEMA PASS 040_event_branding_reward_mail.sql');
await db.exec(fs.readFileSync(root+'/test/event_reward_mail_security.sql','utf8'));
console.log('TEST PASS event_reward_mail_security.sql');
await db.close();
await import('../live_edge_offline.mjs');
}catch(e){console.log('BOOTSTRAP FAIL',e.message);process.exit(1);}
