begin;
do $$begin
 if(select count(*) from pulse_private.gift_catalog where sku like 'legend_%' and enabled)<>9 then raise exception 'FAIL legendary count';end if;
 if exists(select 1 from (values('legend_lion_king',1000),('legend_phoenix',5000),('legend_thunder_god',7500),('legend_phantom_supercar',10000),('legend_cosmic_rocket',15000),('legend_royal_palace',20000),('legend_galaxy_dragon',30000),('legend_pulse_legend',50000),('legend_pulse_universe',60000))v(sku,coins) left join pulse_private.gift_catalog g using(sku) where g.coins is distinct from v.coins)then raise exception 'FAIL legendary prices';end if;
end$$;
create temporary table legend_fixture(k text primary key,id uuid default gen_random_uuid());
insert into legend_fixture(k)values('host'),('viewer'),('live'),('one'),('two');
grant select on legend_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at)select id,'authenticated','authenticated',id||'@example.invalid',now()from legend_fixture where k in('host','viewer');
insert into public.pulse_live_sessions(id,host_id,title)select l.id,h.id,'Legend fixture'from legend_fixture l,legend_fixture h where l.k='live'and h.k='host';
insert into pulse_private.wallets(user_id,coins,p_coins)select id,2500,0 from legend_fixture where k='viewer';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from legend_fixture where k='viewer'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_live_gifts('send',(select id from legend_fixture where k='live'),(select id from legend_fixture where k='host'),'legend_lion_king',1,(select id from legend_fixture where k='one'));
select public.pulse_live_gifts('send',(select id from legend_fixture where k='live'),(select id from legend_fixture where k='host'),'legend_lion_king',1,(select id from legend_fixture where k='one'));
select public.pulse_live_gifts('send',(select id from legend_fixture where k='live'),(select id from legend_fixture where k='host'),'legend_lion_king',1,(select id from legend_fixture where k='two'));
do $$begin
 if(public.pulse_wallet()->>'coins')::int<>500 then raise exception 'FAIL combo duplicate debit';end if;
 begin perform public.pulse_live_gifts('send',(select id from legend_fixture where k='live'),(select id from legend_fixture where k='host'),'legend_lion_king',1,gen_random_uuid());raise exception 'FAIL overspend';exception when others then if sqlerrm='FAIL overspend'then raise;end if;end;
 if(public.pulse_wallet()->>'coins')::int<>500 then raise exception 'FAIL rejection changed balance';end if;
end$$;
reset role;
rollback;
