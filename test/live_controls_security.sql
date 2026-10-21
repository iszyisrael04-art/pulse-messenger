begin;
create temporary table live_fixture(k text primary key,id uuid default gen_random_uuid());
insert into live_fixture(k) values('staff'),('host'),('fan'),('other'),('channel'),('live'),('comment');
grant select,update on live_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_user_meta_data) select id,'authenticated','authenticated','live-'||id||'@example.invalid',now(),'{"admin":true}' from live_fixture where k in('staff','host','fan','other');
insert into pulse_private.admins(user_id) select id from live_fixture where k='staff';
insert into public.pulse_channels(id,owner_id,name) select c.id,h.id,'Live test channel' from live_fixture c,live_fixture h where c.k='channel' and h.k='host';
do $$ begin if (select min_followers from pulse_private.live_policy)<>100 then raise exception 'FAIL: default follower minimum';end if;end $$;
-- Small threshold only for isolated test fixtures; outer transaction rolls back.
update pulse_private.live_policy set min_followers=2;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from live_fixture where k='host'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if (public.pulse_live_tools('eligibility',null,(select id from live_fixture where k='channel'))->>'eligible')::boolean then raise exception 'FAIL: zero followers eligible';end if;
 begin perform public.pulse_live_start((select id from live_fixture where k='channel'),'Low followers');raise exception 'FAIL: follower threshold bypass';exception when others then if sqlerrm='FAIL: follower threshold bypass' then raise;end if;end;
 begin perform public.pulse_live_tools('policy_save',null,null,null,'{"min_followers":0}');raise exception 'FAIL: user metadata admin escalation';exception when others then if sqlerrm='FAIL: user metadata admin escalation' then raise;end if;end;
end $$;
reset role;
insert into public.pulse_followers select c.id,f.id from live_fixture c,live_fixture f where c.k='channel' and f.k in('fan','other');
set local role authenticated;
update live_fixture set id=public.pulse_live_start((select id from live_fixture where k='channel'),'Threshold reached') where k='live';
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from live_fixture where k='fan'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_live_tools('like',(select id from live_fixture where k='live'));
select public.pulse_live_tools('like',(select id from live_fixture where k='live'));
do $$ begin
 if (public.pulse_live_tools('info',(select id from live_fixture where k='live'))->>'likes')::int<>1 then raise exception 'FAIL: duplicate live likes';end if;
 begin perform public.pulse_live_tools('settings',(select id from live_fixture where k='live'),null,null,'{"chat_enabled":false}');raise exception 'FAIL: fan changed chat';exception when others then if sqlerrm='FAIL: fan changed chat' then raise;end if;end;
end $$;
select public.pulse_live_chat_send((select id from live_fixture where k='live'),(select id from live_fixture where k='comment'),'Hello');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from live_fixture where k='host'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_live_tools('pin',(select id from live_fixture where k='live'),null,null,jsonb_build_object('message',(select id from live_fixture where k='comment')));
select public.pulse_live_tools('mute',(select id from live_fixture where k='live'),null,(select id from live_fixture where k='fan'),'{"minutes":10}');
select public.pulse_live_tools('settings',(select id from live_fixture where k='live'),null,null,'{"slow_seconds":30,"chat_enabled":false}');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from live_fixture where k='fan'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if public.pulse_live_tools('info',(select id from live_fixture where k='live'))->>'muted_until' is null then raise exception 'FAIL: mute missing';end if;
 if public.pulse_live_tools('info',(select id from live_fixture where k='live'))->'pinned'->>'body'<>'Hello' then raise exception 'FAIL: pin missing';end if;
 begin perform public.pulse_live_chat_send((select id from live_fixture where k='live'),gen_random_uuid(),'Bypass');raise exception 'FAIL: mute/paused bypass';exception when others then if sqlerrm='FAIL: mute/paused bypass' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from live_fixture where k='host'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_live_tools('unmute',(select id from live_fixture where k='live'),null,(select id from live_fixture where k='fan'));
select public.pulse_live_tools('settings',(select id from live_fixture where k='live'),null,null,'{"chat_enabled":true}');
select public.pulse_live_chat_hide((select id from live_fixture where k='comment'));
do $$ begin
 if public.pulse_live_tools('info',(select id from live_fixture where k='live'))->'pinned'<>'null'::jsonb then raise exception 'FAIL: hidden pinned comment';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from live_fixture where k='fan'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 begin perform public.pulse_live_chat_send((select id from live_fixture where k='live'),gen_random_uuid(),'Too soon');raise exception 'FAIL: slow mode bypass';exception when others then if sqlerrm='FAIL: slow mode bypass' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from live_fixture where k='host'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_live_end((select id from live_fixture where k='live'));
do $$ begin
 begin perform public.pulse_live_tools('like',(select id from live_fixture where k='live'));raise exception 'FAIL: ended live likes';exception when others then if sqlerrm='FAIL: ended live likes' then raise;end if;end;
end $$;
reset role;
rollback;
