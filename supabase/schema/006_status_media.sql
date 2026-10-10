-- Pulse v0.2.1: photo/video statuses. Existing text statuses remain compatible.
begin;
alter table public.pulse_statuses add column if not exists media_path text;
alter table public.pulse_statuses add column if not exists media_type text;
alter table public.pulse_statuses drop constraint if exists pulse_statuses_body_check;
alter table public.pulse_statuses add constraint pulse_statuses_body_check check (
 length(body)<=1000 and (length(trim(body))>0 or media_path is not null)
);
alter table public.pulse_statuses add constraint pulse_statuses_media_check check (
 (media_path is null and media_type is null) or
 (media_path is not null and media_type is not null and media_type in ('image','video'))
);
create index if not exists pulse_statuses_media_path on public.pulse_statuses(media_path) where media_path is not null;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('pulse-status-media','pulse-status-media',false,20971520,
 array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime','video/webm']);

-- An uploaded object is readable only by its owner or a viewer of an active status.
create function pulse_private.can_read_status_media(p_path text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (
 split_part(p_path,'/',1)=auth.uid()::text or exists (
 select 1 from public.pulse_statuses s where s.media_path=p_path and s.expires_at>now()
 and pulse_private.can_see_status(s.user_id)))
$$;
revoke all on function pulse_private.can_read_status_media(text) from public,anon;
grant execute on function pulse_private.can_read_status_media(text) to authenticated;
create policy pulse_status_media_read on storage.objects for select to authenticated
using(bucket_id='pulse-status-media' and pulse_private.can_read_status_media(name));
create policy pulse_status_media_insert on storage.objects for insert to authenticated
with check(bucket_id='pulse-status-media' and (storage.foldername(name))[1]=auth.uid()::text);
create policy pulse_status_media_delete on storage.objects for delete to authenticated
using(bucket_id='pulse-status-media' and (storage.foldername(name))[1]=auth.uid()::text);

create function pulse_private.post_media_status(p_id uuid,p_body text,p_path text,p_type text) returns uuid
language plpgsql security definer set search_path='' as $$
 declare mime text;
 begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_path is null or split_part(p_path,'/',1)<>auth.uid()::text then raise exception 'Invalid status file'; end if;
 if p_type is null or p_type not in ('image','video') then raise exception 'Invalid status type'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,5));
 if exists(select 1 from public.pulse_statuses where id=p_id and user_id=auth.uid()) then return p_id; end if;
 if (select count(*) from public.pulse_statuses where user_id=auth.uid() and created_at>now()-interval '1 day')>=30 then raise exception 'Status limit reached'; end if;
 select metadata->>'mimetype' into mime from storage.objects where bucket_id='pulse-status-media' and name=p_path;
 if mime is null then raise exception 'Upload the file before posting'; end if;
 if (p_type='image' and mime not in ('image/jpeg','image/png','image/webp')) or
    (p_type='video' and mime not in ('video/mp4','video/quicktime','video/webm')) then raise exception 'Status file type does not match'; end if;
 insert into public.pulse_statuses(id,user_id,body,media_path,media_type)
 values(p_id,auth.uid(),coalesce(trim(p_body),''),p_path,p_type);
 return p_id;
 end
$$;
create function pulse_private.delete_status(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
 begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 delete from public.pulse_statuses where id=p_id and user_id=auth.uid();
 if not found then raise exception 'Status unavailable'; end if;
 end
$$;
create function public.pulse_post_media_status(p_id uuid,p_body text,p_path text,p_type text) returns uuid
language sql security invoker set search_path='' as $$ select pulse_private.post_media_status(p_id,p_body,p_path,p_type) $$;
create function public.pulse_delete_status(p_id uuid) returns void
language sql security invoker set search_path='' as $$ select pulse_private.delete_status(p_id) $$;
revoke all on function pulse_private.post_media_status(uuid,text,text,text),pulse_private.delete_status(uuid),
 public.pulse_post_media_status(uuid,text,text,text),public.pulse_delete_status(uuid) from public,anon;
grant execute on function pulse_private.post_media_status(uuid,text,text,text),pulse_private.delete_status(uuid),
 public.pulse_post_media_status(uuid,text,text,text),public.pulse_delete_status(uuid) to authenticated;
commit;
