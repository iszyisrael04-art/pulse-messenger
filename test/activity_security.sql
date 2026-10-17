begin;
create temporary table activity_fixture(k text primary key,id uuid default gen_random_uuid());
insert into activity_fixture(k) values('creator'),('follower'),('tagged'),('outsider'),('before'),('post'),('private'),('comment'),('video'),('draft');
grant select on activity_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at) select id,'authenticated','authenticated','pulse-activity-'||id||'@example.invalid',now() from activity_fixture where k in('creator','follower','tagged','outsider');
update public.pulse_profiles set username='act_'||left(replace(id::text,'-',''),12),display_name='Activity fixture' where id in(select id from activity_fixture);
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from activity_fixture where k='creator'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_social_write((select id from activity_fixture where k='before'),'post','Before follow','[]','public',false);
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from activity_fixture where k='follower'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_social_follow((select id from activity_fixture where k='creator'),true);
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from activity_fixture where k='creator'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_social_write((select id from activity_fixture where k='post'),'post',
 'Hello @'||(select username from public.pulse_profiles where id=(select id from activity_fixture where k='tagged'))||' and email x@'||(select username from public.pulse_profiles where id=(select id from activity_fixture where k='outsider')),'[]','public',false);
select public.pulse_social_write((select id from activity_fixture where k='private'),'post',
 'Secret @'||(select username from public.pulse_profiles where id=(select id from activity_fixture where k='tagged')),'[]','private',false);
select public.pulse_social_write((select id from activity_fixture where k='draft'),'post','Draft','[]','public',true);
do $$ declare a jsonb;begin
 a=public.pulse_activity();
 if not exists(select 1 from jsonb_array_elements(a->'items') v where v->>'kind'='follow') then raise exception 'FAIL: new follower event';end if;
 if exists(select 1 from jsonb_array_elements(a->'items') v where v->>'kind'='publish') then raise exception 'FAIL: self notification';end if;
end $$;
reset role;
-- Trusted fixture for a video; no real media uploaded in this SQL policy test.
insert into public.pulse_social_content(id,author_id,kind,body,state,media) values((select id from activity_fixture where k='video'),(select id from activity_fixture where k='creator'),'reel','Video fixture','published','[{"kind":"video","path":"fixture-only"}]');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from activity_fixture where k='follower'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_social_action((select id from activity_fixture where k='post'),'like',true);
select public.pulse_social_action((select id from activity_fixture where k='post'),'like',true);
select public.pulse_social_comment((select id from activity_fixture where k='comment'),(select id from activity_fixture where k='post'),
 'Comment @'||(select username from public.pulse_profiles where id=(select id from activity_fixture where k='tagged')),false);
do $$ declare a jsonb;cutoff timestamptz;begin
 a=public.pulse_activity();
 if jsonb_array_length(a->'items')<>2 then raise exception 'FAIL: followed new posts/videos only: %',a;end if;
 if not exists(select 1 from jsonb_array_elements(a->'items') v where v->>'post_id'=(select id::text from activity_fixture where k='video') and (v->>'is_video')::boolean) then raise exception 'FAIL: video classification';end if;
 cutoff=(a->>'as_of')::timestamptz;
 perform public.pulse_activity_read(null,cutoff);
 if (public.pulse_activity()->>'unread')::int<>0 then raise exception 'FAIL: mark all read';end if;
 perform public.pulse_activity_preferences(true,true,true,true,false);
 if jsonb_array_length(public.pulse_activity()->'items')<>0 then raise exception 'FAIL: following opt out';end if;
 perform public.pulse_activity_preferences(true,true,true,true,true);
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from activity_fixture where k='tagged'),'role','authenticated')::text,true);
set local role authenticated;
do $$ declare a jsonb;first_item jsonb;next_page jsonb;begin
 a=public.pulse_activity();
 if jsonb_array_length(a->'items')<>2 or (a->>'unread')::int<>2 then raise exception 'FAIL: post/comment mentions or private leak: %',a;end if;
 first_item=public.pulse_activity(null,null,1)->'items'->0;
 next_page=public.pulse_activity((first_item->>'created_at')::timestamptz,(first_item->>'id')::uuid,1);
 if jsonb_array_length(next_page->'items')<>1 or next_page->'items'->0->>'id'=first_item->>'id' then raise exception 'FAIL: cursor pagination';end if;
 perform public.pulse_activity_read((first_item->>'id')::uuid,null);
 if (public.pulse_activity()->>'unread')::int<>1 then raise exception 'FAIL: individual read';end if;
 perform public.pulse_activity_preferences(false,true,true,true,true);
 if (public.pulse_activity()->>'unread')::int<>0 then raise exception 'FAIL: mention preference';end if;
 perform public.pulse_activity_preferences(true,true,true,true,true);
 perform public.pulse_block_user((select id from activity_fixture where k='creator'),true);
 if jsonb_array_length(public.pulse_activity()->'items')<>0 then raise exception 'FAIL: blocked post or comment context leaked';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from activity_fixture where k='outsider'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if jsonb_array_length(public.pulse_activity()->'items')<>0 then raise exception 'FAIL: unrelated recipient or email parsed as mention';end if;
 begin perform public.pulse_activity_read((select id from activity_fixture where k='post'),null);raise exception 'FAIL: arbitrary mark';exception when others then if sqlerrm='FAIL: arbitrary mark' then raise;end if;end;
 begin execute 'select * from pulse_private.activity_events';raise exception 'FAIL: raw notifications leaked';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from activity_fixture where k='creator'),'role','authenticated')::text,true);
set local role authenticated;
do $$ declare a jsonb;begin
 a=public.pulse_activity();
 if (select count(*) from jsonb_array_elements(a->'items') v where v->>'kind'='like')<>1 then raise exception 'FAIL: duplicate likes';end if;
 if not exists(select 1 from jsonb_array_elements(a->'items') v where v->>'kind'='comment') then raise exception 'FAIL: comment alert';end if;
end $$;
select public.pulse_social_edit((select id from activity_fixture where k='post'),'Removed',true);
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from activity_fixture where k='follower'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if exists(select 1 from jsonb_array_elements(public.pulse_activity()->'items') v where v->>'post_id'=(select id::text from activity_fixture where k='post')) then raise exception 'FAIL: deleted content leaked';end if;
end $$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.pulse_activity(timestamptz,uuid,integer)','execute') or has_function_privilege('anon','public.pulse_activity_read(uuid,timestamptz)','execute') then raise exception 'FAIL: anonymous access';end if;
end $$;
rollback;
