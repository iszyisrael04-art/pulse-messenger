begin;
create table pulse_private.withdrawals(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.pulse_profiles on delete cascade,p_coins integer not null check(p_coins between 100 and 1000000),usd_cents integer not null check(usd_cents=p_coins*30),rate_kobo_per_usd bigint not null check(rate_kobo_per_usd>0),gross_kobo bigint not null check(gross_kobo>0),fee_kobo bigint not null check(fee_kobo>=0 and fee_kobo<gross_kobo),net_kobo bigint not null check(net_kobo=gross_kobo-fee_kobo),bank_code text not null check(bank_code~'^[0-9]{6}$'),account_number text not null check(account_number~'^[0-9]{10}$'),account_name text not null,provider_reference text not null unique,state text not null default 'quoted'check(state in('quoted','review','processing','paid','failed')),refunded boolean not null default false,created_at timestamptz not null default now(),quote_expires_at timestamptz not null default now()+interval '10 minutes',processed_at timestamptz,rate_as_of timestamptz not null);
create index withdrawals_user on pulse_private.withdrawals(user_id,created_at desc);
create index withdrawals_review on pulse_private.withdrawals(state,created_at);
alter table pulse_private.withdrawals enable row level security;
revoke all on pulse_private.withdrawals from public,anon,authenticated;
create policy deny_clients on pulse_private.withdrawals for all to anon,authenticated using(false)with check(false);
create function pulse_private.withdraw_available(p_user uuid)returns numeric language sql volatile security definer set search_path=''as $$
 select greatest(0,least(coalesce((select p_coins from pulse_private.wallets where user_id=p_user),0),coalesce((select sum(p_coins)from pulse_private.gift_events where recipient_id=p_user and created_at<=now()-interval '7 days'),0)-coalesce((select sum(p_coins)from pulse_private.withdrawals where user_id=p_user and state in('review','processing','paid')and not refunded),0)))
$$;
revoke all on function pulse_private.withdraw_available(uuid)from public,anon,authenticated;
create function pulse_private.withdraw_info(p_admin boolean)returns jsonb language plpgsql security definer set search_path=''as $$begin
 perform pulse_private.require_active();
 if p_admin and not pulse_private.is_admin()then raise exception 'Staff required';end if;
 return jsonb_build_object('available_p_coins',pulse_private.withdraw_available(auth.uid()),'minimum',100,'hold_days',7,'usd_cents_per_pcoin',30,
 'requests',coalesce((select jsonb_agg(x)from(select id,user_id,p_coins,net_kobo,fee_kobo,account_name,'••••••'||right(account_number,4) account,state,created_at,processed_at from pulse_private.withdrawals where(p_admin and state in('review','processing')or user_id=auth.uid())and state<>'quoted'order by created_at desc limit 100)x),'[]'));
