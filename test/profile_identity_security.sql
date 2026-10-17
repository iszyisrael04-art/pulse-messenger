begin;
create temporary table identity_fixture(k text primary key,id uuid default gen_random_uuid());
insert into identity_fixture(k) values('free'),('paid'),('peer');
grant select on identity_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_user_meta_data)
 select id,'authenticated','authenticated','pulse-identity-'||id||'@example.invalid',now(),
 case when k='paid' then '{"privacy_version":"2026-10-17","privacy_accepted":true}'::jsonb else '{}'::jsonb end
 from identity_fixture;
do $$ begin
 if (select count(*) from pulse_private.policy_acceptances where user_id in(select id from identity_fixture))<>1 then raise exception 'FAIL: acceptance captured without explicit acknowledgement'; end if;
 if not exists(select 1 from pulse_private.policy_acceptances where user_id=(select id from identity_fixture where k='paid') and version='2026-10-17') then raise exception 'FAIL: acceptance version'; end if;
end $$;
insert into public.pulse_premium(user_id,expires_at) select id,now()+interval '1 day' from identity_fixture where k='paid';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from identity_fixture where k='free'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if not pulse_private.avatar_upload_allowed(auth.uid()::text||'/photo.png','image/png') then raise exception 'FAIL: free photo denied'; end if;
 if pulse_private.avatar_upload_allowed(auth.uid()::text||'/motion.gif','image/gif') then raise exception 'FAIL: free GIF allowed'; end if;
 if pulse_private.avatar_upload_allowed(auth.uid()::text||'/motion.gif','image/png') then raise exception 'FAIL: extension bypass'; end if;
 if pulse_private.avatar_upload_allowed((select id::text from identity_fixture where k='paid')||'/photo.png','image/png') then raise exception 'FAIL: foreign avatar path'; end if;
 begin perform public.pulse_profile_features_save('ocean','','creating');raise exception 'FAIL: free background';exception when others then if sqlerrm='FAIL: free background' then raise;end if;end;
 begin perform public.pulse_profile_features_save('classic','Hello','creating');raise exception 'FAIL: free Signal';exception when others then if sqlerrm='FAIL: free Signal' then raise;end if;end;
 perform public.pulse_profile_features_save('classic','','creating');
 if public.pulse_profile_features(auth.uid())->>'background'<>'classic' then raise exception 'FAIL: free reset';end if;
 begin execute 'select * from pulse_private.policy_acceptances';raise exception 'FAIL: consent records leaked';exception when insufficient_privilege then null;end;
 begin execute 'select * from pulse_private.profile_signals';raise exception 'FAIL: raw Signals leaked';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from identity_fixture where k='paid'),'role','authenticated')::text,true);
set local role authenticated;
do $$ declare f jsonb; begin
 if not pulse_private.avatar_upload_allowed(auth.uid()::text||'/motion.gif','image/gif') then raise exception 'FAIL: Premium GIF denied';end if;
 perform public.pulse_profile_features_save('circuit','Creating Pulse','collaborating');
 f=public.pulse_profile_features(auth.uid());
 if f->>'background'<>'circuit' or f->>'signal'<>'Creating Pulse' or (f->>'motion_until')::timestamptz<=now() or (f->>'motion_until')::timestamptz>now()+interval '60 seconds' then raise exception 'FAIL: Premium features';end if;
 begin perform public.pulse_profile_features_save('ocean',repeat('a',121),'creating');raise exception 'FAIL: long Signal';exception when others then if sqlerrm='FAIL: long Signal' then raise;end if;end;
 begin perform public.pulse_profile_features_save('invalid','','creating');raise exception 'FAIL: invalid theme';exception when others then if sqlerrm='FAIL: invalid theme' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from identity_fixture where k='peer'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if public.pulse_profile_features((select id from identity_fixture where k='paid'))->>'signal'<>'Creating Pulse' then raise exception 'FAIL: public profile metadata unavailable';end if;
 perform public.pulse_block_user((select id from identity_fixture where k='paid'),true);
 if public.pulse_profile_features((select id from identity_fixture where k='paid')) is not null then raise exception 'FAIL: blocked features leak';end if;
end $$;
reset role;
update public.pulse_premium set expires_at=now()-interval '1 minute' where user_id=(select id from identity_fixture where k='paid');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from identity_fixture where k='paid'),'role','authenticated')::text,true);
set local role authenticated;
do $$ declare f jsonb;begin
 f=public.pulse_profile_features(auth.uid());
 if f->>'background'<>'classic' or f->>'signal'<>'' or f->>'motion_until' is not null then raise exception 'FAIL: expired features retained';end if;
 if pulse_private.avatar_upload_allowed(auth.uid()::text||'/motion.gif','image/gif') then raise exception 'FAIL: expired GIF allowed';end if;
 begin perform public.pulse_profile_features_save('ocean','','creating');raise exception 'FAIL: expired write';exception when others then if sqlerrm='FAIL: expired write' then raise;end if;end;
 perform public.pulse_profile_features_save('classic','','creating');
end $$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.pulse_profile_features(uuid)','execute') or has_function_privilege('anon','public.pulse_profile_features_save(text,text,text)','execute') then raise exception 'FAIL: anonymous access';end if;
 if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='pulse_avatar_insert' and with_check like '%avatar_upload_allowed%') then raise exception 'FAIL: avatar storage gate missing';end if;
end $$;
rollback;
