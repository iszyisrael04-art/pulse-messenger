begin;
create temporary table withdrawal_fixture(k text primary key,id uuid default gen_random_uuid());
insert into withdrawal_fixture(k)values('sender'),('creator'),('staff'),('other'),('channel'),('live'),('gift'),('quote'),('quote2');
grant select,update on withdrawal_fixture to authenticated,service_role;
insert into auth.users(id,aud,role,email,email_confirmed_at)select id,'authenticated','authenticated','withdraw-'||id||'@example.invalid',now()from withdrawal_fixture where k in('sender','creator','staff','other');
insert into pulse_private.admins(user_id)select id from withdrawal_fixture where k='staff';
insert into public.pulse_channels(id,name,description,owner_id)select c.id,'Withdrawal fixture','Test',h.id from withdrawal_fixture c,withdrawal_fixture h where c.k='channel'and h.k='creator';
insert into public.pulse_live_sessions(id,channel_id,host_id,title)select l.id,c.id,h.id,'Withdrawal fixture'from withdrawal_fixture l,withdrawal_fixture c,withdrawal_fixture h where l.k='live'and c.k='channel'and h.k='creator';
insert into pulse_private.wallets(user_id,p_coins)select id,200 from withdrawal_fixture where k='creator';
insert into pulse_private.gift_events(id,sender_id,recipient_id,session_id,sku,quantity,coins,p_coins,created_at)select g.id,s.id,r.id,l.id,'rose',100,500,200,now()from withdrawal_fixture g,withdrawal_fixture s,withdrawal_fixture r,withdrawal_fixture l where g.k='gift'and s.k='sender'and r.k='creator'and l.k='live';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from withdrawal_fixture where k='creator'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 if public.pulse_withdraw_info()->>'available_p_coins'<>'0'then raise exception 'FAIL immature gifts';end if;
 begin perform public.pulse_withdraw_service('quote');raise exception 'FAIL forged exchange quote';exception when insufficient_privilege then null;end;
 begin perform public.pulse_withdraw_info(true);raise exception 'FAIL nonstaff list';exception when others then if sqlerrm='FAIL nonstaff list'then raise;end if;end;
end $$;
reset role;
update pulse_private.gift_events set created_at=now()-interval '8 days'where id=(select id from withdrawal_fixture where k='gift');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
update withdrawal_fixture set id=(public.pulse_withdraw_service('quote',null,(select id from withdrawal_fixture where k='creator'),jsonb_build_object('p_coins',100,'rate_kobo_per_usd',150000,'rate_as_of',now(),'fee_kobo',0,'bank_code','000013','account_number','0123456789','account_name','Fixture only','reference','fixture-payout-1'))->>'id')::uuid where k='quote';
update withdrawal_fixture set id=(public.pulse_withdraw_service('quote',null,(select id from withdrawal_fixture where k='creator'),jsonb_build_object('p_coins',200,'rate_kobo_per_usd',150000,'rate_as_of',now(),'fee_kobo',0,'bank_code','000013','account_number','0123456789','account_name','Fixture only','reference','fixture-payout-2'))->>'id')::uuid where k='quote2';
select public.pulse_withdraw_service('confirm',(select id from withdrawal_fixture where k='quote'),(select id from withdrawal_fixture where k='creator'));
select public.pulse_withdraw_service('confirm',(select id from withdrawal_fixture where k='quote'),(select id from withdrawal_fixture where k='creator'));
do $$begin
 begin perform public.pulse_withdraw_service('confirm',(select id from withdrawal_fixture where k='quote2'),(select id from withdrawal_fixture where k='creator'));raise exception 'FAIL overspent held earnings';exception when others then if sqlerrm='FAIL overspent held earnings'then raise;end if;end;
 begin perform public.pulse_withdraw_service('claim',(select id from withdrawal_fixture where k='quote'),(select id from withdrawal_fixture where k='other'));raise exception 'FAIL nonstaff payout';exception when others then if sqlerrm='FAIL nonstaff payout'then raise;end if;end;
end $$;
do $$declare result jsonb;begin
 result=public.pulse_withdraw_service('claim',(select id from withdrawal_fixture where k='quote'),(select id from withdrawal_fixture where k='staff'));
 if result->>'claimed'<>'true'or result->>'net_kobo'<>'4500000'then raise exception 'FAIL payout quote or claim';end if;
 result=public.pulse_withdraw_service('claim',(select id from withdrawal_fixture where k='quote'),(select id from withdrawal_fixture where k='staff'));
 if result->>'claimed'<>'false'then raise exception 'FAIL duplicate payout dispatch';end if;
end $$;
select public.pulse_withdraw_service('paid',(select id from withdrawal_fixture where k='quote'),(select id from withdrawal_fixture where k='creator'));
select public.pulse_withdraw_service('reversed',(select id from withdrawal_fixture where k='quote'),(select id from withdrawal_fixture where k='staff'));
select public.pulse_withdraw_service('reversed',(select id from withdrawal_fixture where k='quote'),(select id from withdrawal_fixture where k='staff'));
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from withdrawal_fixture where k='creator'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 if public.pulse_wallet()->>'p_coins'<>'200'then raise exception 'FAIL duplicated refund or reservation';end if;
 if public.pulse_withdraw_info()->>'available_p_coins'<>'200'then raise exception 'FAIL earnings not restored';end if;
end $$;
reset role;
rollback;
