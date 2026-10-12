-- Additive upgrade after 009. Does not reset messaging/account data.
begin;
create or replace function pulse_private.social_size_allowed(p_size bigint) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and p_size between 1 and 2147483648 and
 (p_size<=524288000 or exists(select 1 from public.pulse_premium where user_id=auth.uid() and expires_at>now()))
$$;
revoke all on function pulse_private.social_size_allowed(bigint) from public,anon;
grant execute on function pulse_private.social_size_allowed(bigint) to authenticated;
create or replace function pulse_private.social_upload_access(p_bytes bigint) returns jsonb language plpgsql stable security definer set search_path='' as $$
 begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_bytes is null or p_bytes<=0 then raise exception 'Empty file'; end if;
 return jsonb_build_object('allowed',pulse_private.social_size_allowed(p_bytes),'premium',exists(select 1 from public.pulse_premium where user_id=auth.uid() and expires_at>now()),'maximum',2147483648);
 end
$$;
create or replace function public.pulse_social_upload_access(p_bytes bigint) returns jsonb language sql stable security invoker set search_path='' as $$ select pulse_private.social_upload_access(p_bytes) $$;
revoke all on function pulse_private.social_upload_access(bigint),public.pulse_social_upload_access(bigint) from public,anon;
grant execute on function pulse_private.social_upload_access(bigint),public.pulse_social_upload_access(bigint) to authenticated;
-- Global Storage service limit is configured separately; Free hosting is capped at 50 MB.
update storage.buckets set file_size_limit=2147483648 where id='pulse-social';
-- TUS permission checks may occur before metadata exists. Final object metadata
-- and publishing both enforce the actual byte size, never client premium claims.
create or replace function pulse_private.social_storage_size() returns trigger language plpgsql security definer set search_path='' as $$
 begin
 if new.bucket_id='pulse-social' and auth.uid() is not null and new.metadata->>'size' is not null and not pulse_private.social_size_allowed((new.metadata->>'size')::bigint) then raise exception 'File exceeds account upload allowance'; end if;
 return new;
 end
$$;
revoke all on function pulse_private.social_storage_size() from public,anon,authenticated;
drop trigger if exists pulse_social_storage_size on storage.objects;
create trigger pulse_social_storage_size before insert or update of metadata on storage.objects for each row execute function pulse_private.social_storage_size();
create or replace function pulse_private.social_write(p_id uuid,p_kind text,p_body text,p_media jsonb,p_audience text,p_draft boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare m jsonb; mime text; total bigint; existing public.pulse_social_content;
begin
 perform pulse_private.social_rate('write',40,3600);
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,13));
 select * into existing from public.pulse_social_content where id=p_id for update;
 if found and (existing.author_id<>auth.uid() or existing.state='deleted') then raise exception 'Post unavailable'; end if;
 -- Retried publishing after an uncertain network response is idempotent. Editing is a separate RPC.
 if found and existing.state='published' then return p_id; end if;
 if p_id is null or p_kind is null or p_kind not in ('post','reel') or p_audience is null or p_audience not in ('public','followers') or p_draft is null or p_body is null or length(p_body)>4000 then raise exception 'Invalid post'; end if;
 if p_media is null or jsonb_typeof(p_media)<>'array' or jsonb_array_length(p_media)>8 then raise exception 'Choose up to 8 photos or one video'; end if;
 if p_kind='reel' and (jsonb_array_length(p_media)<>1 or p_media->0->>'kind' is distinct from 'video') then raise exception 'A Reel needs one video'; end if;
 if length(trim(p_body))=0 and jsonb_array_length(p_media)=0 then raise exception 'Add text or media'; end if;
 if exists(select 1 from jsonb_array_elements(p_media) x where x->>'kind'='video') and jsonb_array_length(p_media)<>1 then raise exception 'Upload one video per post'; end if;
 for m in select value from jsonb_array_elements(p_media) loop
 if m->>'kind' is null or m->>'kind' not in ('image','video') or m->>'path' is null or split_part(m->>'path','/',1)<>auth.uid()::text or split_part(m->>'path','/',2)<>p_id::text then raise exception 'Invalid media owner'; end if;
 select metadata->>'mimetype',(metadata->>'size')::bigint into mime,total from storage.objects where bucket_id='pulse-social' and name=m->>'path';
 if mime is null or mime is distinct from m->>'mime' then raise exception 'Upload media before publishing'; end if;
 if (m->>'kind'='image' and mime not in ('image/jpeg','image/png','image/webp')) or (m->>'kind'='video' and mime not in ('video/mp4','video/webm','video/quicktime')) then raise exception 'Unsupported media type'; end if;
 if not pulse_private.social_size_allowed(total) then raise exception 'Your file is over 500MB. Please upgrade to Premium to continue.'; end if;
 if m ? 'cover_path' and (split_part(m->>'cover_path','/',1)<>auth.uid()::text or split_part(m->>'cover_path','/',2)<>p_id::text or not exists(select 1 from storage.objects where bucket_id='pulse-social' and name=m->>'cover_path' and metadata->>'mimetype'='image/jpeg' and (metadata->>'size')::bigint between 1 and 10485760)) then raise exception 'Invalid video cover'; end if;
 end loop;
 insert into public.pulse_social_content(id,author_id,kind,body,media,audience,state) values(p_id,auth.uid(),p_kind,trim(p_body),p_media,p_audience,case when p_draft then 'draft' else 'published' end)
 on conflict(id) do update set body=excluded.body,media=excluded.media,audience=excluded.audience,kind=excluded.kind,state=excluded.state,
 created_at=case when excluded.state='published' then now() else pulse_social_content.created_at end;
 return p_id;
