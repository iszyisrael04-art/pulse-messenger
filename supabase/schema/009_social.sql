-- Additive social foundation. Existing messaging tables and data are not changed.
begin;
create table public.pulse_social_accounts (
 user_id uuid primary key references public.pulse_profiles on delete cascade,
 cover_path text, is_private boolean not null default false, verified boolean not null default false
);
create table public.pulse_social_follows (
 follower_id uuid references public.pulse_profiles on delete cascade,
 creator_id uuid references public.pulse_profiles on delete cascade,
 state text not null check(state in ('pending','accepted')), created_at timestamptz not null default now(),
 primary key(follower_id,creator_id),check(follower_id<>creator_id)
);
create index social_follows_creator on public.pulse_social_follows(creator_id,state,follower_id);
create table public.pulse_social_content (
 id uuid primary key, author_id uuid not null references public.pulse_profiles on delete cascade,
 kind text not null check(kind in ('post','reel')), body text not null default '' check(length(body)<=4000),
 audience text not null default 'public' check(audience in ('public','followers')),
 state text not null check(state in ('draft','published','deleted')), hidden boolean not null default false,
 media jsonb not null default '[]'::jsonb check(jsonb_typeof(media)='array' and jsonb_array_length(media)<=8),
 created_at timestamptz not null default now(), edited_at timestamptz
);
create index social_content_page on public.pulse_social_content(created_at desc,id desc) where state='published' and not hidden;
create index social_content_author on public.pulse_social_content(author_id,created_at desc,id desc);
create index social_content_paths on public.pulse_social_content using gin(media);
create table public.pulse_social_likes (
 post_id uuid references public.pulse_social_content on delete cascade,user_id uuid references public.pulse_profiles on delete cascade,
 primary key(post_id,user_id)
);
create index social_likes_user on public.pulse_social_likes(user_id,post_id);
create table public.pulse_social_saves (
 post_id uuid references public.pulse_social_content on delete cascade,user_id uuid references public.pulse_profiles on delete cascade,
 primary key(post_id,user_id)
);
create index social_saves_user on public.pulse_social_saves(user_id,post_id);
create table public.pulse_social_reposts (
 post_id uuid references public.pulse_social_content on delete cascade,user_id uuid references public.pulse_profiles on delete cascade,
 created_at timestamptz not null default now(),primary key(post_id,user_id)
);
create index social_reposts_user on public.pulse_social_reposts(user_id,post_id);
create table public.pulse_social_comments (
 id uuid primary key,post_id uuid not null references public.pulse_social_content on delete cascade,
 author_id uuid not null references public.pulse_profiles on delete cascade,
 body text not null check(length(body) between 1 and 2000),created_at timestamptz not null default now(),deleted_at timestamptz
);
create index social_comments_page on public.pulse_social_comments(post_id,created_at desc,id desc);
create index social_comments_author on public.pulse_social_comments(author_id);
create table public.pulse_social_views (
 post_id uuid references public.pulse_social_content on delete cascade,user_id uuid references public.pulse_profiles on delete cascade,
 created_at timestamptz not null default now(),primary key(post_id,user_id)
);
create index social_views_user on public.pulse_social_views(user_id,post_id);
create table public.pulse_social_reports (
 id uuid primary key default gen_random_uuid(),post_id uuid not null references public.pulse_social_content on delete cascade,
 reporter_id uuid not null references public.pulse_profiles on delete cascade,reason text not null check(length(reason) between 1 and 1000),
 state text not null default 'open' check(state in ('open','reviewed')),created_at timestamptz not null default now(),unique(post_id,reporter_id)
);
create index social_reports_reporter on public.pulse_social_reports(reporter_id);
create table pulse_private.social_limits (
 user_id uuid references public.pulse_profiles on delete cascade,action text,started_at timestamptz not null,n int not null,primary key(user_id,action)
);
alter table pulse_private.social_limits enable row level security;
create table pulse_private.social_shares (
 id uuid primary key references public.pulse_messages on delete cascade,post_id uuid references public.pulse_social_content on delete cascade,
 user_id uuid references public.pulse_profiles on delete cascade
);
alter table pulse_private.social_shares enable row level security;
create index social_shares_post on pulse_private.social_shares(post_id);
create index social_shares_user on pulse_private.social_shares(user_id);
create table pulse_private.social_moderation (
 id bigint generated always as identity primary key,post_id uuid references public.pulse_social_content on delete cascade,
 admin_id uuid references public.pulse_profiles,hidden boolean,created_at timestamptz not null default now()
);
alter table pulse_private.social_moderation enable row level security;
create index social_moderation_post on pulse_private.social_moderation(post_id);
create index social_moderation_admin on pulse_private.social_moderation(admin_id);

