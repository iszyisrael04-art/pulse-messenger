begin;
create temporary table test_coin_fixture(k text primary key,id uuid default gen_random_uuid());
insert into test_coin_fixture(k)values('host'),('sender'),('other'),('channel'),('live'),('gift');
grant select on test_coin_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at)select id,'authenticated','authenticated','test-coin-'||id||'@example.invalid',now()from test_coin_fixture where k in('host','sender','other');
insert into public.pulse_channels(id,name,description,owner_id)select c.id,'Test coins fixture','',h.id from test_coin_fixture c,test_coin_fixture h where c.k='channel'and h.k='host';
insert into public.pulse_live_sessions(id,channel_id,host_id,title)select l.id,c.id,h.id,'Sandbox gifts'from test_coin_fixture l,test_coin_fixture c,test_coin_fixture h where l.k='live'and c.k='channel'and h.k='host';
insert into pulse_private.test_wallets(user_id,coins)select id,2000000 from test_coin_fixture where k='sender';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from test_coin_fixture where k='sender'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_test_live_gift((select id from test_coin_fixture where k='live'),(select id from test_coin_fixture where k='host'),'rose',1,(select id from test_coin_fixture where k='gift'));
select public.pulse_test_live_gift((select id from test_coin_fixture where k='live'),(select id from test_coin_fixture where k='host'),'rose',1,(select id from test_coin_fixture where k='gift'));
do $$declare w jsonb;begin
 if(public.pulse_test_wallet()->>'coins')::bigint<>1999990 then raise exception 'FAIL duplicate test debit';end if;
 w=public.pulse_wallet();if(w->>'coins')::bigint<>0 or(w->>'p_coins')::numeric<>0 then raise exception 'FAIL test touched real wallet';end if;
 if(public.pulse_gifter_status(auth.uid())->>'rank')::int<>0 then raise exception 'FAIL fake rank progress';end if;
 begin update pulse_private.test_wallets set coins=9000000;raise exception 'FAIL client minted test coins';exception when insufficient_privilege then null;end;
 begin perform public.pulse_test_live_gift((select id from test_coin_fixture where k='live'),(select id from test_coin_fixture where k='host'),'rose',2,(select id from test_coin_fixture where k='gift'));raise exception 'FAIL mismatched retry';exception when others then if sqlerrm='FAIL mismatched retry'then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from test_coin_fixture where k='host'),'role','authenticated')::text,true);
set local role authenticated;
do $$declare w jsonb;begin
 w=public.pulse_wallet();if(w->>'p_coins')::numeric<>0 then raise exception 'FAIL test became cashable';end if;
 if(public.pulse_test_wallet()->>'coins')::bigint<>0 then raise exception 'FAIL another wallet leaked';end if;
end $$;
reset role;
do $$begin
 if exists(select 1 from pulse_private.gift_events where session_id=(select id from test_coin_fixture where k='live'))then raise exception 'FAIL test became real event';end if;
 if pulse_private.withdraw_available((select id from test_coin_fixture where k='host'))<>0 then raise exception 'FAIL test became withdrawable';end if;
end $$;
rollback;
