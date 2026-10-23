begin;
create temporary table order_fixture(k text primary key,id uuid default gen_random_uuid());
insert into order_fixture(k)values('buyer'),('other'),('coin_order'),('motion_order');
grant select on order_fixture to authenticated,service_role;
insert into auth.users(id,aud,role,email,email_confirmed_at)select id,'authenticated','authenticated','order-'||id||'@example.invalid',now()from order_fixture where k in('buyer','other');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from order_fixture where k='buyer'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_payment_order((select id from order_fixture where k='coin_order'),'coins_50');
select public.pulse_payment_order((select id from order_fixture where k='motion_order'),'motion');
do $$begin
 begin perform public.pulse_payment_order_service((select id from order_fixture where k='coin_order'),'fulfill',100,'USD');raise exception 'FAIL client fulfillment';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from order_fixture where k='other'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 begin perform public.pulse_payment_order((select id from order_fixture where k='coin_order'),'coins_50');raise exception 'FAIL stolen order';exception when others then if sqlerrm='FAIL stolen order'then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
do $$begin
 begin perform public.pulse_payment_order_service((select id from order_fixture where k='coin_order'),'fulfill',1,'USD');raise exception 'FAIL wrong amount';exception when others then if sqlerrm='FAIL wrong amount'then raise;end if;end;
 begin perform public.pulse_payment_order_service((select id from order_fixture where k='coin_order'),'fulfill',100,'NGN');raise exception 'FAIL wrong currency';exception when others then if sqlerrm='FAIL wrong currency'then raise;end if;end;
end $$;
select public.pulse_payment_order_service((select id from order_fixture where k='coin_order'),'fulfill',100,'USD');
select public.pulse_payment_order_service((select id from order_fixture where k='coin_order'),'fulfill',100,'USD');
select public.pulse_payment_order_service((select id from order_fixture where k='motion_order'),'fulfill',100,'USD');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from order_fixture where k='buyer'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 if public.pulse_wallet()->>'coins'<>'50'then raise exception 'FAIL duplicate credit';end if;
 if not (public.pulse_creator_access()->>'motion')::boolean then raise exception 'FAIL profile unlock';end if;
end $$;
reset role;
rollback;
