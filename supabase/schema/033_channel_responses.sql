begin;
create table pulse_private.channel_responses(id uuid primary key,post_id uuid not null references public.pulse_posts on delete cascade,user_id uuid not null references public.pulse_profiles on delete cascade,body text not null check(length(body) between 1 and 2000),parent_id uuid references pulse_private.channel_responses on delete set null,created_at timestamptz not null default clock_timestamp());
create index channel_responses_post on pulse_private.channel_responses(post_id,created_at desc,id desc);
create index channel_responses_parent on pulse_private.channel_responses(parent_id);
create index channel_responses_user on pulse_private.channel_responses(user_id);
alter table pulse_private.channel_responses enable row level security;
revoke all on pulse_private.channel_responses from public,anon,authenticated;
create policy deny_clients on pulse_private.channel_responses for all to anon,authenticated using(false)with check(false);
create function pulse_private.channel_responses(p_post uuid,p_action text,p_id uuid,p_body text,p_parent uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare p public.pulse_posts;prior pulse_private.channel_responses;
begin
 perform pulse_private.require_active();
 select * into p from public.pulse_posts where id=p_post;
 if p.id is null or pulse_private.social_blocked(p.author_id) or not exists(select 1 from public.pulse_channels where id=p.channel_id and not pulse_private.social_blocked(owner_id))then raise exception 'Announcement unavailable';end if;
 if p_action='send'then
  if not pulse_private.channel_admin(p.channel_id) and not exists(select 1 from public.pulse_followers where channel_id=p.channel_id and user_id=auth.uid())then raise exception 'Follow this channel to respond';end if;
  if p_id is null or p_body is null or length(trim(p_body))not between 1 and 2000 then raise exception 'Write a response (1–2000 characters)';end if;
  perform pg_advisory_xact_lock(hashtextextended(p_id::text,97));
  select * into prior from pulse_private.channel_responses where id=p_id;
  if found then
   if prior.post_id<>p_post or prior.user_id<>auth.uid()or prior.body<>trim(p_body)or prior.parent_id is distinct from p_parent then raise exception 'Response retry mismatch';end if;
  else
   if p_parent is not null and not exists(select 1 from pulse_private.channel_responses where id=p_parent and post_id=p_post and not pulse_private.social_blocked(user_id))then raise exception 'Quoted response unavailable';end if;
   perform pulse_private.social_rate('channel_response',20,60);
   insert into pulse_private.channel_responses(id,post_id,user_id,body,parent_id)values(p_id,p_post,auth.uid(),trim(p_body),p_parent);
  end if;
 elsif p_action<>'list'then raise exception 'Invalid response action';end if;
 return jsonb_build_object('items',coalesce((select jsonb_agg(x order by x.created_at)from(
  select r.id,r.body,r.parent_id,r.created_at,u.id user_id,u.display_name,u.username,u.avatar_path,
  (select left(q.body,300)from pulse_private.channel_responses q where q.id=r.parent_id and not pulse_private.social_blocked(q.user_id))quoted_body
  from pulse_private.channel_responses r join public.pulse_profiles u on u.id=r.user_id where r.post_id=p_post and not pulse_private.social_blocked(r.user_id) order by r.created_at desc,r.id desc limit 100)x),'[]'),
 'count',(select count(*)from pulse_private.channel_responses where post_id=p_post and not pulse_private.social_blocked(user_id)),
 'can_respond',pulse_private.channel_admin(p.channel_id)or exists(select 1 from public.pulse_followers where channel_id=p.channel_id and user_id=auth.uid()));
end $$;
create function public.pulse_channel_responses(p_post uuid,p_action text default 'list',p_id uuid default null,p_body text default null,p_parent uuid default null)returns jsonb language sql security invoker set search_path=''as $$select pulse_private.channel_responses(p_post,p_action,p_id,p_body,p_parent)$$;
revoke all on function pulse_private.channel_responses(uuid,text,uuid,text,uuid),public.pulse_channel_responses(uuid,text,uuid,text,uuid)from public,anon,authenticated;
grant execute on function pulse_private.channel_responses(uuid,text,uuid,text,uuid),public.pulse_channel_responses(uuid,text,uuid,text,uuid)to authenticated;
commit;
