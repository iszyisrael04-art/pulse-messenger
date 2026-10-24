begin;
-- Revoked native Auth sessions must not retain access to protected RPCs.
create function pulse_private.session_is_current()returns boolean language plpgsql stable security definer set search_path=''as $$
declare sid text;begin
 sid=nullif(coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb->>'session_id','');
 -- Compatibility for older, platform-signed tokens without session_id. Clients
 -- cannot remove this signed claim from modern tokens without invalidating JWTs.
 if sid is null then return true;end if;
 if sid!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'then return false;end if;
 return exists(select 1 from auth.sessions where id=sid::uuid and user_id=auth.uid()and(not_after is null or not_after>now()));
end $$;
revoke all on function pulse_private.session_is_current()from public,anon,authenticated;
create or replace function pulse_private.account_active()returns boolean language sql stable security definer set search_path=''as $$
 select auth.uid()is not null and exists(select 1 from auth.users where id=auth.uid())and pulse_private.session_is_current()and not exists(select 1 from pulse_private.account_limits where user_id=auth.uid()and(state='banned'or state='suspended'and until_at>now()))
$$;
create table pulse_private.test_wallets(user_id uuid primary key references public.pulse_profiles on delete cascade,coins bigint not null default 0 check(coins>=0));
create table pulse_private.test_coin_grants(reference text primary key,user_id uuid not null references public.pulse_profiles on delete cascade,coins bigint not null check(coins>0),reason text not null,created_at timestamptz not null default now());
create table pulse_private.test_gift_events(id uuid primary key,sender_id uuid not null references public.pulse_profiles on delete cascade,recipient_id uuid not null references public.pulse_profiles on delete cascade,session_id uuid not null references public.pulse_live_sessions on delete cascade,sku text not null references pulse_private.gift_catalog,quantity integer not null check(quantity between 1 and 100),coins bigint not null check(coins>0),created_at timestamptz not null default clock_timestamp());
create index test_grants_user on pulse_private.test_coin_grants(user_id);
create index test_gifts_session on pulse_private.test_gift_events(session_id,created_at,id);
create index test_gifts_sender on pulse_private.test_gift_events(sender_id);
create index test_gifts_recipient on pulse_private.test_gift_events(recipient_id);
do $$declare t text;begin
 foreach t in array array['test_wallets','test_coin_grants','test_gift_events']loop
 execute format('alter table pulse_private.%I enable row level security',t);
 execute format('revoke all on pulse_private.%I from public,anon,authenticated',t);
 execute format('create policy deny_clients on pulse_private.%I for all to anon,authenticated using(false)with check(false)',t);
 end loop;
end $$;
create function pulse_private.test_wallet()returns jsonb language plpgsql security definer set search_path=''as $$begin
 perform pulse_private.require_active();
 return jsonb_build_object('coins',coalesce((select coins from pulse_private.test_wallets where user_id=auth.uid()),0),'test_only',true,'withdrawable',false,'affects_rank',false);
end $$;
create function pulse_private.test_live_gift(p_session uuid,p_recipient uuid,p_sku text,p_quantity integer,p_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare s public.pulse_live_sessions;prior pulse_private.test_gift_events;price integer;spend bigint;
begin
 perform pulse_private.require_active();
 select * into s from public.pulse_live_sessions where id=p_session for update;
 if s.id is null or pulse_private.social_blocked(s.host_id)then raise exception 'LIVE unavailable';end if;
 if p_id is null or p_quantity is null or p_quantity not between 1 and 100 then raise exception 'Choose 1–100 gifts';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,98));
 select * into prior from pulse_private.test_gift_events where id=p_id;
 if found then
 if prior.sender_id<>auth.uid()or prior.recipient_id<>p_recipient or prior.session_id<>p_session or prior.sku<>p_sku or prior.quantity<>p_quantity then raise exception 'Test gift retry mismatch';end if;
 return jsonb_build_object('sent',true,'test',true,'id',prior.id);end if;
 if s.status<>'live'or s.expires_at<=now()then raise exception 'LIVE ended';end if;
 if p_recipient is null or pulse_private.social_blocked(p_recipient)then raise exception 'Recipient unavailable';end if;
 if p_recipient<>s.host_id and not exists(select 1 from pulse_private.live_guests where session_id=p_session and user_id=p_recipient and state='approved')then raise exception 'Choose the host or approved guest';end if;
 if exists(select 1 from pulse_private.account_limits where user_id=p_recipient and(state='banned'or state='suspended'and until_at>now()))then raise exception 'Recipient unavailable';end if;
 select coins into price from pulse_private.gift_catalog where sku=p_sku and enabled;
 if price is null then raise exception 'Gift unavailable';end if;
 spend=price::bigint*p_quantity;
 perform pulse_private.social_rate('test_gift',30,60);
 update pulse_private.test_wallets set coins=coins-spend where user_id=auth.uid()and coins>=spend;
 if not found then raise exception 'Not enough test coins';end if;
 insert into pulse_private.test_gift_events values(p_id,auth.uid(),p_recipient,p_session,p_sku,p_quantity,spend,clock_timestamp());
 return jsonb_build_object('sent',true,'test',true,'id',p_id,'test_coins_spent',spend,'p_coins_earned',0);
