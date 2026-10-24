begin;
-- Decimal earnings are exact numeric values; normal coins remain whole integers.
alter table pulse_private.wallets alter column p_coins type numeric(20,2);
alter table pulse_private.gift_catalog alter column p_coins type numeric(20,2);
alter table pulse_private.gift_events alter column p_coins type numeric(20,2);
-- Preserve historical gift events and wallet balances. Only future gifts use this catalog.
update pulse_private.gift_catalog set coins=10,p_coins=0.5 where sku='rose';
update pulse_private.cashout_policy set usd_cents_per_pcoin=30,enabled=false;
create or replace function pulse_private.wallet() returns jsonb language plpgsql security definer set search_path='' as $$
declare w pulse_private.wallets;
begin
 perform pulse_private.require_active();
 select * into w from pulse_private.wallets where user_id=auth.uid();
 return jsonb_build_object('coins',coalesce(w.coins,0),'p_coins',coalesce(w.p_coins,0),'cashout_enabled',false,'pcoin_usd_cents',30,'cash_value_usd_cents',coalesce(w.p_coins,0)*30,
 'cashout_message','P-coins are creator earnings. 100 P-coins are valued at $30. Bank withdrawals are unavailable until the payout service and verification are configured.',
 'gifts',(select jsonb_agg(to_jsonb(g) order by coins) from pulse_private.gift_catalog g where enabled),
 'coin_packs',jsonb_build_array(jsonb_build_object('sku','coins_100','coins',100,'usd_cents',100),jsonb_build_object('sku','coins_200','coins',200,'usd_cents',200),jsonb_build_object('sku','coins_500','coins',500,'usd_cents',500),jsonb_build_object('sku','coins_1000','coins',1000,'usd_cents',1000)),
 'transactions',coalesce((select jsonb_agg(x) from(select id,sku,quantity,coins,p_coins,created_at,sender_id=auth.uid() outgoing from pulse_private.gift_events where sender_id=auth.uid() or recipient_id=auth.uid() order by created_at desc limit 50)x),'[]'));
end $$;
create or replace function pulse_private.credit_coins(p_user uuid,p_provider text,p_receipt text,p_coins integer,p_usd_cents integer) returns boolean language plpgsql security definer set search_path='' as $$
declare prior pulse_private.coin_receipts;
begin
 if coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role',current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception 'Verified provider required';end if;
 if p_provider<>'squad-live' or length(p_receipt) not between 1 and 300 or p_user is null then raise exception 'Invalid coin purchase';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_provider||':'||p_receipt,88));
 select * into prior from pulse_private.coin_receipts where provider=p_provider and receipt=p_receipt;
 if found then
 if prior.user_id<>p_user or prior.coins<>p_coins or prior.usd_cents<>p_usd_cents then raise exception 'Receipt mismatch';end if;return false;end if;
 -- A pre-existing order retains its immutable quote across catalog changes.
 if not ((p_coins in(100,200,500,1000) and p_usd_cents=p_coins)
   or exists(select 1 from pulse_private.payment_orders where id::text=p_receipt and user_id=p_user and coins=p_coins and usd_cents=p_usd_cents)) then raise exception 'Invalid coin purchase';end if;
 insert into pulse_private.coin_receipts values(p_provider,p_receipt,p_user,p_coins,p_usd_cents,now());
 insert into pulse_private.wallets(user_id,coins)values(p_user,p_coins) on conflict(user_id)do update set coins=pulse_private.wallets.coins+excluded.coins;
 return true;
