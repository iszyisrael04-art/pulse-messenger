begin;
create temporary table pulse_push_test(k text primary key,id uuid default gen_random_uuid());
insert into pulse_push_test(k) values('alice'),('bob'),('device'),('message'),('chat');
grant select,update on pulse_push_test to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at) select id,'authenticated','authenticated','pulse-push-'||id::text||'@example.invalid',now() from pulse_push_test where k in ('alice','bob');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_push_test where k='bob'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_push_register((select id from pulse_push_test where k='device'),'test-device-token-private-123456789');
do $$ begin
 begin perform public.pulse_push_claim(); raise exception 'FAIL: client claimed push queue'; exception when insufficient_privilege then null; end;
 begin perform 1 from pulse_private.push_devices; raise exception 'FAIL: client read device tokens'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_push_test where k='alice'),'role','authenticated')::text,true);
set local role authenticated;
update pulse_push_test set id=public.pulse_start_chat(array[(select id from pulse_push_test where k='bob')],'Push fixture',false) where k='chat';
select public.pulse_send_message((select id from pulse_push_test where k='message'),(select id from pulse_push_test where k='chat'),'Private text excluded from push',null,null);
do $$ begin
 begin perform public.pulse_push_register((select id from pulse_push_test where k='device'),'attacker-token-private-123456789'); raise exception 'FAIL: device hijack'; exception when others then if sqlerrm='FAIL: device hijack' then raise; end if; end;
end $$;
reset role;
do $$ begin
 if (select count(*) from pulse_private.push_outbox where message_id=(select id from pulse_push_test where k='message'))<>1 then raise exception 'FAIL: recipient queue'; end if;
 if not pulse_private.push_allowed((select id from pulse_push_test where k='message'),(select id from pulse_push_test where k='bob')) then raise exception 'FAIL: recipient eligibility'; end if;
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_push_test where k='bob'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_push_disable((select id from pulse_push_test where k='device'),true);
select public.pulse_block_user((select id from pulse_push_test where k='alice'),true);
reset role;
do $$ begin
 if exists(select 1 from pulse_private.push_devices where user_id=(select id from pulse_push_test where k='bob')) then raise exception 'FAIL: global push disable'; end if;
 if pulse_private.push_allowed((select id from pulse_push_test where k='message'),(select id from pulse_push_test where k='bob')) then raise exception 'FAIL: blocked push eligibility'; end if;
end $$;
select 'PASS: token privacy, registration ownership, recipient queue, server-only claiming, global disable, block eligibility' as result;
rollback;
