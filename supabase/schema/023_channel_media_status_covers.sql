-- Additive Pulse 0.5.3 installation script; run once after 022.
begin;
alter table public.pulse_posts add column attachment_path text,
 add column media_kind text, add column media_mime text, add column cover_path text,
 add column duration_ms integer, add column waveform jsonb not null default '[]';
alter table public.pulse_posts drop constraint pulse_posts_body_check;
alter table public.pulse_posts add constraint pulse_posts_body_check check(length(body)<=8000 and (length(trim(body))>0 or attachment_path is not null));
alter table public.pulse_posts add constraint pulse_posts_media_check check(
 (attachment_path is null and media_kind is null and media_mime is null and cover_path is null) or
 (attachment_path is not null and media_kind is not null and media_kind in ('image','video','audio') and media_mime is not null));
create index pulse_posts_search on public.pulse_posts using gin(to_tsvector('simple',body));
create index pulse_posts_media_path on public.pulse_posts(attachment_path) where attachment_path is not null;
create index pulse_posts_cover_path on public.pulse_posts(cover_path) where cover_path is not null;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values(
 'pulse-channel-media','pulse-channel-media',false,2147483648,
 array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime','video/webm','audio/mp4','audio/mpeg','audio/ogg','audio/wav','audio/aac']);
create function pulse_private.channel_upload_allowed(p_path text) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare cid uuid;begin
 if not pulse_private.account_active() or split_part(p_path,'/',2)<>auth.uid()::text then return false;end if;
 cid=split_part(p_path,'/',1)::uuid;
 return pulse_private.channel_admin(cid) and split_part(p_path,'/',3)<>'' and split_part(p_path,'/',4)<>'';
 exception when invalid_text_representation then return false;
end $$;
create function pulse_private.channel_media_read(p_path text) returns boolean
language sql stable security definer set search_path='' as $$
 select pulse_private.account_active() and (pulse_private.channel_upload_allowed(p_path) or exists(
 select 1 from public.pulse_posts p join public.pulse_channels c on c.id=p.channel_id
 where (p.attachment_path=p_path or p.cover_path=p_path)
 and not pulse_private.social_blocked(p.author_id) and not pulse_private.social_blocked(c.owner_id)))
$$;
revoke all on function pulse_private.channel_upload_allowed(text),pulse_private.channel_media_read(text) from public,anon;
grant execute on function pulse_private.channel_upload_allowed(text),pulse_private.channel_media_read(text) to authenticated;
create policy pulse_channel_media_insert on storage.objects for insert to authenticated
 with check(bucket_id='pulse-channel-media' and pulse_private.channel_upload_allowed(name));
create function pulse_private.channel_storage_size() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.bucket_id='pulse-channel-media' and auth.uid() is not null and new.metadata->>'size' is not null and pulse_private.social_size_allowed((new.metadata->>'size')::bigint) is not true then raise exception 'File exceeds account upload allowance';end if;
 return new;
end $$;
revoke all on function pulse_private.channel_storage_size() from public,anon,authenticated;
create trigger pulse_channel_storage_size before insert or update of metadata on storage.objects for each row execute function pulse_private.channel_storage_size();
create policy pulse_channel_media_read on storage.objects for select to authenticated
 using(bucket_id='pulse-channel-media' and pulse_private.channel_media_read(name));
create policy pulse_channel_media_delete on storage.objects for delete to authenticated
 using(bucket_id='pulse-channel-media' and pulse_private.channel_upload_allowed(name)
 and not exists(select 1 from public.pulse_posts where attachment_path=name or cover_path=name));
create function pulse_private.channel_publish(p_id uuid,p_channel uuid,p_body text,p_path text,p_kind text,p_mime text,p_duration integer,p_waveform jsonb,p_cover text) returns uuid
language plpgsql security definer set search_path='' as $$
declare obj storage.objects; old public.pulse_posts; prefix text;begin
 perform pulse_private.require_active();
 if not pulse_private.channel_admin(p_channel) then raise exception 'Channel administrator required';end if;
 if p_id is null or p_body is null or length(p_body)>8000 then raise exception 'Invalid announcement';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,23));
 select * into old from public.pulse_posts where id=p_id;
 if found then
  if old.channel_id=p_channel and old.author_id=auth.uid() then return p_id;end if;
  raise exception 'Announcement unavailable';
 end if;
 if exists(select 1 from public.pulse_posts where author_id=auth.uid() and created_at>now()-interval '5 seconds') then raise exception 'Please wait before posting again';end if;
 if p_path is null then
  if p_kind is not null or p_mime is not null or p_cover is not null or length(trim(p_body))=0 then raise exception 'Add text or media';end if;
 else
  prefix=p_channel::text||'/'||auth.uid()::text||'/'||p_id::text||'/';
  if p_path not like prefix||'%' or p_kind is null or p_kind not in ('image','video','audio') then raise exception 'Invalid announcement file';end if;
  select * into obj from storage.objects where bucket_id='pulse-channel-media' and name=p_path;
  if not found or obj.metadata->>'mimetype' is distinct from p_mime or pulse_private.social_size_allowed((obj.metadata->>'size')::bigint) is not true then raise exception 'Upload a supported file within your upload allowance';end if;
  if (p_kind='image' and p_mime not in ('image/jpeg','image/png','image/webp')) or
   (p_kind='video' and p_mime not in ('video/mp4','video/quicktime','video/webm')) or
   (p_kind='audio' and p_mime not in ('audio/mp4','audio/mpeg','audio/ogg','audio/wav','audio/aac')) then raise exception 'File type does not match';end if;
  if p_cover is not null and (p_kind<>'video' or p_cover not like prefix||'%' or not exists(select 1 from storage.objects where bucket_id='pulse-channel-media' and name=p_cover and metadata->>'mimetype'='image/jpeg' and (metadata->>'size')::bigint between 1 and 2097152)) then raise exception 'Invalid cover image';end if;
 end if;
 if p_waveform is null or jsonb_typeof(p_waveform)<>'array' then raise exception 'Invalid waveform';end if;
 if jsonb_array_length(p_waveform)>80 then raise exception 'Invalid waveform';end if;
 if exists(select 1 from jsonb_array_elements(p_waveform) x where jsonb_typeof(x)<>'number') then raise exception 'Invalid waveform';end if;
 if exists(select 1 from jsonb_array_elements(p_waveform) x where (x#>>'{}')::numeric not between 0 and 1) or p_duration is not null and p_duration not between 1 and 86400000 then raise exception 'Invalid media duration';end if;
 insert into public.pulse_posts(id,channel_id,author_id,body,attachment_path,media_kind,media_mime,cover_path,duration_ms,waveform)
 values(p_id,p_channel,auth.uid(),trim(p_body),p_path,p_kind,p_mime,p_cover,p_duration,p_waveform);
 return p_id;
end $$;
create function public.pulse_channel_publish(p_id uuid,p_channel uuid,p_body text,p_path text default null,p_kind text default null,p_mime text default null,p_duration integer default null,p_waveform jsonb default '[]',p_cover text default null) returns uuid
language sql security invoker set search_path='' as $$select pulse_private.require_active();select pulse_private.channel_publish(p_id,p_channel,p_body,p_path,p_kind,p_mime,p_duration,p_waveform,p_cover)$$;
create function pulse_private.channel_history(p_channel uuid,p_query text,p_before timestamptz,p_cursor uuid,p_media boolean) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 perform pulse_private.require_active();
 if p_query is null or length(p_query)>100 or p_media is null or (p_before is null)<>(p_cursor is null) then raise exception 'Invalid search';end if;
 if not exists(select 1 from public.pulse_channels where id=p_channel and not pulse_private.social_blocked(owner_id)) then raise exception 'Channel unavailable';end if;
 return coalesce((select jsonb_agg(to_jsonb(rows) order by created_at desc,id desc) from(
 select p.* from public.pulse_posts p where p.channel_id=p_channel and not pulse_private.social_blocked(p.author_id)
 and (not p_media or p.attachment_path is not null)
 and (trim(p_query)='' or to_tsvector('simple',p.body) @@ websearch_to_tsquery('simple',trim(p_query)))
 and (p_before is null or (p.created_at,p.id)<(p_before,p_cursor))
 order by p.created_at desc,p.id desc limit 30)rows),'[]');
end $$;
create function public.pulse_channel_history(p_channel uuid,p_query text default '',p_before timestamptz default null,p_cursor uuid default null,p_media boolean default false) returns jsonb
language sql stable security invoker set search_path='' as $$select pulse_private.require_active();select pulse_private.channel_history(p_channel,p_query,p_before,p_cursor,p_media)$$;
create function pulse_private.channel_summary(p_channel uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 perform pulse_private.require_active();
 return (select to_jsonb(c)||jsonb_build_object('followers',(select count(*) from public.pulse_followers where channel_id=c.id),'media_count',(select count(*) from public.pulse_posts where channel_id=c.id and attachment_path is not null and not pulse_private.social_blocked(author_id))) from public.pulse_channels c where c.id=p_channel and not pulse_private.social_blocked(c.owner_id));
end $$;
create function public.pulse_channel_summary(p_channel uuid) returns jsonb language sql stable security invoker set search_path='' as $$select pulse_private.require_active();select pulse_private.channel_summary(p_channel)$$;
revoke all on function pulse_private.channel_publish(uuid,uuid,text,text,text,text,integer,jsonb,text),public.pulse_channel_publish(uuid,uuid,text,text,text,text,integer,jsonb,text),pulse_private.channel_history(uuid,text,timestamptz,uuid,boolean),public.pulse_channel_history(uuid,text,timestamptz,uuid,boolean),pulse_private.channel_summary(uuid),public.pulse_channel_summary(uuid) from public,anon;
grant execute on function pulse_private.channel_publish(uuid,uuid,text,text,text,text,integer,jsonb,text),public.pulse_channel_publish(uuid,uuid,text,text,text,text,integer,jsonb,text),pulse_private.channel_history(uuid,text,timestamptz,uuid,boolean),public.pulse_channel_history(uuid,text,timestamptz,uuid,boolean),pulse_private.channel_summary(uuid),public.pulse_channel_summary(uuid) to authenticated;
create function pulse_private.channel_entry(p_post uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform pulse_private.require_active();
 return (select to_jsonb(p)||jsonb_build_object('username',u.username) from public.pulse_posts p join public.pulse_channels c on c.id=p.channel_id join public.pulse_profiles u on u.id=p.author_id where p.id=p_post and not pulse_private.social_blocked(p.author_id) and not pulse_private.social_blocked(c.owner_id));
end $$;
create function public.pulse_channel_entry(p_post uuid) returns jsonb language sql stable security invoker set search_path='' as $$select pulse_private.require_active();select pulse_private.channel_entry(p_post)$$;
revoke all on function pulse_private.channel_entry(uuid),public.pulse_channel_entry(uuid) from public,anon;
grant execute on function pulse_private.channel_entry(uuid),public.pulse_channel_entry(uuid) to authenticated;
-- Rate limit authenticated LiveKit control-plane probes without exposing secrets.
create function pulse_private.live_probe() returns void language plpgsql security definer set search_path='' as $$begin perform pulse_private.require_active();perform pulse_private.social_rate('live_probe',3,60);end $$;
revoke all on function pulse_private.live_probe() from public,anon;
grant execute on function pulse_private.live_probe() to authenticated;
create function public.pulse_live_probe() returns void language sql security invoker set search_path='' as $$select pulse_private.require_active();select pulse_private.live_probe()$$;
revoke all on function public.pulse_live_probe() from public,anon;
grant execute on function public.pulse_live_probe() to authenticated;
-- A persisted video status cover obeys the same audience and expiry as its video.
alter table public.pulse_statuses add column cover_path text;
create index pulse_statuses_cover on public.pulse_statuses(cover_path) where cover_path is not null;
create or replace function pulse_private.can_read_status_media(p_path text) returns boolean
language sql stable security definer set search_path='' as $$
 select pulse_private.account_active() and (split_part(p_path,'/',1)=auth.uid()::text or exists (
 select 1 from public.pulse_statuses s where (s.media_path=p_path or s.cover_path=p_path) and s.expires_at>now() and pulse_private.can_see_status(s.user_id)))
$$;
create function pulse_private.post_status_cover(p_id uuid,p_body text,p_path text,p_cover text) returns uuid
language plpgsql security definer set search_path='' as $$begin
 perform pulse_private.require_active();
 if p_cover is null or p_cover<>auth.uid()::text||'/'||p_id::text||'-cover.jpg' or not exists(select 1 from storage.objects where bucket_id='pulse-status-media' and name=p_cover and metadata->>'mimetype'='image/jpeg' and (metadata->>'size')::bigint between 1 and 2097152) then raise exception 'Upload a cover image first';end if;
 perform pulse_private.post_media_status(p_id,p_body,p_path,'video');
 update public.pulse_statuses set cover_path=p_cover where id=p_id and user_id=auth.uid() and media_type='video' and media_path=p_path;
 if not found then raise exception 'Status unavailable';end if;
 return p_id;
end $$;
create function public.pulse_post_status_cover(p_id uuid,p_body text,p_path text,p_cover text) returns uuid language sql security invoker set search_path='' as $$select pulse_private.require_active();select pulse_private.post_status_cover(p_id,p_body,p_path,p_cover)$$;
revoke all on function pulse_private.post_status_cover(uuid,text,text,text),public.pulse_post_status_cover(uuid,text,text,text) from public,anon;
grant execute on function pulse_private.post_status_cover(uuid,text,text,text),public.pulse_post_status_cover(uuid,text,text,text) to authenticated;
commit;
