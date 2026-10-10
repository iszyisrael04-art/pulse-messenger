-- Transactional test identities and content are rolled back. Never delete existing users.
begin;
create temporary table pulse_test_ids(k text primary key,id uuid default gen_random_uuid());
insert into pulse_test_ids(k) values('alice'),('bob'),('outsider'),('chat'),('message');
grant select on pulse_test_ids to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at) select id,'authenticated','authenticated','pulse-test-'||id::text||'@example.invalid',now() from pulse_test_ids where k in ('alice','bob','outsider');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_test_ids where k='alice'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_save_profile('test_'||substr(replace((select id::text from pulse_test_ids where k='alice'),'-',''),1,12),'Alice','Test',null);
-- Direct conversation must be idempotent.
select public.pulse_start_chat(array[(select id from pulse_test_ids where k='bob')],'Test',false);
select public.pulse_start_chat(array[(select id from pulse_test_ids where k='bob')],'Test',false);
select public.pulse_send_message((select id from pulse_test_ids where k='message'),(select id from public.pulse_chats where owner_id=auth.uid()),'Hello',null,null);
select public.pulse_send_message((select id from pulse_test_ids where k='message'),(select id from public.pulse_chats where owner_id=auth.uid()),'Hello',null,null);
select public.pulse_redeem('30DAYSPULSE');
do $$ begin
 if (select count(*) from public.pulse_chats where owner_id=auth.uid())<>1 then raise exception 'FAIL: duplicate direct chat'; end if;
 if (select count(*) from public.pulse_messages where sender_id=auth.uid())<>1 then raise exception 'FAIL: duplicate message'; end if;
 if not exists(select 1 from public.pulse_premium where user_id=auth.uid() and expires_at>now()+interval '29 days') then raise exception 'FAIL: premium expiry'; end if;
 begin perform public.pulse_redeem('30DAYSPULSE'); raise exception 'FAIL: duplicate redemption'; exception when others then if sqlerrm='FAIL: duplicate redemption' then raise; end if; end;
 begin update public.pulse_premium set expires_at=now()+interval '100 years'; raise exception 'FAIL: direct premium mutation'; exception when insufficient_privilege then null; end;
 begin perform public.pulse_login_lookup('nobody','x'); raise exception 'FAIL: email lookup'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_test_ids where k='outsider'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.pulse_chats) or exists(select 1 from public.pulse_messages) or exists(select 1 from public.pulse_members) then raise exception 'FAIL: outsider sees private chat'; end if;
 begin perform public.pulse_send_message((select id from pulse_test_ids where k='chat'),(select chat_id from public.pulse_messages),'Attack',null,null); raise exception 'FAIL: unauthorized send'; exception when others then if sqlerrm='FAIL: unauthorized send' then raise; end if; end;
 begin perform public.pulse_change_message((select id from pulse_test_ids where k='message'),'Attack',false); raise exception 'FAIL: unauthorized edit'; exception when others then if sqlerrm='FAIL: unauthorized edit' then raise; end if; end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_test_ids where k='bob'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if (select count(*) from public.pulse_messages)<>1 then raise exception 'FAIL: recipient cannot read'; end if;
 begin perform public.pulse_change_message((select id from pulse_test_ids where k='message'),'Attack',false); raise exception 'FAIL: recipient edits sender message'; exception when others then if sqlerrm='FAIL: recipient edits sender message' then raise; end if; end;
end $$;
select public.pulse_mark_read((select id from public.pulse_chats limit 1));
select public.pulse_react((select id from pulse_test_ids where k='message'),'❤️');
select public.pulse_block_user((select id from pulse_test_ids where k='alice'),true);
do $$ begin
 begin perform public.pulse_send_message((select id from pulse_test_ids where k='chat'),(select id from public.pulse_chats limit 1),'Blocked',null,null); raise exception 'FAIL: blocked sender'; exception when others then if sqlerrm='FAIL: blocked sender' then raise; end if; end;
end $$;
reset role;
select 'PASS: isolation, membership, idempotency, premium access, redemption uniqueness, ownership, receipts, reactions, blocking' as result;
rollback;
