begin;
create temporary table summary_fixture(k text primary key,id uuid default gen_random_uuid());
insert into summary_fixture(k) values('a'),('b'),('c'),('outsider'),('chat'),('old'),('latest'),('deleted');
grant select on summary_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at) select id,'authenticated','authenticated',id||'@example.invalid',now() from summary_fixture where k in('a','b','c','outsider');
update public.pulse_profiles set display_name='Danny' where id=(select id from summary_fixture where k='b');
insert into public.pulse_chats(id,kind,name,owner_id) select c.id,'group','Summary fixture',u.id from summary_fixture c,summary_fixture u where c.k='chat' and u.k='a';
insert into public.pulse_members(chat_id,user_id,role) select c.id,u.id,case when u.k='a' then 'owner' else 'member' end from summary_fixture c,summary_fixture u where c.k='chat' and u.k in('a','b','c');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from summary_fixture where k='a'),'role','authenticated')::text,true);
insert into public.pulse_messages(id,chat_id,sender_id,body,created_at) select m.id,c.id,u.id,'Older incoming',now()-interval '3 seconds' from summary_fixture m,summary_fixture c,summary_fixture u where m.k='old' and c.k='chat' and u.k='b';
insert into public.pulse_messages(id,chat_id,sender_id,body,created_at) select m.id,c.id,u.id,'How was your day?',now()-interval '2 seconds' from summary_fixture m,summary_fixture c,summary_fixture u where m.k='latest' and c.k='chat' and u.k='a';
insert into public.pulse_messages(id,chat_id,sender_id,body,created_at,deleted_at) select m.id,c.id,u.id,'Deleted latest',now()-interval '1 second',now() from summary_fixture m,summary_fixture c,summary_fixture u where m.k='deleted' and c.k='chat' and u.k='c';
create function pg_temp.summary_row() returns jsonb language sql as $$
 select value from jsonb_array_elements(public.pulse_chat_summaries()) where value->>'chat_id'=(select id::text from summary_fixture where k='chat')
$$;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from summary_fixture where k='a'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 if pg_temp.summary_row()->>'body'<>'How was your day?' or pg_temp.summary_row()->>'delivery'<>'sent' then raise exception 'FAIL latest visible sent preview';end if;
end $$;
reset role;
insert into public.pulse_receipts(message_id,user_id,delivered_at) select m.id,u.id,now() from summary_fixture m,summary_fixture u where m.k='latest' and u.k='b';
set local role authenticated;
do $$begin if pg_temp.summary_row()->>'delivery'<>'sent' then raise exception 'FAIL fabricated group delivery';end if;end $$;
reset role;
insert into public.pulse_receipts(message_id,user_id,delivered_at) select m.id,u.id,now() from summary_fixture m,summary_fixture u where m.k='latest' and u.k='c';
set local role authenticated;
do $$begin if pg_temp.summary_row()->>'delivery'<>'delivered' then raise exception 'FAIL delivered preview';end if;end $$;
reset role;
update public.pulse_receipts set read_at=now() where message_id=(select id from summary_fixture where k='latest');
set local role authenticated;
do $$begin if pg_temp.summary_row()->>'delivery'<>'read' then raise exception 'FAIL read preview';end if;end $$;
reset role;
insert into public.pulse_message_preferences(message_id,user_id,hidden) select m.id,u.id,true from summary_fixture m,summary_fixture u where m.k='latest' and u.k='a';
set local role authenticated;
do $$begin
 if pg_temp.summary_row()->>'body'<>'Older incoming' or pg_temp.summary_row()->>'sender_name'<>'Danny' or pg_temp.summary_row()->>'delivery' is not null then raise exception 'FAIL hidden message or incoming receipt privacy';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from summary_fixture where k='outsider'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin if pg_temp.summary_row() is not null then raise exception 'FAIL outsider summary leak';end if;end $$;
reset role;
insert into public.pulse_blocks(user_id,blocked_id) select a.id,b.id from summary_fixture a,summary_fixture b where a.k='a' and b.k='b';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from summary_fixture where k='a'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin if pg_temp.summary_row() is not null then raise exception 'FAIL blocked chat summary leak';end if;end $$;
reset role;
do $$begin
 if has_function_privilege('anon','public.pulse_chat_summaries()','execute') then raise exception 'FAIL anonymous summaries';end if;
 if (select count(*) from pulse_private.gift_catalog where enabled and sku in('archmage','moon_witch','wizard_filter','witch_filter'))<>4 then raise exception 'FAIL magic catalogue';end if;
 if exists(select 1 from pulse_private.gift_catalog where enabled and sku in('voltage_dominion','void_rift','solar_overdrive','quantum_cathedral','prism_avalanche','aurora_ascension','gravity_collapse','pulse_supernova')) then raise exception 'FAIL retired effects still active';end if;
end $$;
rollback;
