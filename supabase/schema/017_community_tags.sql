begin;
alter table pulse_private.activity_events drop constraint activity_events_kind_check;
alter table pulse_private.activity_events add constraint activity_events_kind_check check(kind in('follow','follow_request','like','comment','mention_post','mention_comment','publish','community_tag'));
alter table pulse_private.activity_events add column community_id uuid references public.pulse_chats on delete cascade;
create index activity_community on pulse_private.activity_events(community_id,created_at desc);
create unique index activity_community_once on pulse_private.activity_events(community_id,post_id) where kind='community_tag';
create function pulse_private.activity_community_tag() returns trigger language plpgsql security definer set search_path='' as $$
declare targets uuid[];
begin
 select coalesce(array_agg(c.chat_id),'{}'::uuid[]) into targets from pulse_private.community_cards c join
 (select distinct m[2] handle from regexp_matches(lower(new.body),'(^|[^a-z0-9_!])!([a-z][a-z0-9_]{2,39})(?![a-z0-9_])','g')m limit 10)t on c.handle=t.handle
 where exists(select 1 from public.pulse_members where chat_id=c.chat_id and user_id=new.author_id);
 delete from pulse_private.activity_events where kind='community_tag' and post_id=new.id and (new.state<>'published' or not(community_id=any(targets)));
 if new.state='published' then
 insert into pulse_private.activity_events(recipient_id,actor_id,kind,post_id,reference_id,community_id)
 select new.author_id,new.author_id,'community_tag',new.id,gen_random_uuid(),u from unnest(targets)u on conflict do nothing;
 end if;return new;
end $$;
revoke all on function pulse_private.activity_community_tag() from public,anon,authenticated;
create trigger pulse_activity_community_tag after insert or update on public.pulse_social_content for each row execute function pulse_private.activity_community_tag();
create or replace function pulse_private.activity_visible(p_event uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare e pulse_private.activity_events; s pulse_private.activity_settings;
begin
 if auth.uid() is null then return false;end if;
 select * into e from pulse_private.activity_events where id=p_event;
 if not found or e.actor_id=auth.uid() or pulse_private.social_blocked(e.actor_id) then return false;end if;
 select * into s from pulse_private.activity_settings where user_id=auth.uid();
 if e.kind='community_tag' then
   if not exists(select 1 from public.pulse_members where chat_id=e.community_id and user_id=auth.uid()) then return false;end if;
 elsif e.kind='publish' then
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
create or replace function pulse_private.activity_candidates() returns setof pulse_private.activity_events language sql stable security definer set search_path='' as $$
 select e.* from pulse_private.activity_events e where auth.uid() is not null and e.created_at>now()-interval '90 days'
 and ((e.kind='community_tag' and e.community_id in(select chat_id from public.pulse_members where user_id=auth.uid())) or (e.recipient_id=auth.uid() and e.kind not in('publish','community_tag')) or (e.kind='publish' and e.actor_id in (select creator_id from public.pulse_social_follows where follower_id=auth.uid() and state='accepted')))
 and pulse_private.activity_visible(e.id)
$$;
revoke all on function pulse_private.activity_candidates() from public,anon,authenticated;

create or replace function pulse_private.activity(p_before timestamptz,p_cursor uuid,p_limit int) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb; n int; s pulse_private.activity_settings;
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 if p_limit is null or p_limit not between 1 and 50 or (p_before is null)<>(p_cursor is null) then raise exception 'Invalid activity page';end if;
 select * into s from pulse_private.activity_settings where user_id=auth.uid();
 select count(*) into n from (select 1 from pulse_private.activity_candidates() e where e.created_at>coalesce(s.seen_until,'1970-01-01') and not exists(select 1 from pulse_private.activity_reads r where r.user_id=auth.uid() and r.event_id=e.id) limit 100) unread;
 select coalesce(jsonb_agg(q.item order by q.created_at desc,q.id desc),'[]'::jsonb) into items from (
 select e.id,e.created_at,jsonb_build_object('id',e.id,'kind',e.kind,'post_id',e.post_id,'actor_id',e.actor_id,
 'created_at',e.created_at,'display_name',p.display_name,'username',p.username,'avatar_path',p.avatar_path,
 'community_id',e.community_id,'community_name',(select name from public.pulse_chats where id=e.community_id),'content_kind',c.kind,'is_video',c.kind='reel' or c.media->0->>'kind'='video','preview',left(c.body,180),
 'read',e.created_at<=coalesce(s.seen_until,'1970-01-01') or exists(select 1 from pulse_private.activity_reads r where r.user_id=auth.uid() and r.event_id=e.id)) item
 from pulse_private.activity_candidates() e join public.pulse_profiles p on p.id=e.actor_id left join public.pulse_social_content c on c.id=e.post_id
 where p_before is null or (e.created_at,e.id)<(p_before,p_cursor)
 order by e.created_at desc,e.id desc limit p_limit) q;
 return jsonb_build_object('items',items,'unread',n,'as_of',clock_timestamp(),'preferences',jsonb_build_object('mentions',coalesce(s.mentions,true),'follows',coalesce(s.follows,true),'likes',coalesce(s.likes,true),'comments',coalesce(s.comments,true),'following',coalesce(s.following,true)));
end $$;

notify pgrst,'reload schema';
commit;
