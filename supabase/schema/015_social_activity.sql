begin;
-- Use actual follow creation time, including multiple actions in one transaction.
alter table public.pulse_social_follows alter column created_at set default clock_timestamp();
create table pulse_private.activity_events (
 id uuid primary key default gen_random_uuid(),
 recipient_id uuid not null references public.pulse_profiles on delete cascade,
 actor_id uuid not null references public.pulse_profiles on delete cascade,
 kind text not null check(kind in ('follow','follow_request','like','comment','mention_post','mention_comment','publish')),
 post_id uuid references public.pulse_social_content on delete cascade,
 reference_id uuid not null,created_at timestamptz not null default clock_timestamp(),
 unique(recipient_id,actor_id,kind,reference_id)
);
create index activity_recipient_page on pulse_private.activity_events(recipient_id,created_at desc,id desc);
create index activity_actor_page on pulse_private.activity_events(actor_id,created_at desc,id desc);
create index activity_reference on pulse_private.activity_events(reference_id,kind);
create index activity_post on pulse_private.activity_events(post_id);
create table pulse_private.activity_settings (
 user_id uuid primary key references public.pulse_profiles on delete cascade,
 mentions boolean not null default true,follows boolean not null default true,
 likes boolean not null default true,comments boolean not null default true,following boolean not null default true,
 seen_until timestamptz not null default '1970-01-01'
);
create table pulse_private.activity_reads (
 user_id uuid references public.pulse_profiles on delete cascade,
 event_id uuid references pulse_private.activity_events on delete cascade,
 primary key(user_id,event_id)
);
create index activity_reads_event on pulse_private.activity_reads(event_id);
alter table pulse_private.activity_events enable row level security;
alter table pulse_private.activity_settings enable row level security;
alter table pulse_private.activity_reads enable row level security;
revoke all on pulse_private.activity_events,pulse_private.activity_settings,pulse_private.activity_reads from public,anon,authenticated;

create function pulse_private.mentioned_users(p_body text) returns uuid[] language sql stable security definer set search_path='' as $$
 select coalesce(array_agg(p.id),'{}'::uuid[]) from public.pulse_profiles p join
 (select distinct m[2] username from regexp_matches(lower(p_body),'(^|[^a-z0-9_@])@([a-z][a-z0-9_]{2,23})(?![a-z0-9_])','g') m limit 20) tags
 on p.username=tags.username
$$;
create function pulse_private.activity_content_trigger() returns trigger language plpgsql security definer set search_path='' as $$
declare targets uuid[];
begin
 if new.state='published' then
   if TG_OP='INSERT' or old.state<>'published' then
     -- One publication event, queried by followers: no follower fan-out on posting.
     insert into pulse_private.activity_events(recipient_id,actor_id,kind,post_id,reference_id)
     values(new.author_id,new.author_id,'publish',new.id,new.id) on conflict do nothing;
   end if;
   targets=pulse_private.mentioned_users(new.body);
   delete from pulse_private.activity_events where kind='mention_post' and reference_id=new.id and not(recipient_id=any(targets));
   insert into pulse_private.activity_events(recipient_id,actor_id,kind,post_id,reference_id)
   select u,new.author_id,'mention_post',new.id,new.id from unnest(targets) u where u<>new.author_id on conflict do nothing;
 else delete from pulse_private.activity_events where kind='mention_post' and reference_id=new.id;
 end if;
 return new;
end $$;
create trigger pulse_activity_content after insert or update on public.pulse_social_content for each row execute function pulse_private.activity_content_trigger();
create function pulse_private.activity_follow_trigger() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into pulse_private.activity_events(recipient_id,actor_id,kind,reference_id)
 values(new.creator_id,new.follower_id,case when new.state='accepted' then 'follow' else 'follow_request' end,new.creator_id) on conflict do nothing;
 return new;
end $$;
create trigger pulse_activity_follow after insert or update of state on public.pulse_social_follows for each row execute function pulse_private.activity_follow_trigger();
create function pulse_private.activity_like_trigger() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into pulse_private.activity_events(recipient_id,actor_id,kind,post_id,reference_id)
 select author_id,new.user_id,'like',id,id from public.pulse_social_content where id=new.post_id and author_id<>new.user_id on conflict do nothing;
 return new;
