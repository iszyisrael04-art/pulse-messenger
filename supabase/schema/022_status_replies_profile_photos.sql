-- Additive installation script; run after 021. No existing content is removed.
begin;
update storage.buckets set file_size_limit=15728640 where id='pulse-avatars';
alter table public.pulse_messages add column if not exists status_id uuid;
-- Deliberately no FK: expired/deleted statuses must not delete private replies.
create function pulse_private.reply_status(p_id uuid,p_status uuid,p_body text) returns uuid
language plpgsql security definer set search_path='' as $$
declare s public.pulse_statuses; cid uuid; existing public.pulse_messages;
begin
 perform pulse_private.require_active();
 if p_id is null or p_status is null or p_body is null or length(trim(p_body))=0 or length(p_body)>4000 then raise exception 'Enter a reply of 1 to 4000 characters';end if;
 -- Serialize duplicate submissions; retry cannot change the original reply.
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,22));
 select * into existing from public.pulse_messages where id=p_id;
 if found then
  if existing.sender_id=auth.uid() and existing.status_id=p_status and existing.deleted_at is null and pulse_private.is_member(existing.chat_id) then return existing.chat_id;end if;
  raise exception 'Reply unavailable';
 end if;
 select * into s from public.pulse_statuses where id=p_status and expires_at>now() and pulse_private.can_see_status(user_id);
 if not found or s.user_id=auth.uid() then raise exception 'Status unavailable or expired';end if;
 cid=pulse_private.start_chat(array[s.user_id],'Status reply',false);
 -- Preserve rate limits, blocking and message-request consent checks.
 perform pulse_private.send_message(p_id,cid,trim(p_body),null,null);
 update public.pulse_messages set status_id=p_status where id=p_id and sender_id=auth.uid();
 return cid;
end $$;
create function public.pulse_reply_status(p_id uuid,p_status uuid,p_body text) returns uuid
language sql security invoker set search_path='' as $$select pulse_private.require_active();select pulse_private.reply_status(p_id,p_status,p_body)$$;
revoke all on function pulse_private.reply_status(uuid,uuid,text),public.pulse_reply_status(uuid,uuid,text) from public,anon;
grant execute on function pulse_private.reply_status(uuid,uuid,text),public.pulse_reply_status(uuid,uuid,text) to authenticated;
-- Remove the old eight-photo count restriction. Keep a metadata-size bound,
-- per-file entitlements, validated ownership and the one-video-per-post rule.
alter table public.pulse_social_content drop constraint pulse_social_content_media_check;
alter table public.pulse_social_content add constraint pulse_social_content_media_check
 check(jsonb_typeof(media)='array' and octet_length(media::text)<=1048576);
do $$declare def text;begin
 def=pg_get_functiondef('pulse_private.social_write(uuid,text,text,jsonb,text,boolean)'::regprocedure);
 if position('jsonb_array_length(p_media)>8' in def)=0 then raise exception 'Unexpected social_write definition';end if;
 def=replace(def,'jsonb_array_length(p_media)>8','octet_length(p_media::text)>1048576');
 def=replace(def,'Choose up to 8 photos or one video','This post contains too much attachment metadata; split it into smaller posts');
 execute def;
end $$;
commit;
