begin;
create table pulse_private.gifter_preferences(user_id uuid primary key references public.pulse_profiles on delete cascade,show_rank boolean not null default true,show_spend boolean not null default false);
alter table pulse_private.gifter_preferences enable row level security;
revoke all on pulse_private.gifter_preferences from public,anon,authenticated;
create policy deny_clients on pulse_private.gifter_preferences for all to anon,authenticated using(false)with check(false);
create function pulse_private.gifter_tier(p_coins bigint)returns integer language sql immutable set search_path=''as $$
 select case when p_coins>=1000000 then 10 when p_coins>=500000 then 9 when p_coins>=100000 then 8 when p_coins>=50000 then 7 when p_coins>=25000 then 6 when p_coins>=10000 then 5 when p_coins>=5000 then 4 when p_coins>=1000 then 3 when p_coins>=100 then 2 when p_coins>=1 then 1 else 0 end
$$;
create function pulse_private.gifter_status(p_user uuid,p_show_rank boolean,p_show_spend boolean)returns jsonb language plpgsql security definer set search_path=''as $$
declare total bigint;pref pulse_private.gifter_preferences;
begin
 perform pulse_private.require_active();
 if p_user is null or not exists(select 1 from public.pulse_profiles where id=p_user)or pulse_private.social_blocked(p_user)then return null;end if;
 if p_show_rank is not null or p_show_spend is not null then
  if p_user<>auth.uid()then raise exception 'Only change your own visibility';end if;
  insert into pulse_private.gifter_preferences(user_id,show_rank,show_spend)values(p_user,coalesce(p_show_rank,true),coalesce(p_show_spend,false))on conflict(user_id)do update set show_rank=coalesce(p_show_rank,pulse_private.gifter_preferences.show_rank),show_spend=coalesce(p_show_spend,pulse_private.gifter_preferences.show_spend);
 end if;
 select * into pref from pulse_private.gifter_preferences where user_id=p_user;
 select coalesce(sum(coins),0)into total from pulse_private.gift_events where sender_id=p_user;
 return jsonb_build_object('user_id',p_user,'rank',case when p_user=auth.uid()or coalesce(pref.show_rank,true)then pulse_private.gifter_tier(total)else null end,
 'coins_spent',case when p_user=auth.uid()or coalesce(pref.show_spend,false)then total else null end,
 'show_rank',coalesce(pref.show_rank,true),'show_spend',coalesce(pref.show_spend,false));
end $$;
create function pulse_private.gifter_ranks(p_users uuid[])returns jsonb language plpgsql security definer set search_path=''as $$begin
 perform pulse_private.require_active();
 if p_users is null or cardinality(p_users)>100 then raise exception 'Choose up to 100 users';end if;
 return coalesce((select jsonb_agg(pulse_private.gifter_status(u,null,null))from(select distinct unnest(p_users)u)x),'[]');
end $$;
create function pulse_private.gift_feed(p_session uuid,p_after timestamptz,p_cursor uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare s public.pulse_live_sessions; rows jsonb;last_time timestamptz;last_id uuid;
begin
 perform pulse_private.require_active();
 select * into s from public.pulse_live_sessions where id=p_session;
 if s.id is null or pulse_private.social_blocked(s.host_id)then raise exception 'LIVE unavailable';end if;
 if (p_after is null)<>(p_cursor is null)then raise exception 'Invalid gift cursor';end if;
 if p_after is null then
  select created_at,id into last_time,last_id from pulse_private.gift_events where session_id=p_session order by created_at desc,id desc limit 1;
  return jsonb_build_object('items','[]'::jsonb,'after',coalesce(last_time,'1970-01-01'::timestamptz),'cursor',coalesce(last_id,'00000000-0000-0000-0000-000000000000'::uuid));
 end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by created_at,id),'[]')into rows from(
  select e.id,e.created_at,e.sku,e.quantity,e.sender_id,e.recipient_id,p.display_name,p.avatar_path,g.title,
   pulse_private.gifter_status(e.sender_id,null,null)gifter
  from pulse_private.gift_events e join public.pulse_profiles p on p.id=e.sender_id join pulse_private.gift_catalog g on g.sku=e.sku
  where e.session_id=p_session and(e.created_at,e.id)>(p_after,p_cursor)
  order by e.created_at,e.id limit 50)x;
 -- Advance over blocked senders too, without exposing their event/profile.
 if jsonb_array_length(rows)>0 then
  last_time=(rows->-1->>'created_at')::timestamptz;last_id=(rows->-1->>'id')::uuid;
 else last_time=p_after;last_id=p_cursor;end if;
 select coalesce(jsonb_agg(v order by v->>'created_at',v->>'id'),'[]')into rows from jsonb_array_elements(rows)v where not pulse_private.social_blocked((v->>'sender_id')::uuid);
 return jsonb_build_object('items',rows,'after',last_time,'cursor',last_id);
end $$;
create function public.pulse_gifter_status(p_user uuid,p_show_rank boolean default null,p_show_spend boolean default null)returns jsonb language sql security invoker set search_path=''as $$select pulse_private.gifter_status(p_user,p_show_rank,p_show_spend)$$;
create function public.pulse_gifter_ranks(p_users uuid[])returns jsonb language sql security invoker set search_path=''as $$select pulse_private.gifter_ranks(p_users)$$;
create function public.pulse_gift_feed(p_session uuid,p_after timestamptz default null,p_cursor uuid default null)returns jsonb language sql security invoker set search_path=''as $$select pulse_private.gift_feed(p_session,p_after,p_cursor)$$;
revoke all on function pulse_private.gifter_tier(bigint),pulse_private.gifter_status(uuid,boolean,boolean),pulse_private.gifter_ranks(uuid[]),pulse_private.gift_feed(uuid,timestamptz,uuid),public.pulse_gifter_status(uuid,boolean,boolean),public.pulse_gifter_ranks(uuid[]),public.pulse_gift_feed(uuid,timestamptz,uuid)from public,anon,authenticated;
grant execute on function pulse_private.gifter_status(uuid,boolean,boolean),pulse_private.gifter_ranks(uuid[]),pulse_private.gift_feed(uuid,timestamptz,uuid),public.pulse_gifter_status(uuid,boolean,boolean),public.pulse_gifter_ranks(uuid[]),public.pulse_gift_feed(uuid,timestamptz,uuid)to authenticated;
commit;
