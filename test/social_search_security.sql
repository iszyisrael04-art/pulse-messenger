begin;
create temporary table search_fixture(k text primary key,id uuid default gen_random_uuid());
insert into search_fixture(k) values('author'),('reader'),('video'),('draft');
grant select on search_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at) select id,'authenticated','authenticated','pulse-search-'||id||'@example.invalid',now() from search_fixture where k in ('author','reader');
update public.pulse_profiles set display_name='UniqueSearchCreator',username='zzsearch_'||left(id::text,8) where id=(select id from search_fixture where k='author');
insert into storage.objects(bucket_id,name,metadata) select 'pulse-social',a.id||'/'||v.id||'/video.mp4','{"mimetype":"video/mp4","size":100}'::jsonb from search_fixture a,search_fixture v where a.k='author' and v.k='video';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from search_fixture where k='author'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_social_write((select id from search_fixture where k='video'),'reel','UniqueSearchClip sword dancing #UniqueSearchTopic',jsonb_build_array(jsonb_build_object('kind','video','mime','video/mp4','path',(select a.id||'/'||v.id||'/video.mp4' from search_fixture a,search_fixture v where a.k='author' and v.k='video'))),'public',false);
select public.pulse_social_write((select id from search_fixture where k='draft'),'post','UniqueSearchClip secret draft','[]','public',true);
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from search_fixture where k='reader'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_social_action((select id from search_fixture where k='video'),'view',true);
do $$ declare result jsonb; begin
 result=public.pulse_social_search('sword dancing','video',null,null,12);
 if jsonb_array_length(result)<>1 or result->0->>'id'<>(select id::text from search_fixture where k='video') then raise exception 'FAIL: keyword/video search'; end if;
 if jsonb_array_length(public.pulse_social_search('UniqueSearchClip','all',null,null,12))<>1 then raise exception 'FAIL: draft search leak'; end if;
 if not exists(select 1 from jsonb_array_elements(public.pulse_social_suggestions('UniqueSearch')) x where x->>'text'='#uniquesearchtopic') then raise exception 'FAIL: topic suggestions'; end if;
 result=public.pulse_social_search_people('UniqueSearchCreator');
 if jsonb_array_length(result)<>1 or result->0 ? 'email' or result->0 ? 'phone' then raise exception 'FAIL: profile projection'; end if;
 if not exists(select 1 from jsonb_array_elements(public.pulse_social_trending()) x where x->>'id'=(select id::text from search_fixture where k='video')) then raise exception 'FAIL: trending visible viewed video'; end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from search_fixture where k='author'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_social_account(true,null);
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from search_fixture where k='reader'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if jsonb_array_length(public.pulse_social_search('UniqueSearchClip','video',null,null,12))<>0 then raise exception 'FAIL: private video search leak'; end if;
 if exists(select 1 from jsonb_array_elements(public.pulse_social_suggestions('UniqueSearch')) x where x->>'kind'<>'profile') then raise exception 'FAIL: private suggestion leak'; end if;
 if exists(select 1 from jsonb_array_elements(public.pulse_social_trending()) x where x->>'id'=(select id::text from search_fixture where k='video')) then raise exception 'FAIL: private trending leak'; end if;
end $$;
select public.pulse_block_user((select id from search_fixture where k='author'),true);
do $$ begin
 if jsonb_array_length(public.pulse_social_search_people('UniqueSearchCreator'))<>0 then raise exception 'FAIL: blocked profile search'; end if;
end $$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.pulse_social_search(text,text,timestamptz,uuid,int)','execute') then raise exception 'FAIL: anon search'; end if;
end $$;
rollback;
