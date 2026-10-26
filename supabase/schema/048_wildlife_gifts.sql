begin;
-- Retire all synthetic character/effect/filter gifts; keep historical receipts.
update pulse_private.gift_catalog set enabled=false where sku in
('dream','phoenix','dragon','sports_car','pulse_stars','galaxy','voltage_dominion','void_rift','solar_overdrive','quantum_cathedral','prism_avalanche','aurora_ascension','gravity_collapse','pulse_supernova','archmage','moon_witch','wizard_filter','witch_filter');
update pulse_private.gift_catalog set enabled=true where sku in ('lion','gorilla','royal_lions','thunder_falcon','butterfly');
-- Prices, earnings, receipts, ranks and server-authoritative sending are preserved.
-- Include unit price so a large combo of a cheap gift still stays notification-only.
create or replace function pulse_private.gift_feed(p_session uuid,p_after timestamptz,p_cursor uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare s public.pulse_live_sessions; rows jsonb;last_time timestamptz;last_id uuid;
begin
 perform pulse_private.require_active();
 select * into s from public.pulse_live_sessions where id=p_session;
 if not pulse_private.live_read(p_session) then raise exception 'LIVE unavailable';end if;
 if s.id is null or pulse_private.social_blocked(s.host_id)then raise exception 'LIVE unavailable';end if;
 if (p_after is null)<>(p_cursor is null)then raise exception 'Invalid gift cursor';end if;
 if p_after is null then
  select created_at,id into last_time,last_id from (select id,sender_id,recipient_id,session_id,sku,quantity,created_at,false is_test from pulse_private.gift_events union all select id,sender_id,recipient_id,session_id,sku,quantity,created_at,true is_test from pulse_private.test_gift_events) combined where session_id=p_session order by created_at desc,id desc limit 1;
  return jsonb_build_object('items','[]'::jsonb,'after',coalesce(last_time,'1970-01-01'::timestamptz),'cursor',coalesce(last_id,'00000000-0000-0000-0000-000000000000'::uuid));
 end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by created_at,id),'[]')into rows from(
  select e.id,e.created_at,e.sku,g.coins,e.quantity,e.sender_id,e.recipient_id,e.is_test,p.display_name,p.avatar_path,case when e.is_test then 'TEST · '||g.title else g.title end title,
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
