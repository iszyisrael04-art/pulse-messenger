begin;
create temporary table personal_fixture(k text primary key,id uuid default gen_random_uuid());
insert into personal_fixture(k) values('host'),('viewer'),('stranger'),('channel'),('personal'),('channel_live');
grant select,update on personal_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at) select id,'authenticated','authenticated','personal-'||id||'@example.invalid',now() from personal_fixture where k in('host','viewer','stranger');
update pulse_private.live_policy set min_followers=1;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from personal_fixture where k='host'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 begin perform public.pulse_personal_live('start','Denied');raise exception 'FAIL: bypass follower minimum';exception when others then if sqlerrm like 'FAIL:%' then raise;end if;end;
end$$;
reset role;
insert into public.pulse_social_follows(follower_id,creator_id,state) select v.id,h.id,'accepted' from personal_fixture v,personal_fixture h where v.k='viewer' and h.k='host';
set local role authenticated;
update personal_fixture set id=(public.pulse_personal_live('start','Personal broadcast')->'session'->>'id')::uuid where k='personal';
update personal_fixture set id=public.pulse_create_channel('Separate channel','Test') where k='channel';
do $$begin
 if (select channel_id from public.pulse_live_sessions where id=(select id from personal_fixture where k='personal')) is not null then raise exception 'FAIL: personal live owns channel';end if;
 if (public.pulse_personal_live('start','Resume')->'session'->>'id')::uuid<>(select id from personal_fixture where k='personal')then raise exception 'FAIL: duplicated personal live';end if;
 if (public.pulse_live_party('access',(select id from personal_fixture where k='personal'))->>'publish')::boolean is not true then raise exception 'FAIL: personal host publish';end if;
 if public.pulse_live_moderator((select id from personal_fixture where k='personal')) is not true then raise exception 'FAIL: personal host moderation';end if;
 begin perform public.pulse_live_start((select id from personal_fixture where k='channel'),'Channel');raise exception 'FAIL: social followers count as channel followers';exception when others then if sqlerrm like 'FAIL:%' then raise;end if;end;
end$$;
reset role;
insert into public.pulse_followers(channel_id,user_id) select c.id,v.id from personal_fixture c,personal_fixture v where c.k='channel' and v.k='viewer';
set local role authenticated;
update personal_fixture set id=public.pulse_live_start((select id from personal_fixture where k='channel'),'Channel') where k='channel_live';
select public.pulse_live_tools('settings',(select id from personal_fixture where k='personal'),null,null,'{"slow_seconds":5}');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from personal_fixture where k='viewer'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_live_party('request',(select id from personal_fixture where k='personal'),null,'video');
select public.pulse_live_chat_send((select id from personal_fixture where k='personal'),gen_random_uuid(),'Personal comment');
do $$begin
 if public.pulse_live_moderator((select id from personal_fixture where k='personal')) then raise exception 'FAIL: viewer moderator';end if;
 begin perform public.pulse_live_end((select id from personal_fixture where k='personal'));raise exception 'FAIL: viewer ended live';exception when others then if sqlerrm like 'FAIL:%' then raise;end if;end;
end$$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from personal_fixture where k='host'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_live_party('approve',(select id from personal_fixture where k='personal'),(select id from personal_fixture where k='viewer'));
do $$begin
 if (public.pulse_live_party('access',(select id from personal_fixture where k='personal'),(select id from personal_fixture where k='viewer'))->>'publish')::boolean is not true then raise exception 'FAIL: personal guest publish';end if;
end$$;
reset role;
insert into public.pulse_social_accounts(user_id,is_private) select id,true from personal_fixture where k='host' on conflict(user_id)do update set is_private=true;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from personal_fixture where k='stranger'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 if exists(select 1 from public.pulse_live_sessions where id=(select id from personal_fixture where k='personal'))then raise exception 'FAIL: private session leak';end if;
 if exists(select 1 from public.pulse_live_chat where session_id=(select id from personal_fixture where k='personal'))then raise exception 'FAIL: private chat leak';end if;
 begin perform public.pulse_personal_live('info',null,(select id from personal_fixture where k='host'));raise exception 'FAIL: private live badge leak';exception when others then if sqlerrm like 'FAIL:%' then raise;end if;end;
 begin perform public.pulse_live_party('access',(select id from personal_fixture where k='personal'));raise exception 'FAIL: private party leak';exception when others then if sqlerrm like 'FAIL:%' then raise;end if;end;
 begin perform public.pulse_live_gifts('info',(select id from personal_fixture where k='personal'));raise exception 'FAIL: private gifts leak';exception when others then if sqlerrm like 'FAIL:%' then raise;end if;end;
end$$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from personal_fixture where k='host'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_live_end((select id from personal_fixture where k='personal'));
do $$begin
 if public.pulse_personal_live('info')->'session'<>'null'::jsonb then raise exception 'FAIL: stale live badge';end if;
 if not exists(select 1 from public.pulse_live_sessions where id=(select id from personal_fixture where k='channel_live') and status='live') then raise exception 'FAIL: ended separate channel';end if;
end$$;
reset role;
rollback;
