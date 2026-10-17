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
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid() primary key,bucket_id text references storage.buckets,name text,metadata jsonb,owner uuid,created_at timestamptz default now());
alter table storage.objects enable row level security;
grant usage on schema auth,storage to authenticated,anon,service_role;
grant select,insert,update,delete on storage.objects to authenticated;
create function storage.foldername(text) returns text[] language sql immutable as $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;
create publication supabase_realtime;`);
for(const f of fs.readdirSync(root+'/supabase/schema').filter(x=>x.endsWith('.sql')).sort()){
 try{await db.exec(fs.readFileSync(root+'/supabase/schema/'+f,'utf8'));console.log('SCHEMA PASS',f);}catch(e){console.log('SCHEMA FAIL',f,e.message,e.where??'');process.exit(1);}
}
for(const f of ['requests_privacy_premium_security.sql','profile_identity_security.sql','activity_security.sql','control_security.sql']){
 if(!fs.existsSync(root+'/test/'+f))continue;
 try{await db.exec(fs.readFileSync(root+'/test/'+f,'utf8'));console.log('TEST PASS',f);}catch(e){console.log('TEST FAIL',f,e.message,e.where??'');process.exit(1);}
}
await db.close();
}catch(e){console.log('BOOTSTRAP FAIL',e.message);process.exit(1);}