end $$;
create function public.pulse_test_wallet()returns jsonb language sql security invoker set search_path=''as $$select pulse_private.test_wallet()$$;
create function public.pulse_test_live_gift(p_session uuid,p_recipient uuid,p_sku text,p_quantity integer,p_id uuid)returns jsonb language sql security invoker set search_path=''as $$select pulse_private.test_live_gift(p_session,p_recipient,p_sku,p_quantity,p_id)$$;
revoke all on function pulse_private.test_wallet(),pulse_private.test_live_gift(uuid,uuid,text,integer,uuid),public.pulse_test_wallet(),public.pulse_test_live_gift(uuid,uuid,text,integer,uuid)from public,anon,authenticated;
grant execute on function pulse_private.test_wallet(),pulse_private.test_live_gift(uuid,uuid,text,integer,uuid),public.pulse_test_wallet(),public.pulse_test_live_gift(uuid,uuid,text,integer,uuid)to authenticated;
create or replace function pulse_private.gift_feed(p_session uuid,p_after timestamptz,p_cursor uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare s public.pulse_live_sessions; rows jsonb;last_time timestamptz;last_id uuid;
begin
 perform pulse_private.require_active();
 select * into s from public.pulse_live_sessions where id=p_session;
 if s.id is null or pulse_private.social_blocked(s.host_id)then raise exception 'LIVE unavailable';end if;
 if (p_after is null)<>(p_cursor is null)then raise exception 'Invalid gift cursor';end if;
 if p_after is null then
  select created_at,id into last_time,last_id from (select id,sender_id,recipient_id,session_id,sku,quantity,created_at,false is_test from pulse_private.gift_events union all select id,sender_id,recipient_id,session_id,sku,quantity,created_at,true is_test from pulse_private.test_gift_events) combined where session_id=p_session order by created_at desc,id desc limit 1;
  return jsonb_build_object('items','[]'::jsonb,'after',coalesce(last_time,'1970-01-01'::timestamptz),'cursor',coalesce(last_id,'00000000-0000-0000-0000-000000000000'::uuid));
 end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by created_at,id),'[]')into rows from(
  select e.id,e.created_at,e.sku,e.quantity,e.sender_id,e.recipient_id,e.is_test,p.display_name,p.avatar_path,case when e.is_test then 'TEST · '||g.title else g.title end title,
   pulse_private.gifter_status(e.sender_id,null,null)gifter
  from (select id,sender_id,recipient_id,session_id,sku,quantity,created_at,false is_test from pulse_private.gift_events union all select id,sender_id,recipient_id,session_id,sku,quantity,created_at,true is_test from pulse_private.test_gift_events) e join public.pulse_profiles p on p.id=e.sender_id join pulse_private.gift_catalog g on g.sku=e.sku
  where e.session_id=p_session and(e.created_at,e.id)>(p_after,p_cursor)
  order by e.created_at,e.id limit 50)x;
 -- Advance over blocked senders too, without exposing their event/profile.
 if jsonb_array_length(rows)>0 then
  last_time=(rows->-1->>'created_at')::timestamptz;last_id=(rows->-1->>'id')::uuid;
 else last_time=p_after;last_id=p_cursor;end if;
 select coalesce(jsonb_agg(v order by v->>'created_at',v->>'id'),'[]')into rows from jsonb_array_elements(rows)v where not pulse_private.social_blocked((v->>'sender_id')::uuid);
 return jsonb_build_object('items',rows,'after',last_time,'cursor',last_id);
end $$;
commit;