create function pulse_private.social_blocked(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is null or exists(select 1 from public.pulse_blocks where
 (user_id=auth.uid() and blocked_id=p_user) or (user_id=p_user and blocked_id=auth.uid()))
$$;
create function pulse_private.social_follows(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not pulse_private.social_blocked(p_user) and exists(select 1 from public.pulse_social_follows
 where follower_id=auth.uid() and creator_id=p_user and state='accepted')
$$;
create function pulse_private.social_creator_read(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (p_user=auth.uid() or (not pulse_private.social_blocked(p_user) and
 (not coalesce((select is_private from public.pulse_social_accounts where user_id=p_user),false) or pulse_private.social_follows(p_user))))
$$;
revoke all on function pulse_private.social_creator_read(uuid) from public,anon;
grant execute on function pulse_private.social_creator_read(uuid) to authenticated;
create function pulse_private.social_read(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.pulse_social_content c where c.id=p_id and c.state<>'deleted' and
 (c.author_id=auth.uid() or (c.state='published' and not c.hidden and not pulse_private.social_blocked(c.author_id) and
 ((c.audience='public' and not coalesce((select is_private from public.pulse_social_accounts where user_id=c.author_id),false)) or pulse_private.social_follows(c.author_id)))))
$$;
create function pulse_private.social_media_read(p_path text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (
 split_part(p_path,'/',1)=auth.uid()::text or exists(select 1 from public.pulse_social_content c
 where c.media @> jsonb_build_array(jsonb_build_object('path',p_path)) and pulse_private.social_read(c.id)) or
 exists(select 1 from public.pulse_social_accounts a where a.cover_path=p_path and not pulse_private.social_blocked(a.user_id)) or
 (pulse_private.is_admin() and exists(select 1 from public.pulse_social_content c join public.pulse_social_reports r on r.post_id=c.id where c.media @> jsonb_build_array(jsonb_build_object('path',p_path)))))
$$;
create function pulse_private.social_rate(p_action text,p_max int,p_seconds int) returns void language plpgsql security definer set search_path='' as $$
 declare attempts int;
 begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 insert into pulse_private.social_limits(user_id,action,started_at,n) values(auth.uid(),p_action,now(),1)
 on conflict(user_id,action) do update set
 n=case when social_limits.started_at<now()-make_interval(secs=>p_seconds) then 1 else social_limits.n+1 end,
 started_at=case when social_limits.started_at<now()-make_interval(secs=>p_seconds) then now() else social_limits.started_at end returning n into attempts;
 if attempts>p_max then raise exception 'Too many actions. Please wait and retry'; end if;
 end
$$;
alter table public.pulse_social_accounts enable row level security;
create policy social_accounts_read on public.pulse_social_accounts for select to authenticated using(not pulse_private.social_blocked(user_id));
revoke all on public.pulse_social_accounts from anon,authenticated;
grant select on public.pulse_social_accounts to authenticated;
alter table public.pulse_social_content enable row level security;
create policy social_content_read on public.pulse_social_content for select to authenticated using(pulse_private.social_read(id));
revoke all on public.pulse_social_content from anon,authenticated;
grant select on public.pulse_social_content to authenticated;
alter table public.pulse_social_likes enable row level security;
create policy social_likes_read on public.pulse_social_likes for select to authenticated using(pulse_private.social_read(post_id));
revoke all on public.pulse_social_likes from anon,authenticated;
grant select on public.pulse_social_likes to authenticated;
alter table public.pulse_social_saves enable row level security;
create policy social_saves_read on public.pulse_social_saves for select to authenticated using(user_id=(select auth.uid()) and pulse_private.social_read(post_id));
revoke all on public.pulse_social_saves from anon,authenticated;
grant select on public.pulse_social_saves to authenticated;
alter table public.pulse_social_reposts enable row level security;
create policy social_reposts_read on public.pulse_social_reposts for select to authenticated using(pulse_private.social_read(post_id) and pulse_private.social_creator_read(user_id));
revoke all on public.pulse_social_reposts from anon,authenticated;
grant select on public.pulse_social_reposts to authenticated;
alter table public.pulse_social_comments enable row level security;
create policy social_comments_read on public.pulse_social_comments for select to authenticated using(deleted_at is null and not pulse_private.social_blocked(author_id) and pulse_private.social_read(post_id));
revoke all on public.pulse_social_comments from anon,authenticated;
grant select on public.pulse_social_comments to authenticated;
alter table public.pulse_social_views enable row level security;
create policy social_views_read on public.pulse_social_views for select to authenticated using(user_id=(select auth.uid()) and pulse_private.social_read(post_id));
revoke all on public.pulse_social_views from anon,authenticated;
grant select on public.pulse_social_views to authenticated;
alter table public.pulse_social_reports enable row level security;
create policy social_reports_read on public.pulse_social_reports for select to authenticated using(reporter_id=(select auth.uid()) or pulse_private.is_admin());
revoke all on public.pulse_social_reports from anon,authenticated;
grant select on public.pulse_social_reports to authenticated;
alter table public.pulse_social_follows enable row level security;
revoke all on public.pulse_social_follows from anon,authenticated;
-- Follow identities are private; expose only scoped projections through RPCs.
create policy social_follows_own on public.pulse_social_follows for select to authenticated using(follower_id=(select auth.uid()) or creator_id=(select auth.uid()));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('pulse-social','pulse-social',false,41943040,
 array['image/jpeg','image/png','image/webp','video/mp4','video/webm','video/quicktime']);
create policy social_upload on storage.objects for insert to authenticated with check(bucket_id='pulse-social' and split_part(name,'/',1)=(select auth.uid())::text);
create policy social_download on storage.objects for select to authenticated using(bucket_id='pulse-social' and pulse_private.social_media_read(name));
create policy social_remove on storage.objects for delete to authenticated using(bucket_id='pulse-social' and split_part(name,'/',1)=(select auth.uid())::text);
create function pulse_private.social_write(p_id uuid,p_kind text,p_body text,p_media jsonb,p_audience text,p_draft boolean) returns uuid language plpgsql security definer set search_path='' as $$
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
 if total is null or total<=0 or total>(case when m->>'kind'='image' then 10485760 else 41943040 end) then raise exception 'Photo limit 10 MB; video limit 40 MB'; end if;
 end loop;
 insert into public.pulse_social_content(id,author_id,kind,body,media,audience,state) values(p_id,auth.uid(),p_kind,trim(p_body),p_media,p_audience,case when p_draft then 'draft' else 'published' end)
 on conflict(id) do update set body=excluded.body,media=excluded.media,audience=excluded.audience,kind=excluded.kind,state=excluded.state,
 created_at=case when excluded.state='published' then now() else pulse_social_content.created_at end;
 return p_id;
end
$$;
create function public.pulse_social_write(p_id uuid,p_kind text,p_body text,p_media jsonb,p_audience text,p_draft boolean) returns uuid language sql security invoker set search_path='' as $$ select pulse_private.social_write(p_id,p_kind,p_body,p_media,p_audience,p_draft) $$;
create function pulse_private.social_edit(p_id uuid,p_body text,p_delete boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform pulse_private.social_rate('edit',60,3600);
 if p_body is null or length(p_body)>4000 or p_delete is null then raise exception 'Invalid edit'; end if;
 update public.pulse_social_content set body=case when p_delete then body else trim(p_body) end,
 state=case when p_delete then 'deleted' else state end,edited_at=now()
 where id=p_id and author_id=auth.uid() and state<>'deleted' and (p_delete or length(trim(p_body))>0 or jsonb_array_length(media)>0);
 if not found then raise exception 'Post unavailable or empty'; end if;
end
$$;
create function public.pulse_social_edit(p_id uuid,p_body text,p_delete boolean) returns void language sql security invoker set search_path='' as $$ select pulse_private.social_edit(p_id,p_body,p_delete) $$;
create function pulse_private.social_follow(p_user uuid,p_follow boolean) returns text language plpgsql security definer set search_path='' as $$
declare result text;
begin
 perform pulse_private.social_rate('follow',60,60);
 if p_user=auth.uid() or p_user is null or p_follow is null or pulse_private.social_blocked(p_user) then raise exception 'Creator unavailable'; end if;
 if not exists(select 1 from public.pulse_profiles where id=p_user) then raise exception 'Creator unavailable'; end if;
 if not p_follow then delete from public.pulse_social_follows where follower_id=auth.uid() and creator_id=p_user; return 'none'; end if;
 select case when coalesce((select is_private from public.pulse_social_accounts where user_id=p_user),false) then 'pending' else 'accepted' end into result;
 insert into public.pulse_social_follows(follower_id,creator_id,state) values(auth.uid(),p_user,result) on conflict do nothing;
 select state into result from public.pulse_social_follows where follower_id=auth.uid() and creator_id=p_user;
 return result;
end
$$;
create function public.pulse_social_follow(p_user uuid,p_follow boolean) returns text language sql security invoker set search_path='' as $$ select pulse_private.social_follow(p_user,p_follow) $$;
create function pulse_private.social_approve(p_user uuid,p_accept boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform pulse_private.social_rate('approve',120,60);
 if p_accept is null or pulse_private.social_blocked(p_user) then raise exception 'Request unavailable'; end if;
 if p_accept then update public.pulse_social_follows set state='accepted' where creator_id=auth.uid() and follower_id=p_user and state='pending';
 else delete from public.pulse_social_follows where creator_id=auth.uid() and follower_id=p_user and state='pending'; end if;
end
$$;
create function public.pulse_social_approve(p_user uuid,p_accept boolean) returns void language sql security invoker set search_path='' as $$ select pulse_private.social_approve(p_user,p_accept) $$;
create function pulse_private.social_account(p_private boolean,p_cover text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform pulse_private.social_rate('account',30,3600);
 if p_private is null then raise exception 'Invalid privacy'; end if;
 if p_cover is not null and (split_part(p_cover,'/',1)<>auth.uid()::text or split_part(p_cover,'/',2)<>'cover' or not exists(select 1 from storage.objects where bucket_id='pulse-social' and name=p_cover and metadata->>'mimetype' in ('image/jpeg','image/png','image/webp') and (metadata->>'size')::bigint<=10485760)) then raise exception 'Invalid cover photo'; end if;
 insert into public.pulse_social_accounts(user_id,is_private,cover_path) values(auth.uid(),p_private,p_cover)
 on conflict(user_id) do update set is_private=excluded.is_private,cover_path=excluded.cover_path;
end
$$;
create function public.pulse_social_account(p_private boolean,p_cover text) returns void language sql security invoker set search_path='' as $$ select pulse_private.social_account(p_private,p_cover) $$;
create function pulse_private.social_action(p_id uuid,p_action text,p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform pulse_private.social_rate('engagement',300,60);
 if p_enabled is null or not pulse_private.social_read(p_id) or not exists(select 1 from public.pulse_social_content where id=p_id and state='published' and not hidden) then raise exception 'Post unavailable'; end if;
 if p_action='like' then
 if p_enabled then insert into public.pulse_social_likes values(p_id,auth.uid()) on conflict do nothing; else delete from public.pulse_social_likes where post_id=p_id and user_id=auth.uid(); end if;
 elsif p_action='save' then
 if p_enabled then insert into public.pulse_social_saves values(p_id,auth.uid()) on conflict do nothing; else delete from public.pulse_social_saves where post_id=p_id and user_id=auth.uid(); end if;
 elsif p_action='repost' then
 if p_enabled then insert into public.pulse_social_reposts(post_id,user_id) values(p_id,auth.uid()) on conflict do nothing; else delete from public.pulse_social_reposts where post_id=p_id and user_id=auth.uid(); end if;
 elsif p_action='view' then
 if (select author_id from public.pulse_social_content where id=p_id)<>auth.uid() then insert into public.pulse_social_views(post_id,user_id) values(p_id,auth.uid()) on conflict do nothing; end if;
 else raise exception 'Unknown action'; end if;
end
$$;
create function public.pulse_social_action(p_id uuid,p_action text,p_enabled boolean) returns void language sql security invoker set search_path='' as $$ select pulse_private.social_action(p_id,p_action,p_enabled) $$;
create function pulse_private.social_comment(p_id uuid,p_post uuid,p_body text,p_delete boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform pulse_private.social_rate('comment',40,60);
 if p_delete then
 update public.pulse_social_comments set deleted_at=now() where id=p_id and (author_id=auth.uid() or exists(select 1 from public.pulse_social_content where id=post_id and author_id=auth.uid()) or pulse_private.is_admin());
 if not found then raise exception 'Comment unavailable'; end if; return;
 end if;
 if p_delete is null or p_body is null or length(trim(p_body)) not between 1 and 2000 or not pulse_private.social_read(p_post) or not exists(select 1 from public.pulse_social_content where id=p_post and state='published' and not hidden) then raise exception 'Comment unavailable'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,14));
 if exists(select 1 from public.pulse_social_comments where id=p_id and (author_id<>auth.uid() or post_id<>p_post)) then raise exception 'Comment unavailable'; end if;
 insert into public.pulse_social_comments(id,post_id,author_id,body) values(p_id,p_post,auth.uid(),trim(p_body)) on conflict(id) do nothing;
end
$$;
create function public.pulse_social_comment(p_id uuid,p_post uuid,p_body text,p_delete boolean) returns void language sql security invoker set search_path='' as $$ select pulse_private.social_comment(p_id,p_post,p_body,p_delete) $$;
create function pulse_private.social_report(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform pulse_private.social_rate('report',20,3600);
 if not pulse_private.social_read(p_id) or p_reason is null or length(trim(p_reason)) not between 1 and 1000 then raise exception 'Report unavailable'; end if;
 insert into public.pulse_social_reports(post_id,reporter_id,reason) values(p_id,auth.uid(),trim(p_reason)) on conflict(post_id,reporter_id) do nothing;
end
$$;
create function public.pulse_social_report(p_id uuid,p_reason text) returns void language sql security invoker set search_path='' as $$ select pulse_private.social_report(p_id,p_reason) $$;
create function pulse_private.social_moderate(p_id uuid,p_hide boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if not pulse_private.is_admin() or p_hide is null then raise exception 'Administrator required'; end if;
 update public.pulse_social_content set hidden=p_hide where id=p_id;
 if not found then raise exception 'Post unavailable'; end if;
 update public.pulse_social_reports set state='reviewed' where post_id=p_id;
 insert into pulse_private.social_moderation(post_id,admin_id,hidden) values(p_id,auth.uid(),p_hide);
end
$$;
create function public.pulse_social_moderate(p_id uuid,p_hide boolean) returns void language sql security invoker set search_path='' as $$ select pulse_private.social_moderate(p_id,p_hide) $$;
create function pulse_private.social_share(p_post uuid,p_chat uuid,p_message uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid;
begin
 perform pulse_private.social_rate('share',40,60);
 if not pulse_private.social_read(p_post) or not exists(select 1 from public.pulse_social_content where id=p_post and state='published' and not hidden) then raise exception 'Post unavailable'; end if;
 if exists(select 1 from public.pulse_messages where id=p_message and (sender_id<>auth.uid() or chat_id<>p_chat or body not like '%pulse:post:'||p_post::text)) then raise exception 'Share unavailable'; end if;
 result=pulse_private.send_message(p_message,p_chat,'Shared a Pulse post · pulse:post:'||p_post::text,null,null);
 insert into pulse_private.social_shares(id,post_id,user_id) values(result,p_post,auth.uid()) on conflict do nothing;
 return result;
end
$$;
create function public.pulse_social_share(p_post uuid,p_chat uuid,p_message uuid) returns uuid language sql security invoker set search_path='' as $$ select pulse_private.social_share(p_post,p_chat,p_message) $$;
create function pulse_private.social_card(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
select to_jsonb(c)||jsonb_build_object(
 'author',(select jsonb_build_object('id',p.id,'username',p.username,'display_name',p.display_name,'bio',p.bio,'avatar_path',p.avatar_path,
 'verified',coalesce(a.verified,false),'premium',exists(select 1 from public.pulse_premium where user_id=p.id and expires_at>now())) from public.pulse_profiles p left join public.pulse_social_accounts a on a.user_id=p.id where p.id=c.author_id),
 'likes',(select count(*) from public.pulse_social_likes where post_id=c.id),
 'comments',(select count(*) from public.pulse_social_comments where post_id=c.id and deleted_at is null and not pulse_private.social_blocked(author_id)),
 'views',(select count(*) from public.pulse_social_views where post_id=c.id),
 'shares',(select count(*) from pulse_private.social_shares where post_id=c.id),
 'reposts',(select count(*) from public.pulse_social_reposts where post_id=c.id),
 'liked',exists(select 1 from public.pulse_social_likes where post_id=c.id and user_id=auth.uid()),
 'saved',exists(select 1 from public.pulse_social_saves where post_id=c.id and user_id=auth.uid()),
 'reposted',exists(select 1 from public.pulse_social_reposts where post_id=c.id and user_id=auth.uid()),
 'follow_state',coalesce((select state from public.pulse_social_follows where follower_id=auth.uid() and creator_id=c.author_id),'none'))
 from public.pulse_social_content c where c.id=p_id and pulse_private.social_read(c.id)
$$;
create function pulse_private.social_feed(p_mode text,p_author uuid,p_kind text,p_before timestamptz,p_cursor uuid,p_limit int) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_mode is null or p_mode not in ('discovery','following','saved','drafts','profile') or p_kind is null or p_kind not in ('all','post','reel') or p_limit is null or p_limit not between 1 and 20 then raise exception 'Invalid feed'; end if;
 if (p_before is null)<>(p_cursor is null) then raise exception 'Invalid cursor'; end if;
 if p_mode='profile' and not pulse_private.social_creator_read(p_author) then return '[]'::jsonb; end if;
 return coalesce((select jsonb_agg(pulse_private.social_card(q.id) order by q.created_at desc,q.id desc) from (
 select c.id,c.created_at from public.pulse_social_content c where pulse_private.social_read(c.id)
 and (p_kind='all' or c.kind=p_kind)
 and (p_mode='drafts' and c.state='draft' and c.author_id=auth.uid() or p_mode<>'drafts' and c.state='published' and not c.hidden)
 and (p_mode<>'profile' or (c.author_id=p_author or exists(select 1 from public.pulse_social_reposts where post_id=c.id and user_id=p_author)))
 and (p_mode<>'following' or c.author_id=auth.uid() or pulse_private.social_follows(c.author_id))
 and (p_mode<>'saved' or exists(select 1 from public.pulse_social_saves where post_id=c.id and user_id=auth.uid()))
 and (p_before is null or (c.created_at,c.id)<(p_before,p_cursor)) order by c.created_at desc,c.id desc limit p_limit
 ) q),'[]'::jsonb);
end
$$;
create function public.pulse_social_feed(p_mode text,p_author uuid,p_kind text,p_before timestamptz,p_cursor uuid,p_limit int) returns jsonb language sql stable security invoker set search_path='' as $$ select pulse_private.social_feed(p_mode,p_author,p_kind,p_before,p_cursor,p_limit) $$;
create function pulse_private.social_post(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
select pulse_private.social_card(p_id)
$$;
create function public.pulse_social_post(p_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select pulse_private.social_post(p_id) $$;
create function pulse_private.social_comments(p_post uuid,p_before timestamptz,p_cursor uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not pulse_private.social_read(p_post) then raise exception 'Post unavailable'; end if;
 if (p_before is null)<>(p_cursor is null) then raise exception 'Invalid cursor'; end if;
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id desc) from (
 select c.id,c.author_id,c.body,c.created_at,p.display_name,p.username,p.avatar_path from public.pulse_social_comments c join public.pulse_profiles p on p.id=c.author_id
 where c.post_id=p_post and c.deleted_at is null and not pulse_private.social_blocked(c.author_id) and (p_before is null or (c.created_at,c.id)<(p_before,p_cursor))
 order by c.created_at desc,c.id desc limit 30) q),'[]'::jsonb);
end
$$;
create function public.pulse_social_comments(p_post uuid,p_before timestamptz,p_cursor uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select pulse_private.social_comments(p_post,p_before,p_cursor) $$;
create function pulse_private.social_profile(p_user uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if pulse_private.social_blocked(p_user) then raise exception 'Profile unavailable'; end if;
 select jsonb_build_object('id',p.id,'username',p.username,'display_name',p.display_name,'bio',p.bio,'avatar_path',p.avatar_path,
 'cover_path',a.cover_path,'is_private',coalesce(a.is_private,false),'verified',coalesce(a.verified,false),
 'premium',exists(select 1 from public.pulse_premium where user_id=p.id and expires_at>now()),
 'follow_state',coalesce((select state from public.pulse_social_follows where follower_id=auth.uid() and creator_id=p.id),'none'),
 'followers',(select count(*) from public.pulse_social_follows where creator_id=p.id and state='accepted'),
 'following',(select count(*) from public.pulse_social_follows where follower_id=p.id and state='accepted'),
 'analytics',case when p.id=auth.uid() then jsonb_build_object(
 'posts',(select count(*) from public.pulse_social_content where author_id=p.id and state='published' and kind='post'),
 'reels',(select count(*) from public.pulse_social_content where author_id=p.id and state='published' and kind='reel'),
 'views',(select count(*) from public.pulse_social_views v join public.pulse_social_content c on c.id=v.post_id where c.author_id=p.id and c.state='published'),
 'likes',(select count(*) from public.pulse_social_likes l join public.pulse_social_content c on c.id=l.post_id where c.author_id=p.id and c.state='published'),
 'comments',(select count(*) from public.pulse_social_comments m join public.pulse_social_content c on c.id=m.post_id where c.author_id=p.id and c.state='published' and m.deleted_at is null)) else null end)
 into result from public.pulse_profiles p left join public.pulse_social_accounts a on a.user_id=p.id where p.id=p_user;
 return result;
end
$$;
create function public.pulse_social_profile(p_user uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select pulse_private.social_profile(p_user) $$;
create function pulse_private.social_requests() returns jsonb language sql stable security definer set search_path='' as $$
select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'username',p.username,'display_name',p.display_name,'avatar_path',p.avatar_path)),'[]'::jsonb) from (select follower_id from public.pulse_social_follows where creator_id=auth.uid() and state='pending' order by created_at desc limit 50) f join public.pulse_profiles p on p.id=f.follower_id where not pulse_private.social_blocked(p.id)
$$;
create function public.pulse_social_requests() returns jsonb language sql stable security invoker set search_path='' as $$ select pulse_private.social_requests() $$;
revoke all on function pulse_private.social_write(uuid,text,text,jsonb,text,boolean) from public,anon,authenticated;
revoke all on function public.pulse_social_write(uuid,text,text,jsonb,text,boolean) from public,anon;
grant execute on function pulse_private.social_write(uuid,text,text,jsonb,text,boolean),public.pulse_social_write(uuid,text,text,jsonb,text,boolean) to authenticated;
revoke all on function pulse_private.social_edit(uuid,text,boolean) from public,anon,authenticated;
revoke all on function public.pulse_social_edit(uuid,text,boolean) from public,anon;
grant execute on function pulse_private.social_edit(uuid,text,boolean),public.pulse_social_edit(uuid,text,boolean) to authenticated;
revoke all on function pulse_private.social_follow(uuid,boolean) from public,anon,authenticated;
revoke all on function public.pulse_social_follow(uuid,boolean) from public,anon;
grant execute on function pulse_private.social_follow(uuid,boolean),public.pulse_social_follow(uuid,boolean) to authenticated;
revoke all on function pulse_private.social_approve(uuid,boolean) from public,anon,authenticated;
revoke all on function public.pulse_social_approve(uuid,boolean) from public,anon;
grant execute on function pulse_private.social_approve(uuid,boolean),public.pulse_social_approve(uuid,boolean) to authenticated;
revoke all on function pulse_private.social_account(boolean,text) from public,anon,authenticated;
revoke all on function public.pulse_social_account(boolean,text) from public,anon;
grant execute on function pulse_private.social_account(boolean,text),public.pulse_social_account(boolean,text) to authenticated;
revoke all on function pulse_private.social_action(uuid,text,boolean) from public,anon,authenticated;
revoke all on function public.pulse_social_action(uuid,text,boolean) from public,anon;
grant execute on function pulse_private.social_action(uuid,text,boolean),public.pulse_social_action(uuid,text,boolean) to authenticated;
revoke all on function pulse_private.social_comment(uuid,uuid,text,boolean) from public,anon,authenticated;
revoke all on function public.pulse_social_comment(uuid,uuid,text,boolean) from public,anon;
grant execute on function pulse_private.social_comment(uuid,uuid,text,boolean),public.pulse_social_comment(uuid,uuid,text,boolean) to authenticated;
revoke all on function pulse_private.social_report(uuid,text) from public,anon,authenticated;
revoke all on function public.pulse_social_report(uuid,text) from public,anon;
grant execute on function pulse_private.social_report(uuid,text),public.pulse_social_report(uuid,text) to authenticated;
revoke all on function pulse_private.social_moderate(uuid,boolean) from public,anon,authenticated;
revoke all on function public.pulse_social_moderate(uuid,boolean) from public,anon;
grant execute on function pulse_private.social_moderate(uuid,boolean),public.pulse_social_moderate(uuid,boolean) to authenticated;
revoke all on function pulse_private.social_share(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.pulse_social_share(uuid,uuid,uuid) from public,anon;
grant execute on function pulse_private.social_share(uuid,uuid,uuid),public.pulse_social_share(uuid,uuid,uuid) to authenticated;
revoke all on function pulse_private.social_card(uuid) from public,anon,authenticated;
revoke all on function pulse_private.social_feed(text,uuid,text,timestamptz,uuid,int) from public,anon,authenticated;
revoke all on function public.pulse_social_feed(text,uuid,text,timestamptz,uuid,int) from public,anon;
grant execute on function pulse_private.social_feed(text,uuid,text,timestamptz,uuid,int),public.pulse_social_feed(text,uuid,text,timestamptz,uuid,int) to authenticated;
revoke all on function pulse_private.social_post(uuid) from public,anon,authenticated;
revoke all on function public.pulse_social_post(uuid) from public,anon;
grant execute on function pulse_private.social_post(uuid),public.pulse_social_post(uuid) to authenticated;
revoke all on function pulse_private.social_comments(uuid,timestamptz,uuid) from public,anon,authenticated;
revoke all on function public.pulse_social_comments(uuid,timestamptz,uuid) from public,anon;
grant execute on function pulse_private.social_comments(uuid,timestamptz,uuid),public.pulse_social_comments(uuid,timestamptz,uuid) to authenticated;
revoke all on function pulse_private.social_profile(uuid) from public,anon,authenticated;
revoke all on function public.pulse_social_profile(uuid) from public,anon;
grant execute on function pulse_private.social_profile(uuid),public.pulse_social_profile(uuid) to authenticated;
revoke all on function pulse_private.social_requests() from public,anon,authenticated;
revoke all on function public.pulse_social_requests() from public,anon;
grant execute on function pulse_private.social_requests(),public.pulse_social_requests() to authenticated;
revoke all on function pulse_private.social_blocked(uuid) from public,anon,authenticated;
grant execute on function pulse_private.social_blocked(uuid) to authenticated;
revoke all on function pulse_private.social_follows(uuid) from public,anon,authenticated;
grant execute on function pulse_private.social_follows(uuid) to authenticated;
revoke all on function pulse_private.social_read(uuid) from public,anon,authenticated;
grant execute on function pulse_private.social_read(uuid) to authenticated;
revoke all on function pulse_private.social_media_read(text) from public,anon,authenticated;
grant execute on function pulse_private.social_media_read(text) to authenticated;
revoke all on function pulse_private.social_rate(text,int,int) from public,anon,authenticated;
create function pulse_private.social_review(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
 begin
 if not pulse_private.is_admin() then raise exception 'Administrator required'; end if;
 if not exists(select 1 from public.pulse_social_reports where post_id=p_id) then raise exception 'Report unavailable'; end if;
 return (select jsonb_build_object('id',c.id,'body',c.body,'media',c.media,'hidden',c.hidden,'state',c.state,'author_id',c.author_id) from public.pulse_social_content c where c.id=p_id);
 end
$$;
create function public.pulse_social_review(p_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$ select pulse_private.social_review(p_id) $$;
revoke all on function pulse_private.social_review(uuid),public.pulse_social_review(uuid) from public,anon;
grant execute on function pulse_private.social_review(uuid),public.pulse_social_review(uuid) to authenticated;
commit;