end $$;
create trigger pulse_activity_like after insert on public.pulse_social_likes for each row execute function pulse_private.activity_like_trigger();
create function pulse_private.activity_comment_trigger() returns trigger language plpgsql security definer set search_path='' as $$
declare targets uuid[];
begin
 if new.deleted_at is null then
   insert into pulse_private.activity_events(recipient_id,actor_id,kind,post_id,reference_id)
   select author_id,new.author_id,'comment',id,new.id from public.pulse_social_content where id=new.post_id and author_id<>new.author_id on conflict do nothing;
   targets=pulse_private.mentioned_users(new.body);
   delete from pulse_private.activity_events where kind='mention_comment' and reference_id=new.id and not(recipient_id=any(targets));
   insert into pulse_private.activity_events(recipient_id,actor_id,kind,post_id,reference_id)
   select u,new.author_id,'mention_comment',new.post_id,new.id from unnest(targets) u where u<>new.author_id on conflict do nothing;
 else delete from pulse_private.activity_events where kind='mention_comment' and reference_id=new.id;
 end if;
 return new;
end $$;
create trigger pulse_activity_comment after insert or update on public.pulse_social_comments for each row execute function pulse_private.activity_comment_trigger();
revoke all on function pulse_private.mentioned_users(text),pulse_private.activity_content_trigger(),pulse_private.activity_follow_trigger(),pulse_private.activity_like_trigger(),pulse_private.activity_comment_trigger() from public,anon,authenticated;