end $$;
create or replace function pulse_private.live_gifts(p_action text,p_session uuid,p_recipient uuid,p_sku text,p_quantity integer,p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.pulse_live_sessions; g pulse_private.gift_catalog; prior pulse_private.gift_events; spend bigint; earned numeric; u uuid;
begin
 perform pulse_private.require_active();
 select * into s from public.pulse_live_sessions where id=p_session for update;
 if s.id is null or pulse_private.social_blocked(s.host_id) then raise exception 'LIVE unavailable';end if;
 if p_action='info' then
 return jsonb_build_object('gifts',(select jsonb_agg(to_jsonb(c)order by coins)from pulse_private.gift_catalog c where enabled),'recent',coalesce((select jsonb_agg(x)from(select e.id,e.recipient_id,e.sku,e.quantity,e.created_at,p.display_name from pulse_private.gift_events e join public.pulse_profiles p on p.id=e.sender_id where e.session_id=p_session and not pulse_private.social_blocked(e.sender_id) order by e.created_at desc limit 12)x),'[]'));
 end if;
 if p_action<>'send' then raise exception 'Invalid gift action';end if;
 if p_id is null or p_quantity is null or p_quantity not between 1 and 100 then raise exception 'Invalid gift quantity';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,89));
 select * into prior from pulse_private.gift_events where id=p_id;
 if found then
 if prior.sender_id<>auth.uid() or prior.recipient_id<>p_recipient or prior.session_id<>p_session or prior.sku<>p_sku or prior.quantity<>p_quantity then raise exception 'Gift retry mismatch';end if;
 return jsonb_build_object('sent',true,'id',prior.id);end if;
 if s.status<>'live' or s.expires_at<=now() then raise exception 'LIVE ended';end if;
 if p_recipient is null or p_recipient=auth.uid() or pulse_private.social_blocked(p_recipient) then raise exception 'Cannot send this gift';end if;
 if p_recipient<>s.host_id and not exists(select 1 from pulse_private.live_guests where session_id=p_session and user_id=p_recipient and state='approved') then raise exception 'Choose a host or approved guest';end if;
 if exists(select 1 from pulse_private.account_limits where user_id=p_recipient and(state='banned' or state='suspended' and until_at>now())) then raise exception 'Recipient unavailable';end if;
 select * into g from pulse_private.gift_catalog where sku=p_sku and enabled;
 if g.sku is null then raise exception 'Gift unavailable';end if;
 spend=g.coins::bigint*p_quantity;earned=g.p_coins*p_quantity;
 perform pulse_private.social_rate('send_gift',30,60);
 -- Stable wallet lock order prevents reciprocal gift deadlocks.
 for u in select unnest(array[auth.uid(),p_recipient]) order by 1 loop
 insert into pulse_private.wallets(user_id)values(u)on conflict do nothing;
 perform 1 from pulse_private.wallets where user_id=u for update;
 end loop;
 update pulse_private.wallets set coins=coins-spend where user_id=auth.uid() and coins>=spend;
 if not found then raise exception 'Not enough normal coins';end if;
 update pulse_private.wallets set p_coins=p_coins+earned where user_id=p_recipient;
 insert into pulse_private.gift_events values(p_id,auth.uid(),p_recipient,p_session,p_sku,p_quantity,spend,earned,clock_timestamp());
 return jsonb_build_object('sent',true,'id',p_id,'coins_spent',spend,'p_coins_earned',earned);
end $$;
create or replace function pulse_private.payment_order(p_id uuid,p_sku text)returns jsonb language plpgsql security definer set search_path=''as $$
declare o pulse_private.payment_orders; amount integer; count integer:=0;
begin
 perform pulse_private.require_active();
 if p_id is null or p_sku is null then raise exception 'Invalid order';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,91));
 select * into o from pulse_private.payment_orders where id=p_id;
 if found then
 if o.user_id<>auth.uid()or o.sku<>p_sku then raise exception 'Order mismatch';end if;return to_jsonb(o);end if;
 perform pulse_private.social_rate('payment_order',3,60);
 if p_sku in('coins_100','coins_200','coins_500','coins_1000')then count=substring(p_sku from 7)::integer;amount=count;
 else select usd_cents into amount from pulse_private.creator_products where sku=p_sku;end if;
 if amount is null then raise exception 'Unknown product';end if;
 insert into pulse_private.payment_orders(id,user_id,sku,usd_cents,coins)values(p_id,auth.uid(),p_sku,amount,count)returning * into o;
 return to_jsonb(o);
end $$;
commit;
