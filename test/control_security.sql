begin;
create temporary table control_fixture(k text primary key,id uuid default gen_random_uuid());
insert into control_fixture(k) values('staff'),('owner'),('member'),('other'),('group'),('post'),('appeal');
grant select,update on control_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_user_meta_data) select id,'authenticated','authenticated','control-'||id||'@example.invalid',now(),'{"admin":true}' from control_fixture where k in('staff','owner','member','other');
update public.pulse_profiles set username='ctl_'||left(replace(id::text,'-',''),12) where id in(select id from control_fixture);
insert into pulse_private.admins(user_id) select id from control_fixture where k='staff';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from control_fixture where k='owner'),'role','authenticated')::text,true);
set local role authenticated;
update control_fixture set id=(public.pulse_communities('create',null,null,jsonb_build_object('name','Fixture community','handle','fixture_'||left(id::text,8)))#>>'{}')::uuid where k='group';
do $$ begin
 begin perform public.pulse_control('verify',(select id from control_fixture where k='other'),'{}');raise exception 'FAIL: user metadata escalated staff';exception when others then if sqlerrm='FAIL: user metadata escalated staff' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from control_fixture where k='member'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_communities('request',(select id from control_fixture where k='group'));
do $$ begin
 if exists(select 1 from public.pulse_members where chat_id=(select id from control_fixture where k='group') and user_id=auth.uid()) then raise exception 'FAIL: self joined without approval';end if;
 begin perform public.pulse_communities('approve',(select id from control_fixture where k='group'),auth.uid());raise exception 'FAIL: self approved';exception when others then if sqlerrm='FAIL: self approved' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from control_fixture where k='owner'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if jsonb_array_length(public.pulse_inbox()->'community_requests')<>1 then raise exception 'FAIL: admin inbox request missing';end if;
end $$;
select public.pulse_communities('approve',(select id from control_fixture where k='group'),(select id from control_fixture where k='member'));
select public.pulse_social_write((select id from control_fixture where k='post'),'post','Tagged !'||(public.pulse_communities('list',(select id from control_fixture where k='group'))->0->>'handle'),'[]','public',false);
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from control_fixture where k='member'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if not exists(select 1 from jsonb_array_elements(public.pulse_activity()->'items')v where v->>'kind'='community_tag') then raise exception 'FAIL: member community tag missing';end if;
 if jsonb_array_length(public.pulse_communities('list',null,auth.uid()))<>1 then raise exception 'FAIL: profile membership';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from control_fixture where k='other'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if exists(select 1 from jsonb_array_elements(public.pulse_activity()->'items')v where v->>'kind'='community_tag') then raise exception 'FAIL: outsider notification leaked';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from control_fixture where k='staff'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_control('verify',(select id from control_fixture where k='member'));
select public.pulse_control('ban',(select id from control_fixture where k='member'),'{"reason":"Fixture test ban"}');
do $$ begin
 begin perform public.pulse_control('ban',auth.uid(),'{"reason":"Fixture self ban"}');raise exception 'FAIL: staff self ban';exception when others then if sqlerrm='FAIL: staff self ban' then raise;end if;end;
end $$;
reset role;
do $$ begin
 if not exists(select 1 from public.pulse_social_accounts where user_id=(select id from control_fixture where k='member') and verified) then raise exception 'FAIL: verified flag';end if;
 if (select count(*) from pulse_private.email_jobs where user_id=(select id from control_fixture where k='member'))<>2 then raise exception 'FAIL: notification emails not queued';end if;
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from control_fixture where k='member'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if (public.pulse_account_status()->>'active')::boolean then raise exception 'FAIL: banned status';end if;
 if exists(select 1 from public.pulse_profiles) then raise exception 'FAIL: banned stale token raw read';end if;
 begin perform public.pulse_social_profile(auth.uid());raise exception 'FAIL: banned stale token RPC';exception when others then if sqlerrm='FAIL: banned stale token RPC' then raise;end if;end;
 begin perform public.pulse_send_message(gen_random_uuid(),(select id from control_fixture where k='group'),'Bypass',null,null);raise exception 'FAIL: banned send';exception when others then if sqlerrm='FAIL: banned send' then raise;end if;end;
end $$;
update control_fixture set id=(public.pulse_appeals('start')->>'id')::uuid where k='appeal';
-- Metadata-only storage fixture for policy tests; no video bytes are uploaded.
insert into storage.objects(bucket_id,name,metadata) values('pulse-appeals',auth.uid()::text||'/'||(select id::text from control_fixture where k='appeal')||'/appeal-video','{"mimetype":"video/mp4","size":2000}');
select public.pulse_appeals('submit',jsonb_build_object('id',(select id from control_fixture where k='appeal'),'path',auth.uid()::text||'/'||(select id::text from control_fixture where k='appeal')||'/appeal-video','consent',true));
do $$ begin
 begin perform public.pulse_appeals('submit',jsonb_build_object('id',(select id from control_fixture where k='appeal'),'consent',true));raise exception 'FAIL: replayed appeal';exception when others then if sqlerrm='FAIL: replayed appeal' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from control_fixture where k='staff'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_appeals('accept',jsonb_build_object('id',(select id from control_fixture where k='appeal')));
select public.pulse_control('unverify',(select id from control_fixture where k='member'));
select public.pulse_control('suspend',(select id from control_fixture where k='member'),'{"reason":"Fixture timed suspension","days":2}');
reset role;
update pulse_private.account_limits set until_at=now()-interval '1 second' where user_id=(select id from control_fixture where k='member');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from control_fixture where k='member'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if not(public.pulse_account_status()->>'active')::boolean then raise exception 'FAIL: suspension did not expire';end if;
 if public.pulse_social_profile(auth.uid())->>'verified'<>'false' then raise exception 'FAIL: unverify';end if;
end $$;
reset role;
do $$ begin
 if has_function_privilege('authenticated','public.pulse_mail_worker(text,uuid,boolean)','execute') then raise exception 'FAIL: email queue client access';end if;
 if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'pulse_%' and not p.prosecdef and p.proname not in('pulse_account_status','pulse_appeals','pulse_mail_worker') and p.prosrc not like '%pulse_private.require_active()%') then raise exception 'FAIL: unguarded existing RPC';end if;
end $$;
rollback;