create function pulse_private.activity_visible(p_event uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare e pulse_private.activity_events; s pulse_private.activity_settings;
begin
 if auth.uid() is null then return false;end if;
 select * into e from pulse_private.activity_events where id=p_event;
 if not found or e.actor_id=auth.uid() or pulse_private.social_blocked(e.actor_id) then return false;end if;
 select * into s from pulse_private.activity_settings where user_id=auth.uid();
 if e.kind='publish' then
   if not coalesce(s.following,true) or not exists(select 1 from public.pulse_social_follows where follower_id=auth.uid() and creator_id=e.actor_id and state='accepted' and created_at<=e.created_at) then return false;end if;
 elsif e.recipient_id<>auth.uid() then return false;
 elsif e.kind in ('mention_post','mention_comment') and not coalesce(s.mentions,true) then return false;
 elsif e.kind in ('follow','follow_request') and not coalesce(s.follows,true) then return false;
 elsif e.kind='like' and not coalesce(s.likes,true) then return false;
 elsif e.kind='comment' and not coalesce(s.comments,true) then return false;
 end if;
 if e.post_id is not null and (not pulse_private.social_read(e.post_id) or not exists(select 1 from public.pulse_social_content where id=e.post_id and state='published' and not hidden)) then return false;end if;
 if e.kind in ('follow','follow_request') and not exists(select 1 from public.pulse_social_follows where follower_id=e.actor_id and creator_id=auth.uid() and state=case when e.kind='follow' then 'accepted' else 'pending' end) then return false;end if;
 if e.kind='like' and not exists(select 1 from public.pulse_social_likes where user_id=e.actor_id and post_id=e.post_id) then return false;end if;
 if e.kind in ('comment','mention_comment') and not exists(select 1 from public.pulse_social_comments where id=e.reference_id and deleted_at is null) then return false;end if;
 return true;
end $$;
revoke all on function pulse_private.activity_visible(uuid) from public,anon,authenticated;
create function pulse_private.activity_candidates() returns setof pulse_private.activity_events language sql stable security definer set search_path='' as $$
 select e.* from pulse_private.activity_events e where auth.uid() is not null and e.created_at>now()-interval '90 days'
 and ((e.recipient_id=auth.uid() and e.kind<>'publish') or (e.kind='publish' and e.actor_id in (select creator_id from public.pulse_social_follows where follower_id=auth.uid() and state='accepted')))
 and pulse_private.activity_visible(e.id)
$$;
revoke all on function pulse_private.activity_candidates() from public,anon,authenticated;
create function pulse_private.activity(p_before timestamptz,p_cursor uuid,p_limit int) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb; n int; s pulse_private.activity_settings;
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 if p_limit is null or p_limit not between 1 and 50 or (p_before is null)<>(p_cursor is null) then raise exception 'Invalid activity page';end if;
 select * into s from pulse_private.activity_settings where user_id=auth.uid();
 select count(*) into n from (select 1 from pulse_private.activity_candidates() e where e.created_at>coalesce(s.seen_until,'1970-01-01') and not exists(select 1 from pulse_private.activity_reads r where r.user_id=auth.uid() and r.event_id=e.id) limit 100) unread;
 select coalesce(jsonb_agg(q.item order by q.created_at desc,q.id desc),'[]'::jsonb) into items from (
 select e.id,e.created_at,jsonb_build_object('id',e.id,'kind',e.kind,'post_id',e.post_id,'actor_id',e.actor_id,
 'created_at',e.created_at,'display_name',p.display_name,'username',p.username,'avatar_path',p.avatar_path,
 'content_kind',c.kind,'is_video',c.kind='reel' or c.media->0->>'kind'='video','preview',left(c.body,180),
 'read',e.created_at<=coalesce(s.seen_until,'1970-01-01') or exists(select 1 from pulse_private.activity_reads r where r.user_id=auth.uid() and r.event_id=e.id)) item
 from pulse_private.activity_candidates() e join public.pulse_profiles p on p.id=e.actor_id left join public.pulse_social_content c on c.id=e.post_id
 where p_before is null or (e.created_at,e.id)<(p_before,p_cursor)
 order by e.created_at desc,e.id desc limit p_limit) q;
 return jsonb_build_object('items',items,'unread',n,'as_of',clock_timestamp(),'preferences',jsonb_build_object('mentions',coalesce(s.mentions,true),'follows',coalesce(s.follows,true),'likes',coalesce(s.likes,true),'comments',coalesce(s.comments,true),'following',coalesce(s.following,true)));
end $$;
create function public.pulse_activity(p_before timestamptz default null,p_cursor uuid default null,p_limit int default 30) returns jsonb language sql stable security invoker set search_path='' as $$ select pulse_private.activity(p_before,p_cursor,p_limit) $$;
create function pulse_private.activity_read(p_event uuid,p_until timestamptz) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 if (p_event is null)=(p_until is null) then raise exception 'Choose a notification or a read cutoff';end if;
 if p_event is not null then
   if not pulse_private.activity_visible(p_event) then raise exception 'Notification unavailable';end if;
   insert into pulse_private.activity_reads values(auth.uid(),p_event) on conflict do nothing;
 else
   insert into pulse_private.activity_settings(user_id,seen_until) values(auth.uid(),least(p_until,clock_timestamp()))
   on conflict(user_id) do update set seen_until=greatest(activity_settings.seen_until,excluded.seen_until);
 end if;
end $$;
create function public.pulse_activity_read(p_event uuid default null,p_until timestamptz default null) returns void language sql security invoker set search_path='' as $$ select pulse_private.activity_read(p_event,p_until) $$;
create function pulse_private.activity_preferences(p_mentions boolean,p_follows boolean,p_likes boolean,p_comments boolean,p_following boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 if p_mentions is null or p_follows is null or p_likes is null or p_comments is null or p_following is null then raise exception 'Choose notification preferences';end if;
 perform pulse_private.social_rate('activity_preferences',30,60);
 insert into pulse_private.activity_settings(user_id,mentions,follows,likes,comments,following)
 values(auth.uid(),p_mentions,p_follows,p_likes,p_comments,p_following) on conflict(user_id) do update
 set mentions=excluded.mentions,follows=excluded.follows,likes=excluded.likes,comments=excluded.comments,following=excluded.following;
end $$;
create function public.pulse_activity_preferences(p_mentions boolean,p_follows boolean,p_likes boolean,p_comments boolean,p_following boolean) returns void language sql security invoker set search_path='' as $$ select pulse_private.activity_preferences(p_mentions,p_follows,p_likes,p_comments,p_following) $$;
revoke all on function pulse_private.activity(timestamptz,uuid,int),public.pulse_activity(timestamptz,uuid,int),pulse_private.activity_read(uuid,timestamptz),public.pulse_activity_read(uuid,timestamptz),pulse_private.activity_preferences(boolean,boolean,boolean,boolean,boolean),public.pulse_activity_preferences(boolean,boolean,boolean,boolean,boolean) from public,anon;
grant execute on function pulse_private.activity(timestamptz,uuid,int),public.pulse_activity(timestamptz,uuid,int),pulse_private.activity_read(uuid,timestamptz),public.pulse_activity_read(uuid,timestamptz),pulse_private.activity_preferences(boolean,boolean,boolean,boolean,boolean),public.pulse_activity_preferences(boolean,boolean,boolean,boolean,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