end $$;
create function pulse_private.withdraw_service(p_action text,p_id uuid,p_user uuid,p_data jsonb)returns jsonb language plpgsql security definer set search_path=''as $$
declare w pulse_private.withdrawals; rid uuid;available numeric; amount integer;gross bigint;
begin
 if coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role',current_setting('request.jwt.claim.role',true),'')<>'service_role'then raise exception 'Payout service required';end if;
 if p_action='quote'then
 amount=(p_data->>'p_coins')::int;
 if amount is null or amount not between 100 and 1000000 or p_user is null then raise exception 'Invalid amount';end if;
 if pulse_private.withdraw_available(p_user)<amount then raise exception 'Not enough available P-coins. Gifts become available after 7 days.';end if;
 if (p_data->>'rate_as_of')::timestamptz<now()-interval '36 hours'or(p_data->>'rate_as_of')::timestamptz>now()+interval '5 minutes'then raise exception 'Stale exchange quote';end if;
 gross=floor(amount::numeric*30*(p_data->>'rate_kobo_per_usd')::bigint/100)::bigint;
 insert into pulse_private.withdrawals(user_id,p_coins,usd_cents,rate_kobo_per_usd,gross_kobo,fee_kobo,net_kobo,bank_code,account_number,account_name,provider_reference,rate_as_of)
 values(p_user,amount,amount*30,(p_data->>'rate_kobo_per_usd')::bigint,gross,(p_data->>'fee_kobo')::bigint,gross-(p_data->>'fee_kobo')::bigint,p_data->>'bank_code',p_data->>'account_number',p_data->>'account_name',p_data->>'reference',(p_data->>'rate_as_of')::timestamptz)returning * into w;
 return to_jsonb(w);
 end if;
 select * into w from pulse_private.withdrawals where id=p_id for update;
 if not found then raise exception 'Withdrawal unavailable';end if;
 if p_action in('get_admin','claim','failed','reversed')and not exists(select 1 from pulse_private.admins where user_id=p_user)then raise exception 'Staff required';end if;
 if p_action='paid'and w.user_id is distinct from p_user and not exists(select 1 from pulse_private.admins where user_id=p_user)then raise exception 'Own withdrawal or staff required';end if;
 if p_action='get_admin'then return to_jsonb(w);end if;
 if p_action in('get','confirm')and w.user_id is distinct from p_user then raise exception 'Own withdrawal only';end if;
 if p_action='get'then return to_jsonb(w);end if;
 if p_action='confirm'then
 if w.state<>'quoted'then return to_jsonb(w);end if;
 if w.quote_expires_at<=now()then raise exception 'Quote expired. Request a new quote.';end if;
 perform 1 from pulse_private.wallets where user_id=w.user_id for update;
 available=pulse_private.withdraw_available(w.user_id);
 if available<w.p_coins then raise exception 'Not enough available P-coins';end if;
 update pulse_private.wallets set p_coins=p_coins-w.p_coins where user_id=w.user_id and p_coins>=w.p_coins;
 if not found then raise exception 'Not enough available P-coins';end if;
 update pulse_private.withdrawals set state='review'where id=w.id returning * into w;
 elsif p_action='claim'then
 if w.state<>'review'then return to_jsonb(w)||jsonb_build_object('claimed',false);end if;
 if exists(select 1 from pulse_private.account_limits where user_id=w.user_id and(state='banned'or state='suspended'and until_at>now()))then raise exception 'Recipient account is restricted';end if;
 update pulse_private.withdrawals set state='processing'where id=w.id returning * into w;
 insert into pulse_private.control_audit(staff_id,action,detail)values(p_user,'payout_approved',jsonb_build_object('withdrawal',w.id,'net_kobo',w.net_kobo));
 return to_jsonb(w)||jsonb_build_object('claimed',true);
 elsif p_action='paid'then
 if w.state='processing'and not w.refunded then update pulse_private.withdrawals set state='paid',processed_at=now()where id=w.id returning * into w;end if;
 elsif p_action in('failed','reversed')then
 if w.state in('review','processing','paid')and not w.refunded then
 update pulse_private.wallets set p_coins=p_coins+w.p_coins where user_id=w.user_id;
 update pulse_private.withdrawals set state='failed',refunded=true,processed_at=now()where id=w.id returning * into w;
 end if;
 else raise exception 'Invalid payout action';end if;
 return to_jsonb(w);
end $$;
create function public.pulse_withdraw_info(p_admin boolean default false)returns jsonb language sql security invoker set search_path=''as $$select pulse_private.withdraw_info(p_admin)$$;
create function public.pulse_withdraw_service(p_action text,p_id uuid default null,p_user uuid default null,p_data jsonb default '{}')returns jsonb language sql security invoker set search_path=''as $$select pulse_private.withdraw_service(p_action,p_id,p_user,p_data)$$;
revoke all on function pulse_private.withdraw_info(boolean),public.pulse_withdraw_info(boolean),pulse_private.withdraw_service(text,uuid,uuid,jsonb),public.pulse_withdraw_service(text,uuid,uuid,jsonb)from public,anon,authenticated;
grant execute on function pulse_private.withdraw_info(boolean),public.pulse_withdraw_info(boolean)to authenticated;
grant execute on function pulse_private.withdraw_service(text,uuid,uuid,jsonb),public.pulse_withdraw_service(text,uuid,uuid,jsonb)to service_role;
create function pulse_private.protect_pending_withdrawals()returns trigger language plpgsql security definer set search_path=''as $$begin
 if exists(select 1 from pulse_private.withdrawals where user_id=old.id and state in('review','processing'))then raise exception 'Settle pending withdrawals before deleting this account';end if;return old;end $$;
revoke all on function pulse_private.protect_pending_withdrawals()from public,anon,authenticated;
create trigger pulse_protect_pending_withdrawals before delete on public.pulse_profiles for each row execute function pulse_private.protect_pending_withdrawals();
commit;
