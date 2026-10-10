begin;
create temporary table pulse_v02_ids(k text primary key,id uuid default gen_random_uuid());
insert into pulse_v02_ids(k) values('owner'),('fan'),('admin'),('channel'),('live'),('message');
grant select,update on pulse_v02_ids to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at) select id,'authenticated','authenticated','pulse-v02-'||id::text||'@example.invalid',now() from pulse_v02_ids where k in ('owner','fan','admin');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_v02_ids where k='owner'),'role','authenticated')::text,true);
set local role authenticated;
update pulse_v02_ids set id=public.pulse_create_channel('Test channel','A rollback fixture') where k='channel';
select public.pulse_channel_post((select id from pulse_v02_ids where k='channel'),'Admin post');
select public.pulse_channel_set_admin((select id from pulse_v02_ids where k='channel'),(select id from pulse_v02_ids where k='admin'),true);
update pulse_v02_ids set id=public.pulse_live_start((select id from pulse_v02_ids where k='channel'),'Test broadcast') where k='live';
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_v02_ids where k='fan'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 begin perform public.pulse_channel_post((select id from pulse_v02_ids where k='channel'),'Fan attack'); raise exception 'FAIL: fan posted'; exception when others then if sqlerrm='FAIL: fan posted' then raise; end if; end;
 begin perform public.pulse_live_start((select id from pulse_v02_ids where k='channel'),'Fan attack'); raise exception 'FAIL: fan broadcast'; exception when others then if sqlerrm='FAIL: fan broadcast' then raise; end if; end;
 begin perform public.pulse_live_chat_send((select id from pulse_v02_ids where k='live'),(select id from pulse_v02_ids where k='message'),'Not following'); raise exception 'FAIL: nonfollower chatted'; exception when others then if sqlerrm='FAIL: nonfollower chatted' then raise; end if; end;
end $$;
select public.pulse_follow_channel((select id from pulse_v02_ids where k='channel'),true);
select public.pulse_live_chat_send((select id from pulse_v02_ids where k='live'),(select id from pulse_v02_ids where k='message'),'Hello live');
select public.pulse_live_chat_send((select id from pulse_v02_ids where k='live'),(select id from pulse_v02_ids where k='message'),'Hello live');
do $$ begin
 if (select count(*) from public.pulse_live_chat where session_id=(select id from pulse_v02_ids where k='live'))<>1 then raise exception 'FAIL: duplicate live chat'; end if;
 begin perform public.pulse_live_chat_send((select id from pulse_v02_ids where k='live'),gen_random_uuid(),'Spam'); raise exception 'FAIL: rate limit'; exception when others then if sqlerrm='FAIL: rate limit' then raise; end if; end;
 begin perform public.pulse_live_end((select id from pulse_v02_ids where k='live')); raise exception 'FAIL: fan ended live'; exception when others then if sqlerrm='FAIL: fan ended live' then raise; end if; end;
end $$;
select public.pulse_post_react((select id from public.pulse_posts where channel_id=(select id from pulse_v02_ids where k='channel') limit 1),'❤️');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_v02_ids where k='admin'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_live_chat_hide((select id from pulse_v02_ids where k='message'));
do $$ begin
 if exists(select 1 from public.pulse_live_chat where id=(select id from pulse_v02_ids where k='message')) then raise exception 'FAIL: hidden chat visible'; end if;
 if not public.pulse_channel_admin((select id from pulse_v02_ids where k='channel')) then raise exception 'FAIL: admin role'; end if;
end $$;
select public.pulse_live_end((select id from pulse_v02_ids where k='live'));
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_v02_ids where k='fan'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 begin perform public.pulse_live_chat_send((select id from pulse_v02_ids where k='live'),gen_random_uuid(),'After end'); raise exception 'FAIL: chat after live'; exception when others then if sqlerrm='FAIL: chat after live' then raise; end if; end;
end $$;
reset role;
select 'PASS: admin-only posts, fan broadcast denial, follower live chat, deduplication, rate limit, moderation and end closure' as result;
rollback;
