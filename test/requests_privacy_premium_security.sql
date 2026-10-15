begin;
create temporary table upgrade_fixture(k text primary key,id uuid default gen_random_uuid());
insert into upgrade_fixture(k) values('sender'),('receiver'),('outsider'),('chat'),('first'),('second'),('reply'),('private');
grant select,update on upgrade_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at) select id,'authenticated','authenticated','pulse-upgrade-'||id||'@example.invalid',now() from upgrade_fixture where k in ('sender','receiver','outsider');
insert into pulse_private.promo_codes(code,days) values('PULSE_TEST_'||(select left(upper(id::text),20) from upgrade_fixture where k='sender'),30);
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from upgrade_fixture where k='sender'),'role','authenticated')::text,true);
set local role authenticated;
update upgrade_fixture set id=public.pulse_start_chat(array[(select id from upgrade_fixture where k='receiver')],'Request test',false) where k='chat';
select public.pulse_send_message((select id from upgrade_fixture where k='first'),(select id from upgrade_fixture where k='chat'),'Hello',null,null);
select public.pulse_send_message((select id from upgrade_fixture where k='second'),(select id from upgrade_fixture where k='chat'),'Another message',null,null);
select public.pulse_social_write((select id from upgrade_fixture where k='private'),'post','Only me #SecretFixture','[]','private',false);
do $$ declare one jsonb; two jsonb; begin
 if not exists(select 1 from public.pulse_chat_requests where chat_id=(select id from upgrade_fixture where k='chat') and state='pending' and sent_at is not null) then raise exception 'FAIL: missing request'; end if;
 begin perform public.pulse_respond_request((select id from upgrade_fixture where k='chat'),true);raise exception 'FAIL: sender self accepted';exception when others then if sqlerrm='FAIL: sender self accepted' then raise;end if;end;
 begin perform public.pulse_social_set_profile_style('aurora');raise exception 'FAIL: free theme bypass';exception when others then if sqlerrm='FAIL: free theme bypass' then raise;end if;end;
 one=public.pulse_redeem_result('PULSE_TEST_'||(select left(upper(id::text),20) from upgrade_fixture where k='sender'));
 two=public.pulse_redeem_result('PULSE_TEST_'||(select left(upper(id::text),20) from upgrade_fixture where k='sender'));
 if one->>'expires_at'<>two->>'expires_at' or (one->>'already_redeemed')::boolean or not (two->>'already_redeemed')::boolean then raise exception 'FAIL: redemption retry extended entitlement';end if;
 perform public.pulse_social_set_profile_style('aurora');
 if public.pulse_social_profile_style(auth.uid())<>'aurora' then raise exception 'FAIL: premium style';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from upgrade_fixture where k='receiver'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 begin perform public.pulse_send_message((select id from upgrade_fixture where k='reply'),(select id from upgrade_fixture where k='chat'),'Reply before acceptance',null,null);raise exception 'FAIL: receiver replied before accept';exception when others then if sqlerrm='FAIL: receiver replied before accept' then raise;end if;end;
 if (public.pulse_unread_counts()->>(select id::text from upgrade_fixture where k='chat'))::int<>2 then raise exception 'FAIL: unread count';end if;
 if public.pulse_social_post((select id from upgrade_fixture where k='private')) is not null then raise exception 'FAIL: private content visible';end if;
end $$;
select public.pulse_social_follow((select id from upgrade_fixture where k='sender'),true);
do $$ begin
 if public.pulse_social_post((select id from upgrade_fixture where k='private')) is not null then raise exception 'FAIL: following leaked private audience';end if;
end $$;
select public.pulse_respond_request((select id from upgrade_fixture where k='chat'),true);
select public.pulse_send_message((select id from upgrade_fixture where k='reply'),(select id from upgrade_fixture where k='chat'),'Accepted reply',null,null);
select public.pulse_mark_read((select id from upgrade_fixture where k='chat'));
do $$ begin
 if public.pulse_unread_counts() ? (select id::text from upgrade_fixture where k='chat') then raise exception 'FAIL: read count not cleared';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from upgrade_fixture where k='outsider'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.pulse_chat_requests where chat_id=(select id from upgrade_fixture where k='chat')) then raise exception 'FAIL: outsider request leak';end if;
 begin perform public.pulse_respond_request((select id from upgrade_fixture where k='chat'),false);raise exception 'FAIL: outsider response';exception when others then if sqlerrm='FAIL: outsider response' then raise;end if;end;
end $$;
reset role;
update public.pulse_premium set expires_at=now()-interval '1 day' where user_id=(select id from upgrade_fixture where k='sender');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from upgrade_fixture where k='sender'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if public.pulse_social_profile_style(auth.uid())<>'classic' then raise exception 'FAIL: expired theme retained';end if;
 begin perform public.pulse_redeem_result('PULSE_TEST_'||(select left(upper(id::text),20) from upgrade_fixture where k='sender'));raise exception 'FAIL: expired code reused';exception when others then if sqlerrm='FAIL: expired code reused' then raise;end if;end;
end $$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.pulse_redeem_result(text)','execute') then raise exception 'FAIL: anon redeem';end if;
 if (select count(*) from pulse_private.redemptions where code='PULSE_TEST_'||(select left(upper(id::text),20) from upgrade_fixture where k='sender'))<>1 then raise exception 'FAIL: duplicate history';end if;
end $$;
rollback;
