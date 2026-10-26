begin;
create table pulse_private.korapay_orders (
 id uuid primary key, user_id uuid not null references public.pulse_profiles on delete cascade,
 sku text not null, usd_cents integer not null check(usd_cents>0), coins integer not null default 0 check(coins>=0),
 currency text not null default 'NGN' check(currency='NGN'),
 charge_minor bigint not null check(charge_minor between 1 and 9000000000000),
 ngn_per_usd numeric(18,6) not null check(ngn_per_usd>0 and ngn_per_usd<=100000),
 state text not null default 'pending' check(state in('pending','paid')),
 checkout_url text,created_at timestamptz not null default now(),paid_at timestamptz,
 check(checkout_url is null or checkout_url ~ '^https://checkout[.]korapay[.]com/')
);
create index korapay_orders_user on pulse_private.korapay_orders(user_id,created_at desc);
alter table pulse_private.korapay_orders enable row level security;
create policy korapay_orders_no_clients on pulse_private.korapay_orders to anon,authenticated using(false) with check(false);
revoke all on pulse_private.korapay_orders from public,anon,authenticated;

CREATE OR REPLACE FUNCTION pulse_private.credit_coins(p_user uuid, p_provider text, p_receipt text, p_coins integer, p_usd_cents integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare prior pulse_private.coin_receipts;
begin
 if coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role',current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception 'Verified provider required';end if;
 if p_provider not in ('squad-live','korapay-live') or length(p_receipt) not between 1 and 300 or p_user is null then raise exception 'Invalid coin purchase';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_provider||':'||p_receipt,88));
 select * into prior from pulse_private.coin_receipts where provider=p_provider and receipt=p_receipt;
 if found then
 if prior.user_id<>p_user or prior.coins<>p_coins or prior.usd_cents<>p_usd_cents then raise exception 'Receipt mismatch';end if;return false;end if;
 if p_provider='korapay-live' then
  if not exists(select 1 from pulse_private.korapay_orders where id::text=p_receipt and user_id=p_user and coins=p_coins and usd_cents=p_usd_cents) then raise exception 'Korapay quote mismatch';end if;
 else
 -- A pre-existing order retains its immutable quote across catalog changes.
 if not ((p_coins in(100,200,500,1000) and p_usd_cents=p_coins)
   or exists(select 1 from pulse_private.payment_orders where id::text=p_receipt and user_id=p_user and coins=p_coins and usd_cents=p_usd_cents)) then raise exception 'Invalid coin purchase';end if;

 end if;
 insert into pulse_private.coin_receipts values(p_provider,p_receipt,p_user,p_coins,p_usd_cents,now());
 insert into pulse_private.wallets(user_id,coins)values(p_user,p_coins) on conflict(user_id)do update set coins=pulse_private.wallets.coins+excluded.coins;
 return true;
end $function$
;

create function pulse_private.kora_order_service(p_id uuid,p_action text,p_user uuid,p_sku text,p_rate numeric,p_amount bigint,p_currency text,p_url text)
 returns jsonb language plpgsql security definer set search_path='' as $$
declare o pulse_private.korapay_orders; cents integer; count integer:=0; charge bigint;
begin
 if coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role',current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception 'Receipt verifier required';end if;
 if p_id is null then raise exception 'Order reference required';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,192));
 select * into o from pulse_private.korapay_orders where id=p_id for update;
 if p_action='quote' then
  if o.id is not null then
   if o.user_id is distinct from p_user or o.sku is distinct from p_sku then raise exception 'Order mismatch';end if;
   return to_jsonb(o);
  end if;
  if exists(select 1 from pulse_private.payment_orders where id=p_id) then raise exception 'Reference already belongs to another provider';end if;
  if p_user is null or not exists(select 1 from public.pulse_profiles where id=p_user) or p_rate is null or p_rate<=0 or p_rate>100000 then raise exception 'Valid customer and merchant price required';end if;
  if p_sku like 'reward_%' then raise exception 'Promotional rewards are not purchasable';end if;
  if p_sku in('coins_100','coins_200','coins_500','coins_1000') then count=substring(p_sku from 7)::integer;cents=count;
  else select usd_cents into cents from pulse_private.creator_products where sku=p_sku;end if;
  if cents is null then raise exception 'Unknown product';end if;
  charge=ceil(cents*p_rate);
  insert into pulse_private.korapay_orders(id,user_id,sku,usd_cents,coins,charge_minor,ngn_per_usd)
   values(p_id,p_user,p_sku,cents,count,charge,p_rate) returning * into o;
  return to_jsonb(o);
 end if;
 if o.id is null then raise exception 'Order unavailable';end if;
 if p_user is not null and o.user_id<>p_user then raise exception 'Order owner mismatch';end if;
 if p_action='get' then return to_jsonb(o);end if;
 if p_action='checkout' then
  if p_url is null or p_url !~ '^https://checkout[.]korapay[.]com/' then raise exception 'Unsupported checkout address';end if;
  if o.checkout_url is not null and o.checkout_url<>p_url then raise exception 'Checkout already initialized';end if;
  update pulse_private.korapay_orders set checkout_url=p_url where id=p_id returning * into o;return to_jsonb(o);
 end if;
 if p_action<>'fulfill' or p_amount is distinct from o.charge_minor or p_currency is distinct from o.currency then raise exception 'Payment mismatch';end if;
 if o.state='paid' then return to_jsonb(o);end if;
 if o.coins>0 then perform pulse_private.credit_coins(o.user_id,'korapay-live',o.id::text,o.coins,o.usd_cents);
 else perform pulse_private.confirm_creator_purchase(o.user_id,o.sku,'korapay-live',o.id::text,o.usd_cents);end if;
 update pulse_private.korapay_orders set state='paid',paid_at=now() where id=p_id returning * into o;
 return to_jsonb(o);
end $$;
create function public.pulse_kora_order_service(p_id uuid,p_action text,p_user uuid default null,p_sku text default null,p_rate numeric default null,p_amount bigint default null,p_currency text default null,p_url text default null)
 returns jsonb language sql security invoker set search_path='' as $$select pulse_private.kora_order_service(p_id,p_action,p_user,p_sku,p_rate,p_amount,p_currency,p_url)$$;
revoke all on function pulse_private.kora_order_service(uuid,text,uuid,text,numeric,bigint,text,text),public.pulse_kora_order_service(uuid,text,uuid,text,numeric,bigint,text,text) from public,anon,authenticated;
grant execute on function pulse_private.kora_order_service(uuid,text,uuid,text,numeric,bigint,text,text),public.pulse_kora_order_service(uuid,text,uuid,text,numeric,bigint,text,text) to service_role;
commit;
