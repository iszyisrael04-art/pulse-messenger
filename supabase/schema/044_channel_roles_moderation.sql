begin;
create table pulse_private.channel_limits (
 channel_id uuid primary key references public.pulse_channels on delete cascade,
 state text not null check(state in ('banned','suspended')),
 until_at timestamptz,
 reason text not null check(length(reason) between 5 and 1000),
 check(state<>'suspended' or until_at is not null)
);
alter table pulse_private.channel_limits enable row level security;
create policy channel_limits_no_client on pulse_private.channel_limits to authenticated using(false);
revoke all on pulse_private.channel_limits from public,anon,authenticated;

create function pulse_private.channel_available(p_channel uuid) returns boolean
 language sql stable security definer set search_path='' as $$
 select p_channel is not null and exists(select 1 from public.pulse_channels where id=p_channel)
 and not exists(select 1 from pulse_private.channel_limits where channel_id=p_channel
 and (state='banned' or until_at>now()))
$$;
create function pulse_private.channel_readable(p_channel uuid) returns boolean
 language sql stable security definer set search_path='' as $$
 select pulse_private.account_active() and
 (pulse_private.channel_available(p_channel) or pulse_private.is_admin())
$$;
create function pulse_private.require_channel(p_channel uuid) returns void
 language plpgsql stable security definer set search_path='' as $$
begin
 perform pulse_private.require_active();
 if not pulse_private.channel_available(p_channel) then
  raise exception 'Channel unavailable: banned, suspended or deleted' using errcode='42501';
 end if;
end $$;
revoke all on function pulse_private.channel_available(uuid),pulse_private.channel_readable(uuid),pulse_private.require_channel(uuid) from public,anon;
grant execute on function pulse_private.channel_available(uuid),pulse_private.channel_readable(uuid),pulse_private.require_channel(uuid) to authenticated;
create policy channels_moderation_read on public.pulse_channels as restrictive for select to authenticated using(pulse_private.channel_readable(id));
create policy posts_channel_moderation_read on public.pulse_posts as restrictive for select to authenticated using(pulse_private.channel_readable(channel_id));
create policy followers_channel_moderation_read on public.pulse_followers as restrictive for select to authenticated using(pulse_private.channel_readable(channel_id));
create policy admins_channel_moderation_read on public.pulse_channel_admins as restrictive for select to authenticated using(pulse_private.channel_readable(channel_id));
create policy reactions_channel_moderation_read on public.pulse_post_reactions as restrictive for select to authenticated using(
 exists(select 1 from public.pulse_posts p where p.id=post_id and pulse_private.channel_readable(p.channel_id)));

create or replace function pulse_private.channel_delete(p_channel uuid) returns void
 language plpgsql security definer set search_path='' as $$
declare channel_name text; channel_owner uuid;
begin
 perform pulse_private.require_active();
 select name,owner_id into channel_name,channel_owner from public.pulse_channels where id=p_channel for update;
 if not found then raise exception 'Channel no longer exists' using errcode='P0002';end if;
 if not pulse_private.channel_admin(p_channel) then
  raise exception 'Channel owner or channel administrator required' using errcode='42501';
 end if;
 insert into pulse_private.control_audit(staff_id,subject_id,action,detail)
 values(auth.uid(),channel_owner,'delete_channel',jsonb_build_object('channel_id',p_channel,'name',channel_name));
 delete from public.pulse_channels where id=p_channel;
end $$;

create function pulse_private.channel_moderation(p_action text,p_channel uuid,p_data jsonb) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare result jsonb; channel_owner uuid; until_time timestamptz; days integer;
begin
 perform pulse_private.require_active();
 if not pulse_private.is_admin() then raise exception 'Pulse administrator required' using errcode='42501';end if;
 if p_action='list' then
  select coalesce(jsonb_agg(q),'[]') into result from (
   select c.id,c.name,c.description,c.avatar_path,c.verified,
    case when l.state='banned' then 'banned' when l.until_at>now() then 'suspended' else 'active' end state,
    l.until_at,l.reason
   from public.pulse_channels c left join pulse_private.channel_limits l on l.channel_id=c.id
   where (coalesce(p_data->>'after','')='' or c.id>(p_data->>'after')::uuid)
   and (coalesce(p_data->>'query','')='' or strpos(lower(c.name),lower(left(p_data->>'query',80)))>0)
   order by c.id limit 50
  )q;
  return result;
 end if;
 if p_action not in ('ban','suspend','release') or p_action is null then raise exception 'Unknown channel moderation action';end if;
 select owner_id into channel_owner from public.pulse_channels where id=p_channel for update;
 if not found then raise exception 'Channel no longer exists';end if;
 if p_action='release' then
  delete from pulse_private.channel_limits where channel_id=p_channel;
 else
  if length(trim(coalesce(p_data->>'reason',''))) not between 5 and 1000 then raise exception 'Enter a clear reason (5–1000 characters)';end if;
  if p_action='suspend' then
   days=(p_data->>'days')::integer;
   if days is null or days not between 1 and 365 then raise exception 'Choose 1–365 suspension days';end if;
   until_time=now()+make_interval(days=>days);
  end if;
  insert into pulse_private.channel_limits(channel_id,state,until_at,reason)
  values(p_channel,case when p_action='ban' then 'banned' else 'suspended' end,until_time,trim(p_data->>'reason'))
  on conflict(channel_id) do update set state=excluded.state,until_at=excluded.until_at,reason=excluded.reason;
 end if;
 insert into pulse_private.control_audit(staff_id,subject_id,action,detail)
 values(auth.uid(),channel_owner,'channel_'||p_action,p_data||jsonb_build_object('channel_id',p_channel));
 return jsonb_build_object('updated',true);
