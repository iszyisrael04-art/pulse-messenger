begin;
create table pulse_private.payment_orders(id uuid primary key,user_id uuid not null references public.pulse_profiles on delete cascade,sku text not null,usd_cents integer not null check(usd_cents>0),coins integer not null default 0 check(coins>=0),currency text not null default 'USD' check(currency='USD'),state text not null default 'pending' check(state in('pending','paid')),created_at timestamptz not null default now(),paid_at timestamptz);
create index payment_orders_user on pulse_private.payment_orders(user_id,created_at desc);
alter table pulse_private.payment_orders enable row level security;
revoke all on pulse_private.payment_orders from public,anon,authenticated;
create policy deny_clients on pulse_private.payment_orders for all to anon,authenticated using(false)with check(false);
create function pulse_private.payment_order(p_id uuid,p_sku text)returns jsonb language plpgsql security definer set search_path=''as $$
declare o pulse_private.payment_orders; amount integer; count integer:=0;
begin
 perform pulse_private.require_active();
 if p_id is null or p_sku is null then raise exception 'Invalid order';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,91));
 select * into o from pulse_private.payment_orders where id=p_id;
 if found then
 if o.user_id<>auth.uid()or o.sku<>p_sku then raise exception 'Order mismatch';end if;return to_jsonb(o);end if;
 perform pulse_private.social_rate('payment_order',3,60);
 if p_sku in('coins_50','coins_100','coins_500','coins_1000')then count=substring(p_sku from 7)::integer;amount=count*2;
 else select usd_cents into amount from pulse_private.creator_products where sku=p_sku;end if;
 if amount is null then raise exception 'Unknown product';end if;
 insert into pulse_private.payment_orders(id,user_id,sku,usd_cents,coins)values(p_id,auth.uid(),p_sku,amount,count)returning * into o;
 return to_jsonb(o);
end $$;
create function pulse_private.payment_order_service(p_id uuid,p_action text,p_amount integer,p_currency text)returns jsonb language plpgsql security definer set search_path=''as $$
declare o pulse_private.payment_orders;
begin
 if coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role',current_setting('request.jwt.claim.role',true),'')<>'service_role'then raise exception 'Verifier required';end if;
 select * into o from pulse_private.payment_orders where id=p_id for update;
 if not found then raise exception 'Unknown order';end if;
 if p_action='get'then return to_jsonb(o);end if;
 if p_action<>'fulfill'or p_amount is distinct from o.usd_cents or p_currency is distinct from o.currency then raise exception 'Payment mismatch';end if;
 if o.state='paid'then return to_jsonb(o);end if;
 if o.coins>0 then perform pulse_private.credit_coins(o.user_id,'squad-live',o.id::text,o.coins,o.usd_cents);
 else perform pulse_private.confirm_creator_purchase(o.user_id,o.sku,'squad-live',o.id::text,o.usd_cents);end if;
 update pulse_private.payment_orders set state='paid',paid_at=now()where id=p_id returning * into o;
 return to_jsonb(o);
end $$;
create function public.pulse_payment_order(p_id uuid,p_sku text)returns jsonb language sql security invoker set search_path=''as $$select pulse_private.payment_order(p_id,p_sku)$$;
create function public.pulse_payment_order_service(p_id uuid,p_action text,p_amount integer default null,p_currency text default null)returns jsonb language sql security invoker set search_path=''as $$select pulse_private.payment_order_service(p_id,p_action,p_amount,p_currency)$$;
revoke all on function pulse_private.payment_order(uuid,text),public.pulse_payment_order(uuid,text),pulse_private.payment_order_service(uuid,text,integer,text),public.pulse_payment_order_service(uuid,text,integer,text)from public,anon,authenticated;
grant execute on function pulse_private.payment_order(uuid,text),public.pulse_payment_order(uuid,text)to authenticated;
grant execute on function pulse_private.payment_order_service(uuid,text,integer,text),public.pulse_payment_order_service(uuid,text,integer,text)to service_role;
commit;
