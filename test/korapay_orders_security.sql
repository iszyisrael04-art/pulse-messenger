begin;
create temporary table kora_fixture(k text primary key,id uuid default gen_random_uuid());
insert into kora_fixture(k)values('buyer'),('other'),('order'),('squad_order');
grant select on kora_fixture to authenticated,service_role;
insert into auth.users(id,aud,role,email,email_confirmed_at)select id,'authenticated','authenticated',id||'@example.invalid',now()from kora_fixture where k in('buyer','other');
do $$begin
 if has_function_privilege('authenticated','public.pulse_kora_order_service(uuid,text,uuid,text,numeric,bigint,text,text)','execute')
 or has_function_privilege('anon','public.pulse_kora_order_service(uuid,text,uuid,text,numeric,bigint,text,text)','execute')then raise exception 'FAIL clients can call verifier';end if;
end $$;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select public.pulse_kora_order_service((select id from kora_fixture where k='order'),'quote',(select id from kora_fixture where k='buyer'),'coins_100',1500);
-- Rate changes cannot alter an existing order.
do $$declare o jsonb;begin
 o=public.pulse_kora_order_service((select id from kora_fixture where k='order'),'quote',(select id from kora_fixture where k='buyer'),'coins_100',2000);
 if (o->>'charge_minor')::bigint<>150000 then raise exception 'FAIL mutable exchange quote';end if;
 begin
  perform public.pulse_kora_order_service((select id from kora_fixture where k='order'),'quote',(select id from kora_fixture where k='other'),'coins_100',1500);
  raise exception 'FAIL owner mismatch';
 exception when others then if sqlerrm='FAIL owner mismatch'then raise;end if;end;
 begin
  perform public.pulse_kora_order_service((select id from kora_fixture where k='order'),'fulfill',p_amount=>1,p_currency=>'NGN');
  raise exception 'FAIL underpayment';
 exception when others then if sqlerrm='FAIL underpayment'then raise;end if;end;
 begin
  perform public.pulse_kora_order_service((select id from kora_fixture where k='order'),'fulfill',p_amount=>150000,p_currency=>'USD');
  raise exception 'FAIL wrong currency';
 exception when others then if sqlerrm='FAIL wrong currency'then raise;end if;end;
end $$;
select public.pulse_kora_order_service((select id from kora_fixture where k='order'),'fulfill',p_amount=>150000,p_currency=>'NGN');
select public.pulse_kora_order_service((select id from kora_fixture where k='order'),'fulfill',p_amount=>150000,p_currency=>'NGN');
reset role;
do $$begin
 if (select coins from pulse_private.wallets where user_id=(select id from kora_fixture where k='buyer'))<>100 then raise exception 'FAIL duplicate or missing coins';end if;
 if (select count(*)from pulse_private.coin_receipts where provider='korapay-live'and receipt=(select id::text from kora_fixture where k='order'))<>1 then raise exception 'FAIL duplicate receipt';end if;
end $$;
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',(select id from kora_fixture where k='buyer'))::text,true);
set local role authenticated;
select public.pulse_payment_order((select id from kora_fixture where k='squad_order'),'coins_100');
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
do $$begin
 begin
  perform public.pulse_kora_order_service((select id from kora_fixture where k='squad_order'),'quote',(select id from kora_fixture where k='buyer'),'coins_100',1500);
  raise exception 'FAIL cross-provider reference reuse';
 exception when others then if sqlerrm='FAIL cross-provider reference reuse'then raise;end if;end;
end $$;
reset role;
rollback;
