-- Ordered installation script, not a Supabase CLI migration-history file.
begin;
create table pulse_private.live_policy(singleton boolean primary key default true check(singleton),min_followers integer not null default 100 check(min_followers between 0 and 1000000));
insert into pulse_private.live_policy values(true,100);
create table pulse_private.live_controls(session_id uuid primary key references public.pulse_live_sessions on delete cascade,chat_enabled boolean not null default true,slow_seconds integer not null default 2 check(slow_seconds between 2 and 120),pinned_message uuid references public.pulse_live_chat on delete set null);
create index live_controls_pinned on pulse_private.live_controls(pinned_message);
create table pulse_private.live_mutes(session_id uuid references public.pulse_live_sessions on delete cascade,user_id uuid references public.pulse_profiles on delete cascade,until_at timestamptz not null,primary key(session_id,user_id));
create index live_mutes_user on pulse_private.live_mutes(user_id);
create table pulse_private.live_likes(session_id uuid references public.pulse_live_sessions on delete cascade,user_id uuid references public.pulse_profiles on delete cascade,primary key(session_id,user_id));
create index live_likes_user on pulse_private.live_likes(user_id);
alter table pulse_private.live_policy enable row level security;
alter table pulse_private.live_controls enable row level security;
alter table pulse_private.live_mutes enable row level security;
alter table pulse_private.live_likes enable row level security;
revoke all on pulse_private.live_policy,pulse_private.live_controls,pulse_private.live_mutes,pulse_private.live_likes from public,anon,authenticated;

