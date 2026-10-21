begin;
alter table pulse_private.community_cards add column verified boolean not null default false;
do $$declare definition text;begin
 select pg_get_functiondef('pulse_private.communities(text,uuid,uuid,jsonb)'::regprocedure) into definition;
 if position('c.is_private,g.name' in definition)=0 then raise exception 'Unexpected communities function; inspect before upgrading';end if;
 execute replace(definition,'c.is_private,g.name','c.is_private,c.verified,g.name');
end $$;
create function pulse_private.community_verification(p_action text,p_chat uuid,p_enabled boolean,p_query text,p_after uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;owner uuid;
begin
 perform pulse_private.require_active();
 if not pulse_private.is_admin() then raise exception 'Pulse staff required';end if;
 if p_action='list' then
  select coalesce(jsonb_agg(r),'[]') into result from (select c.chat_id,c.handle,c.verified,c.avatar_path,c.is_private,g.name from pulse_private.community_cards c join public.pulse_chats g on g.id=c.chat_id where (p_after is null or c.chat_id>p_after) and (coalesce(p_query,'')='' or c.handle ilike '%'||left(p_query,40)||'%' or g.name ilike '%'||left(p_query,40)||'%') order by c.chat_id limit 50)r;
  return result;
 elsif p_action='set' then
  update pulse_private.community_cards set verified=p_enabled where chat_id=p_chat;
  if not found then raise exception 'Community unavailable';end if;
  select owner_id into owner from public.pulse_chats where id=p_chat;
  insert into pulse_private.control_audit(staff_id,subject_id,action,detail) values(auth.uid(),owner,'community_verification',jsonb_build_object('chat_id',p_chat,'verified',p_enabled));
  return jsonb_build_object('verified',p_enabled);
 end if;
 raise exception 'Unknown verification action';
end $$;
revoke all on function pulse_private.community_verification(text,uuid,boolean,text,uuid) from public,anon;
grant execute on function pulse_private.community_verification(text,uuid,boolean,text,uuid) to authenticated;
create function public.pulse_community_verification(p_action text,p_chat uuid default null,p_enabled boolean default false,p_query text default '',p_after uuid default null) returns jsonb language sql security invoker set search_path='' as $$select pulse_private.require_active();select pulse_private.community_verification(p_action,p_chat,p_enabled,p_query,p_after)$$;
revoke all on function public.pulse_community_verification(text,uuid,boolean,text,uuid) from public,anon;
grant execute on function public.pulse_community_verification(text,uuid,boolean,text,uuid) to authenticated;

create table pulse_private.channel_reads(user_id uuid references public.pulse_profiles on delete cascade,channel_id uuid references public.pulse_channels on delete cascade,seen_until timestamptz not null default clock_timestamp(),primary key(user_id,channel_id));
create index channel_reads_channel on pulse_private.channel_reads(channel_id);
alter table pulse_private.channel_reads enable row level security;
revoke all on pulse_private.channel_reads from public,anon,authenticated;
create index pulse_channel_posts_page on public.pulse_posts(channel_id,created_at desc,id desc);
create function pulse_private.channel_follow_read_baseline() returns trigger language plpgsql security definer set search_path='' as $$begin
 insert into pulse_private.channel_reads(user_id,channel_id,seen_until) values(new.user_id,new.channel_id,clock_timestamp()) on conflict(user_id,channel_id) do update set seen_until=excluded.seen_until;return new;end $$;
revoke all on function pulse_private.channel_follow_read_baseline() from public,anon,authenticated;
create trigger pulse_channel_follow_read after insert on public.pulse_followers for each row execute function pulse_private.channel_follow_read_baseline();
create function pulse_private.channel_updates(p_action text,p_channel uuid,p_post uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; cutoff timestamptz;
begin
 perform pulse_private.require_active();
 if p_action='read' then
  if not exists(select 1 from public.pulse_followers where channel_id=p_channel and user_id=auth.uid()) and not pulse_private.channel_admin(p_channel) then raise exception 'Follow this channel';end if;
  if p_post is null then cutoff=clock_timestamp();else select created_at into cutoff from public.pulse_posts where id=p_post and channel_id=p_channel;if cutoff is null then raise exception 'Post unavailable';end if;end if;
  insert into pulse_private.channel_reads values(auth.uid(),p_channel,cutoff) on conflict(user_id,channel_id) do update set seen_until=greatest(pulse_private.channel_reads.seen_until,excluded.seen_until);
  return jsonb_build_object('read',true);
 elsif p_action<>'list' then raise exception 'Unknown channel update action';end if;
 -- First synchronization initializes existing subscriptions without alerting old history.
 insert into pulse_private.channel_reads(user_id,channel_id) select auth.uid(),channel_id from public.pulse_followers where user_id=auth.uid() on conflict do nothing;
 with visible as (
  select p.id,p.channel_id,p.author_id,p.body,p.created_at,c.name,c.avatar_path,c.verified
  from public.pulse_posts p join public.pulse_channels c on c.id=p.channel_id
  join public.pulse_followers f on f.channel_id=p.channel_id and f.user_id=auth.uid()
  join pulse_private.channel_reads r on r.channel_id=p.channel_id and r.user_id=auth.uid()
  where p.author_id<>auth.uid() and p.created_at>r.seen_until and p.created_at>now()-interval '90 days'
   and not pulse_private.social_blocked(p.author_id)
 ), counts as (select channel_id,count(*) unread from visible group by channel_id)
 select jsonb_build_object('items',coalesce((select jsonb_agg(t) from (select * from visible order by created_at desc,id desc limit 50)t),'[]'::jsonb), 'counts',coalesce((select jsonb_agg(counts) from counts),'[]'::jsonb),'total',coalesce((select sum(unread) from counts),0)) into result;
 return result;
end $$;
revoke all on function pulse_private.channel_updates(text,uuid,uuid) from public,anon;
grant execute on function pulse_private.channel_updates(text,uuid,uuid) to authenticated;
create function public.pulse_channel_updates(p_action text default 'list',p_channel uuid default null,p_post uuid default null) returns jsonb language sql security invoker set search_path='' as $$select pulse_private.require_active();select pulse_private.channel_updates(p_action,p_channel,p_post)$$;
revoke all on function public.pulse_channel_updates(text,uuid,uuid) from public,anon;
grant execute on function public.pulse_channel_updates(text,uuid,uuid) to authenticated;
commit;
