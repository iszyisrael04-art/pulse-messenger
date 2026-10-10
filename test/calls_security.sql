begin;
create temporary table pulse_call_test(k text primary key,id uuid default gen_random_uuid());
insert into pulse_call_test(k) values('owner'),('peer'),('outsider'),('chat'),('call');
grant select,update on pulse_call_test to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at)
select id,'authenticated','authenticated','pulse-call-'||id::text||'@example.invalid',now()
from pulse_call_test where k in ('owner','peer','outsider');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_call_test where k='owner'),'role','authenticated')::text,true);
set local role authenticated;
update pulse_call_test set id=public.pulse_start_chat(array[(select id from pulse_call_test where k='peer')],'Call fixture',false) where k='chat';
update pulse_call_test set id=public.pulse_call_start((select id from pulse_call_test where k='chat'),'video') where k='call';
do $$ begin
 if (select count(*) from public.pulse_call_members where call_id=(select id from pulse_call_test where k='call'))<>2 then raise exception 'FAIL: member snapshot'; end if;
 begin perform public.pulse_call_start((select id from pulse_call_test where k='chat'),'voice'); raise exception 'FAIL: busy reservation'; exception when others then if sqlerrm='FAIL: busy reservation' then raise; end if; end;
 begin perform pulse_private.cleanup_call((select id from pulse_call_test where k='call')); raise exception 'FAIL: internal function accessible'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_call_test where k='outsider'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.pulse_calls where id=(select id from pulse_call_test where k='call')) then raise exception 'FAIL: outsider history visible'; end if;
 if exists(select 1 from public.pulse_call_members where call_id=(select id from pulse_call_test where k='call')) then raise exception 'FAIL: outsider members visible'; end if;
 begin perform public.pulse_call_accept((select id from pulse_call_test where k='call')); raise exception 'FAIL: outsider accepted'; exception when others then if sqlerrm='FAIL: outsider accepted' then raise; end if; end;
 begin perform public.pulse_call_state((select id from pulse_call_test where k='call'),true); raise exception 'FAIL: outsider heartbeat'; exception when others then if sqlerrm='FAIL: outsider heartbeat' then raise; end if; end;
 begin perform public.pulse_call_start((select id from pulse_call_test where k='chat'),'voice'); raise exception 'FAIL: outsider started'; exception when others then if sqlerrm='FAIL: outsider started' then raise; end if; end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_call_test where k='peer'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_call_accept((select id from pulse_call_test where k='call'));
do $$ begin
 if (public.pulse_call_state((select id from pulse_call_test where k='call'),true)->>'status')<>'active' then raise exception 'FAIL: accept state'; end if;
end $$;
select public.pulse_call_leave((select id from pulse_call_test where k='call'),false);
do $$ begin
 if (public.pulse_call_state((select id from pulse_call_test where k='call'),false)->>'status')<>'ended' then raise exception 'FAIL: leave not reconciled'; end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_call_test where k='owner'),'role','authenticated')::text,true);
set local role authenticated;
update pulse_call_test set id=public.pulse_call_start((select id from pulse_call_test where k='chat'),'voice') where k='call';
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_call_test where k='peer'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_call_accept((select id from pulse_call_test where k='call'));
reset role;
delete from public.pulse_members where chat_id=(select id from pulse_call_test where k='chat') and user_id=(select id from pulse_call_test where k='peer');
set local role authenticated;
do $$ begin
 if (public.pulse_call_state((select id from pulse_call_test where k='call'),true)->>'status')<>'ended' then raise exception 'FAIL: removed member retained call'; end if;
end $$;
reset role;
insert into public.pulse_members(chat_id,user_id,role) select c.id,u.id,'member' from pulse_call_test c,pulse_call_test u where c.k='chat' and u.k='peer';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_call_test where k='owner'),'role','authenticated')::text,true);
set local role authenticated;
update pulse_call_test set id=public.pulse_call_start((select id from pulse_call_test where k='chat'),'voice') where k='call';
reset role;
update public.pulse_calls set ring_deadline=now()-interval '1 second' where id=(select id from pulse_call_test where k='call');
set local role authenticated;
do $$ begin
 if (public.pulse_call_state((select id from pulse_call_test where k='call'),true)->>'status')<>'ended' then raise exception 'FAIL: unanswered expiry'; end if;
end $$;
reset role;
insert into public.pulse_blocks(user_id,blocked_id) select a.id,b.id from pulse_call_test a,pulse_call_test b where a.k='peer' and b.k='owner';
set local role authenticated;
do $$ begin
 begin perform public.pulse_call_start((select id from pulse_call_test where k='chat'),'voice'); raise exception 'FAIL: blocked call started'; exception when others then if sqlerrm='FAIL: blocked call started' then raise; end if; end;
end $$;
reset role;
select 'PASS: call RLS, authorization, busy, accept, leave, expiry, removed members, blocks and internal privileges' as result;
rollback;