end $$;
create function public.pulse_channel_moderation(p_action text,p_channel uuid default null,p_data jsonb default '{}') returns jsonb
 language sql security invoker set search_path='' as $$
 select pulse_private.require_active();
 select pulse_private.channel_moderation(p_action,p_channel,p_data)
$$;
revoke all on function pulse_private.channel_moderation(text,uuid,jsonb),public.pulse_channel_moderation(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function pulse_private.channel_moderation(text,uuid,jsonb),public.pulse_channel_moderation(text,uuid,jsonb) to authenticated;
CREATE OR REPLACE FUNCTION pulse_private.channel_post(p_channel uuid, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform pulse_private.require_channel(p_channel);
 if not pulse_private.channel_admin(p_channel) then raise exception 'Channel administrator required'; end if;
 if exists(select 1 from public.pulse_posts where author_id=auth.uid() and created_at>now()-interval '5 seconds') then raise exception 'Please wait before posting again'; end if;
 insert into public.pulse_posts(channel_id,author_id,body) values(p_channel,auth.uid(),trim(p_body));
end $function$
;
CREATE OR REPLACE FUNCTION pulse_private.channel_update(p_channel uuid, p_name text, p_description text, p_avatar text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform pulse_private.require_channel(p_channel);
 if not pulse_private.channel_admin(p_channel) then raise exception 'Channel administrator required'; end if;
 if p_avatar is not null and p_avatar is distinct from (select avatar_path from public.pulse_channels where id=p_channel) and p_avatar not like auth.uid()::text||'/%' then raise exception 'Own uploaded image required'; end if;
 update public.pulse_channels set name=trim(p_name),description=trim(p_description),avatar_path=p_avatar where id=p_channel;
end $function$
;
CREATE OR REPLACE FUNCTION pulse_private.channel_set_admin(p_channel uuid, p_user uuid, p_enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform pulse_private.require_channel(p_channel);
 if auth.uid() is null or not exists(select 1 from public.pulse_channels where id=p_channel and owner_id=auth.uid()) then raise exception 'Channel owner required'; end if;
 if p_enabled then insert into public.pulse_channel_admins values(p_channel,p_user) on conflict do nothing;
 else delete from public.pulse_channel_admins where channel_id=p_channel and user_id=p_user; end if;
end $function$
;
CREATE OR REPLACE FUNCTION pulse_private.channel_publish(p_id uuid, p_channel uuid, p_body text, p_path text, p_kind text, p_mime text, p_duration integer, p_waveform jsonb, p_cover text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare obj storage.objects; old public.pulse_posts; prefix text;begin
 perform pulse_private.require_channel(p_channel);
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
end $function$
;
CREATE OR REPLACE FUNCTION pulse_private.channel_quote(p_channel uuid, p_post uuid, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 perform pulse_private.require_channel(p_channel);
 perform pulse_private.require_active();
 if not pulse_private.channel_admin(p_channel) then raise exception 'Channel administrator required';end if;
 if p_body is null or length(trim(p_body)) not between 1 and 4000 then raise exception 'Write a reply (1–4000 characters)';end if;
 if not exists(select 1 from public.pulse_posts where id=p_post and channel_id=p_channel and not pulse_private.social_blocked(author_id))then raise exception 'Announcement unavailable';end if;
 perform pulse_private.social_rate('channel_quote',20,60);
 insert into public.pulse_posts(channel_id,author_id,body,quoted_post_id)values(p_channel,auth.uid(),trim(p_body),p_post);
end $function$
;
CREATE OR REPLACE FUNCTION pulse_private.channel_summary(p_channel uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 perform pulse_private.require_active();
 if not pulse_private.channel_readable(p_channel) then raise exception 'Channel unavailable';end if;
 return (select to_jsonb(c)||jsonb_build_object('followers',(select count(*) from public.pulse_followers where channel_id=c.id),'media_count',(select count(*) from public.pulse_posts where channel_id=c.id and attachment_path is not null and not pulse_private.social_blocked(author_id))) from public.pulse_channels c where c.id=p_channel and not pulse_private.social_blocked(c.owner_id));
end $function$
;
CREATE OR REPLACE FUNCTION pulse_private.channel_history(p_channel uuid, p_query text, p_before timestamp with time zone, p_cursor uuid, p_media boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 perform pulse_private.require_active();
 if not pulse_private.channel_readable(p_channel) then raise exception 'Channel unavailable';end if;
 if p_query is null or length(p_query)>100 or p_media is null or (p_before is null)<>(p_cursor is null) then raise exception 'Invalid search';end if;
 if not exists(select 1 from public.pulse_channels where id=p_channel and not pulse_private.social_blocked(owner_id)) then raise exception 'Channel unavailable';end if;
 return coalesce((select jsonb_agg(to_jsonb(rows) order by created_at desc,id desc) from(
 select p.*,(select left(q.body,500) from public.pulse_posts q where q.id=p.quoted_post_id and q.channel_id=p.channel_id and not pulse_private.social_blocked(q.author_id)) quoted_body from public.pulse_posts p where p.channel_id=p_channel and not pulse_private.social_blocked(p.author_id)
 and (not p_media or p.attachment_path is not null)
 and (trim(p_query)='' or to_tsvector('simple',p.body) @@ websearch_to_tsquery('simple',trim(p_query)))
 and (p_before is null or (p.created_at,p.id)<(p_before,p_cursor))
 order by p.created_at desc,p.id desc limit 30)rows),'[]');
end $function$
;
CREATE OR REPLACE FUNCTION pulse_private.channel_entry(p_post uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 perform pulse_private.require_active();
 if not pulse_private.channel_readable((select channel_id from public.pulse_posts where id=p_post)) then raise exception 'Channel unavailable';end if;
 return (select to_jsonb(p)||jsonb_build_object('username',u.username) from public.pulse_posts p join public.pulse_channels c on c.id=p.channel_id join public.pulse_profiles u on u.id=p.author_id where p.id=p_post and not pulse_private.social_blocked(p.author_id) and not pulse_private.social_blocked(c.owner_id));
end $function$
;
CREATE OR REPLACE FUNCTION pulse_private.channel_responses(p_post uuid, p_action text, p_id uuid, p_body text, p_parent uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.pulse_posts;prior pulse_private.channel_responses;
begin
 perform pulse_private.require_active();
 if not pulse_private.channel_readable((select channel_id from public.pulse_posts where id=p_post)) then raise exception 'Channel unavailable';end if;
 select * into p from public.pulse_posts where id=p_post;
 if p.id is null or pulse_private.social_blocked(p.author_id) or not exists(select 1 from public.pulse_channels where id=p.channel_id and not pulse_private.social_blocked(owner_id))then raise exception 'Announcement unavailable';end if;
 if p_action='send'then
 perform pulse_private.require_channel(p.channel_id);
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
end $function$
;
CREATE OR REPLACE FUNCTION pulse_private.channel_updates(p_action text, p_channel uuid, p_post uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb; cutoff timestamptz;
begin
 perform pulse_private.require_active();
 if p_action='read' then
 perform pulse_private.require_channel(p_channel);
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
  where pulse_private.channel_available(p.channel_id) and p.author_id<>auth.uid() and p.created_at>r.seen_until and p.created_at>now()-interval '90 days'
   and not pulse_private.social_blocked(p.author_id)
 ), counts as (select channel_id,count(*) unread from visible group by channel_id)
 select jsonb_build_object('items',coalesce((select jsonb_agg(t) from (select * from visible order by created_at desc,id desc limit 50)t),'[]'::jsonb), 'counts',coalesce((select jsonb_agg(counts) from counts),'[]'::jsonb),'total',coalesce((select sum(unread) from counts),0)) into result;
 return result;
end $function$
;
CREATE OR REPLACE FUNCTION pulse_private.follow_channel(p_channel uuid, p_follow boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_follow then
 perform pulse_private.require_channel(p_channel);
 insert into public.pulse_followers values(p_channel,auth.uid()) on conflict do nothing;
 else delete from public.pulse_followers where channel_id=p_channel and user_id=auth.uid(); end if;
 end
$function$
;
CREATE OR REPLACE FUNCTION pulse_private.post_react(p_post uuid, p_emoji text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform pulse_private.require_channel((select channel_id from public.pulse_posts where id=p_post));
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_emoji is null then delete from public.pulse_post_reactions where post_id=p_post and user_id=auth.uid();
 else insert into public.pulse_post_reactions values(p_post,auth.uid(),p_emoji) on conflict(post_id,user_id) do update set emoji=excluded.emoji; end if;
end $function$
;
CREATE OR REPLACE FUNCTION pulse_private.channel_upload_allowed(p_path text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cid uuid;begin
 if not pulse_private.account_active() or split_part(p_path,'/',2)<>auth.uid()::text then return false;end if;
 cid=split_part(p_path,'/',1)::uuid;
 return pulse_private.channel_available(cid) and pulse_private.channel_admin(cid) and split_part(p_path,'/',3)<>'' and split_part(p_path,'/',4)<>'';
 exception when invalid_text_representation then return false;
end $function$
;
CREATE OR REPLACE FUNCTION pulse_private.channel_media_read(p_path text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select pulse_private.account_active() and (pulse_private.channel_upload_allowed(p_path) or exists(
 select 1 from public.pulse_posts p join public.pulse_channels c on c.id=p.channel_id
 where pulse_private.channel_readable(c.id) and (p.attachment_path=p_path or p.cover_path=p_path)
 and not pulse_private.social_blocked(p.author_id) and not pulse_private.social_blocked(c.owner_id)))
$function$
;
commit;
