-- Additive chat update; existing messages and accounts are preserved.
begin;
alter table public.pulse_messages add column forwarded boolean not null default false;
create index pulse_messages_latest on public.pulse_messages(chat_id,created_at desc,id desc);
create function pulse_private.chat_summaries() returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 perform pulse_private.require_active();
 return coalesce((select jsonb_agg(to_jsonb(rows) order by created_at desc nulls last,chat_id) from (
 select c.id chat_id,(select cc.avatar_path from pulse_private.community_cards cc where cc.chat_id=c.id) avatar_path,m.body,m.media_kind,m.created_at,m.sender_id,m.forwarded,
 m.attachment_path is not null has_attachment,m.status_id is not null status_reply
 from (select c.* from public.pulse_chats c join public.pulse_members own on own.chat_id=c.id and own.user_id=auth.uid() order by c.created_at desc limit 200)c
 left join lateral(select m.* from public.pulse_messages m where m.chat_id=c.id and m.deleted_at is null
 and not pulse_private.social_blocked(m.sender_id)
 and not exists(select 1 from public.pulse_message_preferences pref where pref.message_id=m.id and pref.user_id=auth.uid() and pref.hidden)
 order by m.created_at desc,m.id desc limit 1)m on true
 where not exists(select 1 from public.pulse_members peer where peer.chat_id=c.id and pulse_private.social_blocked(peer.user_id))
 )rows),'[]');
end $$;
create function public.pulse_chat_summaries() returns jsonb language sql stable security invoker set search_path='' as $$select pulse_private.require_active();select pulse_private.chat_summaries()$$;
create function pulse_private.forward_message(p_id uuid,p_source uuid,p_chat uuid,p_path text) returns uuid
language plpgsql security definer set search_path='' as $$
declare source public.pulse_messages; old public.pulse_messages; mime text; kind text; copied storage.objects;begin
 perform pulse_private.require_active();
 if p_id is null or p_source is null or not pulse_private.is_member(p_chat) then raise exception 'Conversation unavailable';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,24));
 select * into old from public.pulse_messages where id=p_id;
 if found then
  if old.chat_id=p_chat and old.sender_id=auth.uid() and old.forwarded and old.deleted_at is null then return p_id;end if;
  raise exception 'Forward unavailable';
 end if;
 select * into source from public.pulse_messages where id=p_source and deleted_at is null;
 if not found or not pulse_private.is_member(source.chat_id) or pulse_private.social_blocked(source.sender_id)
 or exists(select 1 from public.pulse_message_preferences where message_id=p_source and user_id=auth.uid() and hidden) then raise exception 'Original message unavailable';end if;
 if source.attachment_path is null then
  if p_path is not null then raise exception 'Unexpected attachment';end if;
  perform pulse_private.send_message(p_id,p_chat,source.body,null,null);
 else
  if p_path is null or p_path not like p_chat::text||'/'||auth.uid()::text||'/'||p_id::text||'/%' then raise exception 'Copy media to the destination conversation first';end if;
  select metadata->>'mimetype' into mime from storage.objects where bucket_id='pulse-media' and name=source.attachment_path;
  select * into copied from storage.objects where bucket_id='pulse-media' and name=p_path;
  if mime is null or not found or copied.metadata->>'mimetype' is distinct from mime then raise exception 'Forwarded file unavailable';end if;
  kind=coalesce(source.media_kind,case when mime like 'image/%' then 'image' when mime like 'video/%' then 'video' when mime like 'audio/%' then 'audio' else 'file' end);
  perform pulse_private.send_media_message(p_id,p_chat,source.body,null,p_path,kind,mime,source.duration_ms,source.waveform);
 end if;
 update public.pulse_messages set forwarded=true where id=p_id and sender_id=auth.uid();
 return p_id;
end $$;
create function public.pulse_forward_message(p_id uuid,p_source uuid,p_chat uuid,p_path text default null) returns uuid language sql security invoker set search_path='' as $$select pulse_private.require_active();select pulse_private.forward_message(p_id,p_source,p_chat,p_path)$$;
revoke all on function pulse_private.chat_summaries(),public.pulse_chat_summaries(),pulse_private.forward_message(uuid,uuid,uuid,text),public.pulse_forward_message(uuid,uuid,uuid,text) from public,anon;
grant execute on function pulse_private.chat_summaries(),public.pulse_chat_summaries(),pulse_private.forward_message(uuid,uuid,uuid,text),public.pulse_forward_message(uuid,uuid,uuid,text) to authenticated;
-- A copy remains private to its uploader until its destination message exists.
-- Published legacy and current attachments still use their message membership.
create function pulse_private.message_media_read(p_name text) returns boolean
language plpgsql stable security definer set search_path='' as $$declare cid uuid;begin
 if not pulse_private.account_active() then return false;end if;
 cid=split_part(p_name,'/',1)::uuid;
 if not pulse_private.is_member(cid) then return false;end if;
 return split_part(p_name,'/',2)=auth.uid()::text or exists(select 1 from public.pulse_messages m where m.chat_id=cid and m.attachment_path=p_name and m.deleted_at is null and not exists(select 1 from public.pulse_message_preferences pref where pref.message_id=m.id and pref.user_id=auth.uid() and pref.hidden));
 exception when invalid_text_representation then return false;
end $$;
revoke all on function pulse_private.message_media_read(text) from public,anon;
grant execute on function pulse_private.message_media_read(text) to authenticated;
drop policy pulse_media_read on storage.objects;
create policy pulse_media_read on storage.objects for select to authenticated using(bucket_id='pulse-media' and pulse_private.message_media_read(name));
-- Client cleanup can remove only its own unreferenced copies, never sent media.
create policy pulse_media_orphan_delete on storage.objects for delete to authenticated
 using(bucket_id='pulse-media' and pulse_private.account_active() and (storage.foldername(name))[2]=auth.uid()::text
 and pulse_private.is_member(((storage.foldername(name))[1])::uuid)
 and not exists(select 1 from public.pulse_messages where attachment_path=name));
commit;