create function pulse_private.live_tools(p_action text,p_session uuid,p_channel uuid,p_user uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.pulse_live_sessions; c pulse_private.live_controls; followers integer; minimum integer; mod boolean; pinned jsonb; until_time timestamptz;
begin
 perform pulse_private.require_active();
 select min_followers into minimum from pulse_private.live_policy where singleton;
 if p_action='policy' then return jsonb_build_object('min_followers',minimum);end if;
 if p_action='policy_save' then
  if not pulse_private.is_admin() then raise exception 'Staff required';end if;
  update pulse_private.live_policy set min_followers=(p_data->>'min_followers')::int where singleton;
  insert into pulse_private.control_audit(staff_id,action,detail) values(auth.uid(),'live_policy',p_data);
  return jsonb_build_object('saved',true);
 end if;
 if p_action='eligibility' then
  if not exists(select 1 from public.pulse_channels where id=p_channel) then raise exception 'Channel unavailable';end if;
  select count(*) into followers from public.pulse_followers f where f.channel_id=p_channel
   and f.user_id<>(select owner_id from public.pulse_channels where id=p_channel)
   and not exists(select 1 from pulse_private.account_limits l where l.user_id=f.user_id and (l.state='banned' or l.state='suspended' and l.until_at>now()));
  return jsonb_build_object('followers',followers,'minimum',minimum,'admin',pulse_private.channel_admin(p_channel),'eligible',pulse_private.channel_admin(p_channel) and followers>=minimum);
 end if;
 if p_action='info' then select * into s from public.pulse_live_sessions where id=p_session;
 else select * into s from public.pulse_live_sessions where id=p_session for update;end if;
 if s.id is null then raise exception 'Live session unavailable';end if;
 mod=pulse_private.channel_admin(s.channel_id);
 select * into c from pulse_private.live_controls where session_id=p_session;
 if p_action='info' then
  select jsonb_build_object('id',m.id,'body',m.body) into pinned from public.pulse_live_chat m where m.id=c.pinned_message and not m.hidden;
  select until_at into until_time from pulse_private.live_mutes where session_id=p_session and user_id=auth.uid() and until_at>now();
  return jsonb_build_object('chat_enabled',coalesce(c.chat_enabled,true),'slow_seconds',coalesce(c.slow_seconds,2),'pinned',pinned,'muted_until',until_time,'liked',exists(select 1 from pulse_private.live_likes where session_id=p_session and user_id=auth.uid()),'likes',(select count(*) from pulse_private.live_likes where session_id=p_session),'moderator',mod);
 end if;
 if s.status<>'live' or s.expires_at<=now() then raise exception 'Livestream ended';end if;
 if p_action='like' then
  if coalesce((p_data->>'enabled')::boolean,true) then insert into pulse_private.live_likes values(p_session,auth.uid()) on conflict do nothing;
  else delete from pulse_private.live_likes where session_id=p_session and user_id=auth.uid();end if;
  return jsonb_build_object('saved',true);
 end if;
 if not mod then raise exception 'Channel administrator required';end if;
 insert into pulse_private.live_controls(session_id) values(p_session) on conflict do nothing;
 if p_action='settings' then
  update pulse_private.live_controls set chat_enabled=coalesce((p_data->>'chat_enabled')::boolean,chat_enabled),slow_seconds=coalesce((p_data->>'slow_seconds')::integer,slow_seconds) where session_id=p_session;
 elsif p_action='pin' then
  if p_data->>'message' is not null and not exists(select 1 from public.pulse_live_chat where id=(p_data->>'message')::uuid and session_id=p_session and not hidden) then raise exception 'Comment unavailable';end if;
  update pulse_private.live_controls set pinned_message=(p_data->>'message')::uuid where session_id=p_session;
 elsif p_action='mute' then
  if p_user is null or p_user=s.host_id or pulse_private.channel_admin(s.channel_id) and exists(select 1 from public.pulse_channel_admins where channel_id=s.channel_id and user_id=p_user) then raise exception 'Cannot mute host or administrator';end if;
  if exists(select 1 from public.pulse_channels where id=s.channel_id and owner_id=p_user) then raise exception 'Cannot mute channel owner';end if;
  if coalesce((p_data->>'minutes')::integer,10) not between 1 and 1440 then raise exception 'Mute duration 1-1440 minutes';end if;
  insert into pulse_private.live_mutes values(p_session,p_user,now()+make_interval(mins=>coalesce((p_data->>'minutes')::integer,10))) on conflict(session_id,user_id) do update set until_at=excluded.until_at;
 elsif p_action='unmute' then delete from pulse_private.live_mutes where session_id=p_session and user_id=p_user;
 else raise exception 'Unknown live action';end if;
 return jsonb_build_object('saved',true);
end $$;
revoke all on function pulse_private.live_tools(text,uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function pulse_private.live_tools(text,uuid,uuid,uuid,jsonb) to authenticated;
create function public.pulse_live_tools(p_action text,p_session uuid default null,p_channel uuid default null,p_user uuid default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select pulse_private.require_active();select pulse_private.live_tools(p_action,p_session,p_channel,p_user,p_data)$$;
revoke all on function public.pulse_live_tools(text,uuid,uuid,uuid,jsonb) from public,anon;
grant execute on function public.pulse_live_tools(text,uuid,uuid,uuid,jsonb) to authenticated;

create or replace function pulse_private.live_start(p_channel uuid,p_title text) returns uuid language plpgsql security definer set search_path='' as $$
declare sid uuid; eligibility jsonb;
begin
 perform pulse_private.require_active();
 if not pulse_private.channel_admin(p_channel) then raise exception 'Channel administrator required';end if;
 perform 1 from public.pulse_channels where id=p_channel for update;
 eligibility=pulse_private.live_tools('eligibility',null,p_channel,null,'{}');
 if not (eligibility->>'eligible')::boolean then raise exception 'This channel needs % followers to go live (% currently).',eligibility->>'minimum',eligibility->>'followers';end if;
 if exists(select 1 from public.pulse_live_sessions where channel_id=p_channel and status='live' and expires_at>now()) then raise exception 'This channel is already live';end if;
 update public.pulse_live_sessions set status='ended',ended_at=now() where channel_id=p_channel and status='live';
 insert into public.pulse_live_sessions(channel_id,host_id,title) values(p_channel,auth.uid(),trim(p_title)) returning id into sid;
 return sid;
end $$;

create or replace function pulse_private.live_chat_send(p_session uuid,p_id uuid,p_body text) returns void language plpgsql security definer set search_path='' as $$
declare cid uuid; controls pulse_private.live_controls; moderator boolean;
begin
 perform pulse_private.require_active();
 select channel_id into cid from public.pulse_live_sessions where id=p_session and status='live' and expires_at>now() for update;
 if cid is null then raise exception 'Chat is available only while live';end if;
 moderator=pulse_private.channel_admin(cid);
 if not moderator and not exists(select 1 from public.pulse_followers where channel_id=cid and user_id=auth.uid()) then raise exception 'Follow this channel to chat';end if;
 if exists(select 1 from public.pulse_live_chat where id=p_id and user_id=auth.uid() and session_id=p_session) then return;end if;
 select * into controls from pulse_private.live_controls where session_id=p_session;
 if not moderator and coalesce(controls.chat_enabled,true)=false then raise exception 'Live chat is paused';end if;
 if exists(select 1 from pulse_private.live_mutes where session_id=p_session and user_id=auth.uid() and until_at>now()) then raise exception 'You are temporarily muted in this live';end if;
 if exists(select 1 from public.pulse_live_chat where user_id=auth.uid() and created_at>now()-make_interval(secs=>case when moderator then 2 else coalesce(controls.slow_seconds,2) end)) or (select count(*) from public.pulse_live_chat where user_id=auth.uid() and created_at>now()-interval '1 minute')>=10 then raise exception 'Slow down: live chat rate limit';end if;
 insert into public.pulse_live_chat(id,session_id,user_id,body) values(p_id,p_session,auth.uid(),trim(p_body));
end $$;
commit;
