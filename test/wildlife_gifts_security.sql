begin;
do $$begin
 if (select count(*) from pulse_private.gift_catalog where enabled and sku in ('lion','gorilla','royal_lions','thunder_falcon','butterfly'))<>5 then raise exception 'FAIL animal gift catalogue';end if;
 if exists(select 1 from pulse_private.gift_catalog where enabled and sku in ('galaxy','archmage','moon_witch','wizard_filter','witch_filter','voltage_dominion','pulse_supernova')) then raise exception 'FAIL retired effect still enabled';end if;
end$$;
create temporary table wildlife_fixture(k text primary key,id uuid default gen_random_uuid());
insert into wildlife_fixture(k) values('host'),('viewer'),('live'),('first'),('second');
grant select on wildlife_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at) select id,'authenticated','authenticated',id||'@example.invalid',now() from wildlife_fixture where k in('host','viewer');
insert into public.pulse_live_sessions(id,host_id,title) select l.id,h.id,'Combo test' from wildlife_fixture l,wildlife_fixture h where l.k='live' and h.k='host';
insert into pulse_private.wallets(user_id,coins,p_coins) select id,30,0 from wildlife_fixture where k='viewer';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from wildlife_fixture where k='viewer'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_live_gifts('send',(select id from wildlife_fixture where k='live'),(select id from wildlife_fixture where k='host'),'rose',1,(select id from wildlife_fixture where k='first'));
select public.pulse_live_gifts('send',(select id from wildlife_fixture where k='live'),(select id from wildlife_fixture where k='host'),'rose',1,(select id from wildlife_fixture where k='first'));
select public.pulse_live_gifts('send',(select id from wildlife_fixture where k='live'),(select id from wildlife_fixture where k='host'),'rose',1,(select id from wildlife_fixture where k='second'));
do $$declare feed jsonb;begin
 if (public.pulse_wallet()->>'coins')::int<>10 then raise exception 'FAIL combo or duplicate debit';end if;
 feed=public.pulse_gift_feed((select id from wildlife_fixture where k='live'),'1970-01-01','00000000-0000-0000-0000-000000000000');
 if jsonb_array_length(feed->'items')<>2 or (feed->'items'->0->>'coins')::int<>10 then raise exception 'FAIL gift unit price or events';end if;
 begin perform public.pulse_live_gifts('send',(select id from wildlife_fixture where k='live'),(select id from wildlife_fixture where k='host'),'lion',1,gen_random_uuid());raise exception 'FAIL overspend';exception when others then if sqlerrm='FAIL overspend' then raise;end if;end;
end$$;
reset role;
rollback;