end
$$;
create or replace function pulse_private.social_media_read(p_path text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (
 split_part(p_path,'/',1)=auth.uid()::text or exists(select 1 from public.pulse_social_content c
 where (c.media @> jsonb_build_array(jsonb_build_object('path',p_path)) or c.media @> jsonb_build_array(jsonb_build_object('cover_path',p_path))) and pulse_private.social_read(c.id)) or
 exists(select 1 from public.pulse_social_accounts a where a.cover_path=p_path and not pulse_private.social_blocked(a.user_id)) or
 (pulse_private.is_admin() and exists(select 1 from public.pulse_social_content c join public.pulse_social_reports r on r.post_id=c.id where (c.media @> jsonb_build_array(jsonb_build_object('path',p_path)) or c.media @> jsonb_build_array(jsonb_build_object('cover_path',p_path))))))
$$;

create or replace function pulse_private.social_tags(p_body text) returns text[] language sql immutable set search_path='' as $$
 select coalesce(array_agg(tag order by first_seen),'{}'::text[]) from (
 select lower(m[1]) as tag,min(ord) first_seen from regexp_matches(p_body,'#([A-Za-z0-9_]{1,64})(?![A-Za-z0-9_])','g') with ordinality as matches(m,ord) group by lower(m[1]) order by min(ord) limit 20
 ) tags
$$;
revoke all on function pulse_private.social_tags(text) from public,anon;
grant execute on function pulse_private.social_tags(text) to authenticated;
alter table public.pulse_social_content add column if not exists hashtags text[] generated always as (pulse_private.social_tags(body)) stored;
create index if not exists pulse_social_hashtag_search on public.pulse_social_content using gin(hashtags) where state='published' and not hidden;
create or replace function pulse_private.social_tag_feed(p_tag text,p_kind text,p_before timestamptz,p_cursor uuid,p_limit int) returns jsonb language plpgsql stable security definer set search_path='' as $$
 begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_tag is null or p_tag !~ '^[A-Za-z0-9_]{1,64}$' or p_kind not in ('all','post','reel') or p_kind is null or p_limit is null or p_limit not between 1 and 20 or (p_before is null)<>(p_cursor is null) then raise exception 'Invalid hashtag search'; end if;
 return coalesce((select jsonb_agg(pulse_private.social_card(q.id) order by q.created_at desc,q.id desc) from (
 select c.id,c.created_at from public.pulse_social_content c where c.hashtags @> array[lower(p_tag)] and c.state='published' and not c.hidden and pulse_private.social_read(c.id)
 and (p_kind='all' or c.kind=p_kind) and (p_before is null or (c.created_at,c.id)<(p_before,p_cursor)) order by c.created_at desc,c.id desc limit p_limit
 ) q),'[]'::jsonb);
 end
$$;
create or replace function public.pulse_social_tag_feed(p_tag text,p_kind text,p_before timestamptz,p_cursor uuid,p_limit int) returns jsonb language sql stable security invoker set search_path='' as $$ select pulse_private.social_tag_feed(p_tag,p_kind,p_before,p_cursor,p_limit) $$;
revoke all on function pulse_private.social_tag_feed(text,text,timestamptz,uuid,int),public.pulse_social_tag_feed(text,text,timestamptz,uuid,int) from public,anon;
grant execute on function pulse_private.social_tag_feed(text,text,timestamptz,uuid,int),public.pulse_social_tag_feed(text,text,timestamptz,uuid,int) to authenticated;
commit;
