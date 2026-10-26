begin;
-- Existing installs may predate the summary RPC. This is additive and preserves messages.
alter table public.pulse_messages add column if not exists forwarded boolean not null default false;
create index if not exists pulse_messages_latest on public.pulse_messages(chat_id,created_at desc,id desc);
create or replace function pulse_private.chat_summaries() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform pulse_private.require_active();
 return coalesce((select jsonb_agg(to_jsonb(rows) order by created_at desc nulls last,chat_id) from (
 select c.id chat_id,(select cc.avatar_path from pulse_private.community_cards cc where cc.chat_id=c.id) avatar_path,
 m.id message_id,m.body,m.media_kind,m.created_at,m.sender_id,m.forwarded,
 (select display_name from public.pulse_profiles where id=m.sender_id) sender_name,
 m.attachment_path is not null has_attachment,m.status_id is not null status_reply,
 case when m.id is null or m.sender_id<>auth.uid() then null
 when exists(select 1 from public.pulse_members where chat_id=c.id and user_id<>auth.uid())
 and not exists(select 1 from public.pulse_members peer where peer.chat_id=c.id and peer.user_id<>auth.uid()
 and not exists(select 1 from public.pulse_receipts r where r.message_id=m.id and r.user_id=peer.user_id and r.read_at is not null)) then 'read'
 when exists(select 1 from public.pulse_members where chat_id=c.id and user_id<>auth.uid())
 and not exists(select 1 from public.pulse_members peer where peer.chat_id=c.id and peer.user_id<>auth.uid()
 and not exists(select 1 from public.pulse_receipts r where r.message_id=m.id and r.user_id=peer.user_id and (r.delivered_at is not null or r.read_at is not null))) then 'delivered'
 else 'sent' end delivery
 from (select c.* from public.pulse_chats c join public.pulse_members own on own.chat_id=c.id and own.user_id=auth.uid()
 where pulse_private.is_member(c.id) order by c.created_at desc limit 200)c
 left join lateral(select m.* from public.pulse_messages m where m.chat_id=c.id and m.deleted_at is null
 and not pulse_private.social_blocked(m.sender_id)
 and not exists(select 1 from public.pulse_message_preferences pref where pref.message_id=m.id and pref.user_id=auth.uid() and pref.hidden)
 order by m.created_at desc,m.id desc limit 1)m on true
 where not exists(select 1 from public.pulse_members peer where peer.chat_id=c.id and pulse_private.social_blocked(peer.user_id))
 )rows),'[]'::jsonb);
end $$;
create or replace function public.pulse_chat_summaries() returns jsonb language sql stable security invoker set search_path='' as $$
 select pulse_private.require_active();select pulse_private.chat_summaries()
$$;
revoke all on function pulse_private.chat_summaries(),public.pulse_chat_summaries() from public,anon;
grant execute on function pulse_private.chat_summaries(),public.pulse_chat_summaries() to authenticated;
-- Retire the abstract film collection from new sends; retain receipts and historical playback.
update pulse_private.gift_catalog set enabled=false where sku in ('voltage_dominion','void_rift','solar_overdrive','quantum_cathedral','prism_avalanche','aurora_ascension','gravity_collapse','pulse_supernova');
insert into pulse_private.gift_catalog(sku,title,emoji,coins,p_coins,enabled) values
('archmage','The Archmage','',79999,3999.95,true),
('moon_witch','Moonlight Witch','',84999,4249.95,true),
('wizard_filter','Wizard Head Filter','',15999,799.95,true),
('witch_filter','Witch Head Filter','',18999,949.95,true)
on conflict(sku) do nothing;
commit;
