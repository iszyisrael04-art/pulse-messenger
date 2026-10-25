-- Personal-account LIVE only. Channel broadcast history is retained but closed.
begin;
alter table public.pulse_live_sessions alter column channel_id drop not null;
create index pulse_live_personal_host on public.pulse_live_sessions(host_id,created_at desc) where channel_id is null;
create function pulse_private.live_read(p_session uuid) returns boolean language sql stable security definer set search_path='' as $$
 select pulse_private.account_active() and exists(select 1 from public.pulse_live_sessions s where s.id=p_session and
 not pulse_private.social_blocked(s.host_id) and (s.channel_id is null and pulse_private.social_creator_read(s.host_id)))
$$;
create function pulse_private.live_moderator(p_session uuid) returns boolean language sql stable security definer set search_path='' as $$
 select pulse_private.account_active() and exists(select 1 from public.pulse_live_sessions s where s.id=p_session and
 s.channel_id is null and s.host_id=auth.uid())
$$;
create function pulse_private.live_follower(p_session uuid,p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.pulse_live_sessions s where s.id=p_session and
 case when s.channel_id is null then exists(select 1 from public.pulse_social_follows where creator_id=s.host_id and follower_id=p_user and state='accepted')
 else exists(select 1 from public.pulse_followers where channel_id=s.channel_id and user_id=p_user) end)
$$;
revoke all on function pulse_private.live_read(uuid),pulse_private.live_moderator(uuid),pulse_private.live_follower(uuid,uuid) from public,anon,authenticated;
grant execute on function pulse_private.live_read(uuid),pulse_private.live_moderator(uuid) to authenticated;
create function public.pulse_live_moderator(p_session uuid) returns boolean language sql security invoker set search_path='' as $$select pulse_private.live_moderator(p_session)$$;
revoke all on function public.pulse_live_moderator(uuid) from public,anon;
grant execute on function public.pulse_live_moderator(uuid) to authenticated;
drop policy live_sessions_read on public.pulse_live_sessions;
create policy live_sessions_read on public.pulse_live_sessions for select to authenticated using(pulse_private.live_read(id));
drop policy live_chat_read on public.pulse_live_chat;
create policy live_chat_read on public.pulse_live_chat for select to authenticated using(not hidden and pulse_private.live_read(session_id));
create function pulse_private.personal_live(p_action text,p_title text,p_user uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=coalesce(p_user,auth.uid()); sid uuid; followers integer; minimum integer; current_live jsonb;
begin
 perform pulse_private.require_active();
 if p_action not in('info','start') or p_action is null then raise exception 'Invalid personal LIVE action';end if;
 if not pulse_private.social_creator_read(u) then raise exception 'Profile unavailable';end if;
 select min_followers into minimum from pulse_private.live_policy where singleton;
 select count(*) into followers from public.pulse_social_follows f where creator_id=u and state='accepted'
 and not exists(select 1 from pulse_private.account_limits l where l.user_id=f.follower_id and (l.state='banned' or l.state='suspended' and l.until_at>now()));
 if p_action='start' then
  if u<>auth.uid() then raise exception 'Own profile only';end if;
  if p_title is null or length(trim(p_title)) not between 1 and 100 then raise exception 'LIVE title required';end if;
  perform 1 from public.pulse_profiles where id=u for update;
  select id into sid from public.pulse_live_sessions where host_id=u and channel_id is null and status='live' and expires_at>now() order by created_at desc limit 1;
  if sid is null then
   if followers<minimum then raise exception 'You need % followers to go live (% currently).',minimum,followers;end if;
   update public.pulse_live_sessions set status='ended',ended_at=now() where host_id=u and channel_id is null and status='live';
   insert into public.pulse_live_sessions(channel_id,host_id,title) values(null,u,trim(p_title)) returning id into sid;
  end if;
 end if;
 select jsonb_build_object('id',id,'title',title,'expires_at',expires_at) into current_live from public.pulse_live_sessions
 where host_id=u and channel_id is null and status='live' and expires_at>now() order by created_at desc limit 1;
 return jsonb_build_object('session',current_live,'followers',followers,'minimum',minimum,'eligible',u=auth.uid() and followers>=minimum,'personal',true);
end $$;
create function public.pulse_personal_live(p_action text default 'info',p_title text default null,p_user uuid default null) returns jsonb language sql security invoker set search_path='' as $$select pulse_private.personal_live(p_action,p_title,p_user)$$;
revoke all on function pulse_private.personal_live(text,text,uuid),public.pulse_personal_live(text,text,uuid) from public,anon;
grant execute on function pulse_private.personal_live(text,text,uuid),public.pulse_personal_live(text,text,uuid) to authenticated;
create or replace function pulse_private.live_tools(p_action text,p_session uuid,p_channel uuid,p_user uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
 if p_action='eligibility' then raise exception 'Channel LIVE has been removed. Go live from your personal account.';end if;
 if p_action='info' then select * into s from public.pulse_live_sessions where id=p_session;
 else select * into s from public.pulse_live_sessions where id=p_session for update;end if;
 if s.id is null or not pulse_private.live_read(p_session) then raise exception 'Live session unavailable';end if;
 mod=pulse_private.live_moderator(p_session);
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
 if not mod then raise exception 'Host required';end if;
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
create or replace function pulse_private.live_chat_send(p_session uuid,p_id uuid,p_body text) returns void language plpgsql security definer set search_path='' as $$
declare cid uuid; controls pulse_private.live_controls; moderator boolean;
begin
 perform pulse_private.require_active();
 select channel_id into cid from public.pulse_live_sessions where id=p_session and status='live' and expires_at>now() for update;
 if not found or not pulse_private.live_read(p_session) then raise exception 'Chat is available only while live';end if;
 moderator=pulse_private.live_moderator(p_session);
 if not moderator and not pulse_private.live_follower(p_session,auth.uid()) then raise exception 'Follow the broadcaster to chat';end if;
 if exists(select 1 from public.pulse_live_chat where id=p_id and user_id=auth.uid() and session_id=p_session) then return;end if;
 select * into controls from pulse_private.live_controls where session_id=p_session;
 if not moderator and coalesce(controls.chat_enabled,true)=false then raise exception 'Live chat is paused';end if;
 if exists(select 1 from pulse_private.live_mutes where session_id=p_session and user_id=auth.uid() and until_at>now()) then raise exception 'You are temporarily muted in this live';end if;
 if exists(select 1 from public.pulse_live_chat where user_id=auth.uid() and created_at>now()-make_interval(secs=>case when moderator then 2 else coalesce(controls.slow_seconds,2) end)) or (select count(*) from public.pulse_live_chat where user_id=auth.uid() and created_at>now()-interval '1 minute')>=10 then raise exception 'Slow down: live chat rate limit';end if;
 insert into public.pulse_live_chat(id,session_id,user_id,body) values(p_id,p_session,auth.uid(),trim(p_body));
end $$;
create or replace function pulse_private.live_party(p_action text,p_session uuid,p_user uuid,p_mode text) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.pulse_live_sessions; g pulse_private.live_guests;mod boolean;target uuid;allowed boolean;watch boolean;result jsonb;host_profile jsonb;
begin
 perform pulse_private.require_active();
 if p_action in('info','access') then select * into s from public.pulse_live_sessions where id=p_session;
 else select * into s from public.pulse_live_sessions where id=p_session for update;end if;
 if s.id is null or not pulse_private.live_read(p_session) then raise exception 'Live session unavailable';end if;
 mod=pulse_private.live_moderator(p_session);
 target=coalesce(p_user,auth.uid());
 if p_action='access' then
  if target<>auth.uid() and not mod then raise exception 'Own access only';end if;
  select * into g from pulse_private.live_guests where session_id=p_session and user_id=target;
  watch=s.status='live' and s.expires_at>now() and not exists(select 1 from pulse_private.account_limits where user_id=target and (state='banned' or state='suspended' and until_at>now()));
  allowed=watch and (
   target=s.host_id and (s.channel_id is null or exists(select 1 from public.pulse_channels where id=s.channel_id and owner_id=target union all select 1 from public.pulse_channel_admins where channel_id=s.channel_id and user_id=target))
   or g.state='approved' and pulse_private.live_follower(p_session,target));
  return jsonb_build_object('watch',watch,'publish',coalesce(allowed,false),'host',target=s.host_id,'mode',case when target=s.host_id then 'video' else g.mode end);
 end if;
 if p_action='info' then
  select jsonb_build_object('user_id',p.id,'display_name',p.display_name,'username',p.username,'avatar_path',p.avatar_path,'host',true,'mode','video') into host_profile from public.pulse_profiles p where p.id=s.host_id;
  select jsonb_build_object('host',host_profile,'members',coalesce((select jsonb_agg(q) from (select p.id user_id,p.display_name,p.username,p.avatar_path,guest.mode,false host from pulse_private.live_guests guest join public.pulse_profiles p on p.id=guest.user_id where guest.session_id=p_session and guest.state='approved' order by guest.updated_at,guest.user_id)q),'[]'::jsonb),'requests',case when mod then coalesce((select jsonb_agg(q) from (select p.id user_id,p.display_name,p.username,p.avatar_path,guest.mode from pulse_private.live_guests guest join public.pulse_profiles p on p.id=guest.user_id where guest.session_id=p_session and guest.state='pending' order by guest.requested_at limit 100)q),'[]'::jsonb) else '[]'::jsonb end,'state',coalesce((select state from pulse_private.live_guests where session_id=p_session and user_id=auth.uid()),'none'),'mode',(select mode from pulse_private.live_guests where session_id=p_session and user_id=auth.uid()),'moderator',mod,'limit',8) into result;
  return result;
 end if;
 if s.status<>'live' or s.expires_at<=now() then raise exception 'Livestream ended';end if;
 if p_action='request' then
  if auth.uid()=s.host_id then raise exception 'Already the host';end if;
  if p_mode not in('audio','video') or p_mode is null then raise exception 'Choose audio or video';end if;
  if not pulse_private.live_follower(p_session,auth.uid()) then raise exception 'Follow the broadcaster to request a seat';end if;
  select * into g from pulse_private.live_guests where session_id=p_session and user_id=auth.uid();
  if g.state in('pending','approved') then return jsonb_build_object('state',g.state);end if;
  if g.updated_at>clock_timestamp()-interval '30 seconds' or g.request_window>clock_timestamp()-interval '10 minutes' and g.request_count>=5 then raise exception 'Wait before requesting again';end if;
  insert into pulse_private.live_guests(session_id,user_id,state,mode) values(p_session,auth.uid(),'pending',p_mode) on conflict(session_id,user_id) do update set state='pending',mode=excluded.mode,requested_at=clock_timestamp(),updated_at=clock_timestamp(),request_window=case when pulse_private.live_guests.request_window<clock_timestamp()-interval '10 minutes' then clock_timestamp() else pulse_private.live_guests.request_window end,request_count=case when pulse_private.live_guests.request_window<clock_timestamp()-interval '10 minutes' then 1 else pulse_private.live_guests.request_count+1 end;
 elsif p_action='leave' then
  update pulse_private.live_guests set state='left',updated_at=clock_timestamp() where session_id=p_session and user_id=auth.uid();
 elsif p_action in('approve','reject','remove') then
  if not mod then raise exception 'Host required';end if;
  if p_user is null or p_user=s.host_id then raise exception 'Select a guest';end if;
  select * into g from pulse_private.live_guests where session_id=p_session and user_id=p_user;
  if g.user_id is null or p_action in('approve','reject') and g.state<>'pending' then raise exception 'Request unavailable';end if;
  if p_action='approve' then
   if (select count(*) from pulse_private.live_guests where session_id=p_session and state='approved')>=8 then raise exception 'All eight guest seats are full';end if;
   if not pulse_private.live_follower(p_session,p_user) or exists(select 1 from pulse_private.account_limits where user_id=p_user and (state='banned' or state='suspended' and until_at>now())) then raise exception 'Guest is not eligible';end if;
  end if;
  update pulse_private.live_guests set state=case p_action when 'approve' then 'approved' when 'reject' then 'rejected' else 'removed' end,updated_at=clock_timestamp() where session_id=p_session and user_id=p_user;
 else raise exception 'Unknown party action';end if;
 return jsonb_build_object('saved',true);
end $$;
create or replace function pulse_private.live_end(p_session uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform pulse_private.require_active();
 if not exists(select 1 from public.pulse_live_sessions where id=p_session and (host_id=auth.uid() or pulse_private.live_moderator(p_session))) then raise exception 'Administrator required'; end if;
 update public.pulse_live_sessions set status='ended',ended_at=now(),expires_at=now() where id=p_session;
end $$;
create or replace function pulse_private.live_chat_hide(p_message uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform pulse_private.require_active();
 if not exists(select 1 from public.pulse_live_chat m join public.pulse_live_sessions s on s.id=m.session_id where m.id=p_message and pulse_private.live_moderator(s.id)) then raise exception 'Administrator required'; end if;
 update public.pulse_live_chat set hidden=true where id=p_message;
end $$;
create or replace function pulse_private.live_gifts(p_action text,p_session uuid,p_recipient uuid,p_sku text,p_quantity integer,p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.pulse_live_sessions; g pulse_private.gift_catalog; prior pulse_private.gift_events; spend bigint; earned numeric; u uuid;
begin
 perform pulse_private.require_active();
 select * into s from public.pulse_live_sessions where id=p_session for update;
 if not pulse_private.live_read(p_session) then raise exception 'LIVE unavailable';end if;
 if s.id is null or pulse_private.social_blocked(s.host_id) then raise exception 'LIVE unavailable';end if;
 if p_action='info' then
 return jsonb_build_object('gifts',(select jsonb_agg(to_jsonb(c)order by coins)from pulse_private.gift_catalog c where enabled),'recent',coalesce((select jsonb_agg(x)from(select e.id,e.recipient_id,e.sku,e.quantity,e.created_at,p.display_name from pulse_private.gift_events e join public.pulse_profiles p on p.id=e.sender_id where e.session_id=p_session and not pulse_private.social_blocked(e.sender_id) order by e.created_at desc limit 12)x),'[]'));
 end if;
 if p_action<>'send' then raise exception 'Invalid gift action';end if;
 if p_id is null or p_quantity is null or p_quantity not between 1 and 100 then raise exception 'Invalid gift quantity';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,89));
 select * into prior from pulse_private.gift_events where id=p_id;
 if found then
 if prior.sender_id<>auth.uid() or prior.recipient_id<>p_recipient or prior.session_id<>p_session or prior.sku<>p_sku or prior.quantity<>p_quantity then raise exception 'Gift retry mismatch';end if;
 return jsonb_build_object('sent',true,'id',prior.id);end if;
 if s.status<>'live' or s.expires_at<=now() then raise exception 'LIVE ended';end if;
 if p_recipient is null or p_recipient=auth.uid() or pulse_private.social_blocked(p_recipient) then raise exception 'Cannot send this gift';end if;
 if p_recipient<>s.host_id and not exists(select 1 from pulse_private.live_guests where session_id=p_session and user_id=p_recipient and state='approved') then raise exception 'Choose a host or approved guest';end if;
 if exists(select 1 from pulse_private.account_limits where user_id=p_recipient and(state='banned' or state='suspended' and until_at>now())) then raise exception 'Recipient unavailable';end if;
 select * into g from pulse_private.gift_catalog where sku=p_sku and enabled;
 if g.sku is null then raise exception 'Gift unavailable';end if;
 spend=g.coins::bigint*p_quantity;earned=g.p_coins*p_quantity;
 perform pulse_private.social_rate('send_gift',30,60);
 -- Stable wallet lock order prevents reciprocal gift deadlocks.
 for u in select unnest(array[auth.uid(),p_recipient]) order by 1 loop
 insert into pulse_private.wallets(user_id)values(u)on conflict do nothing;
 perform 1 from pulse_private.wallets where user_id=u for update;
 end loop;
 update pulse_private.wallets set coins=coins-spend where user_id=auth.uid() and coins>=spend;
 if not found then raise exception 'Not enough normal coins';end if;
 update pulse_private.wallets set p_coins=p_coins+earned where user_id=p_recipient;
 insert into pulse_private.gift_events values(p_id,auth.uid(),p_recipient,p_session,p_sku,p_quantity,spend,earned,clock_timestamp());
 return jsonb_build_object('sent',true,'id',p_id,'coins_spent',spend,'p_coins_earned',earned);
end $$;
create or replace function pulse_private.test_live_gift(p_session uuid,p_recipient uuid,p_sku text,p_quantity integer,p_id uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare s public.pulse_live_sessions;prior pulse_private.test_gift_events;price integer;spend bigint;
begin
 perform pulse_private.require_active();
 select * into s from public.pulse_live_sessions where id=p_session for update;
 if not pulse_private.live_read(p_session) then raise exception 'LIVE unavailable';end if;
 if s.id is null or pulse_private.social_blocked(s.host_id)then raise exception 'LIVE unavailable';end if;
 if p_id is null or p_quantity is null or p_quantity not between 1 and 100 then raise exception 'Choose 1–100 gifts';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,98));
 select * into prior from pulse_private.test_gift_events where id=p_id;
 if found then
 if prior.sender_id<>auth.uid()or prior.recipient_id<>p_recipient or prior.session_id<>p_session or prior.sku<>p_sku or prior.quantity<>p_quantity then raise exception 'Test gift retry mismatch';end if;
 return jsonb_build_object('sent',true,'test',true,'id',prior.id);end if;
 if s.status<>'live'or s.expires_at<=now()then raise exception 'LIVE ended';end if;
 if p_recipient is null or pulse_private.social_blocked(p_recipient)then raise exception 'Recipient unavailable';end if;
 if p_recipient<>s.host_id and not exists(select 1 from pulse_private.live_guests where session_id=p_session and user_id=p_recipient and state='approved')then raise exception 'Choose the host or approved guest';end if;
 if exists(select 1 from pulse_private.account_limits where user_id=p_recipient and(state='banned'or state='suspended'and until_at>now()))then raise exception 'Recipient unavailable';end if;
 select coins into price from pulse_private.gift_catalog where sku=p_sku and enabled;
 if price is null then raise exception 'Gift unavailable';end if;
 spend=price::bigint*p_quantity;
 perform pulse_private.social_rate('test_gift',30,60);
 update pulse_private.test_wallets set coins=coins-spend where user_id=auth.uid()and coins>=spend;
 if not found then raise exception 'Not enough test coins';end if;
 insert into pulse_private.test_gift_events values(p_id,auth.uid(),p_recipient,p_session,p_sku,p_quantity,spend,clock_timestamp());
 return jsonb_build_object('sent',true,'test',true,'id',p_id,'test_coins_spent',spend,'p_coins_earned',0);
end $$;
create or replace function pulse_private.gift_feed(p_session uuid,p_after timestamptz,p_cursor uuid)returns jsonb language plpgsql security definer set search_path=''as $$
declare s public.pulse_live_sessions; rows jsonb;last_time timestamptz;last_id uuid;
begin
 perform pulse_private.require_active();
 select * into s from public.pulse_live_sessions where id=p_session;
 if not pulse_private.live_read(p_session) then raise exception 'LIVE unavailable';end if;
 if s.id is null or pulse_private.social_blocked(s.host_id)then raise exception 'LIVE unavailable';end if;
 if (p_after is null)<>(p_cursor is null)then raise exception 'Invalid gift cursor';end if;
 if p_after is null then
  select created_at,id into last_time,last_id from (select id,sender_id,recipient_id,session_id,sku,quantity,created_at,false is_test from pulse_private.gift_events union all select id,sender_id,recipient_id,session_id,sku,quantity,created_at,true is_test from pulse_private.test_gift_events) combined where session_id=p_session order by created_at desc,id desc limit 1;
  return jsonb_build_object('items','[]'::jsonb,'after',coalesce(last_time,'1970-01-01'::timestamptz),'cursor',coalesce(last_id,'00000000-0000-0000-0000-000000000000'::uuid));
 end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by created_at,id),'[]')into rows from(
  select e.id,e.created_at,e.sku,e.quantity,e.sender_id,e.recipient_id,e.is_test,p.display_name,p.avatar_path,case when e.is_test then 'TEST · '||g.title else g.title end title,
   pulse_private.gifter_status(e.sender_id,null,null)gifter
  from (select id,sender_id,recipient_id,session_id,sku,quantity,created_at,false is_test from pulse_private.gift_events union all select id,sender_id,recipient_id,session_id,sku,quantity,created_at,true is_test from pulse_private.test_gift_events) e join public.pulse_profiles p on p.id=e.sender_id join pulse_private.gift_catalog g on g.sku=e.sku
  where e.session_id=p_session and(e.created_at,e.id)>(p_after,p_cursor)
  order by e.created_at,e.id limit 50)x;
 -- Advance over blocked senders too, without exposing their event/profile.
 if jsonb_array_length(rows)>0 then
  last_time=(rows->-1->>'created_at')::timestamptz;last_id=(rows->-1->>'id')::uuid;
 else last_time=p_after;last_id=p_cursor;end if;
 select coalesce(jsonb_agg(v order by v->>'created_at',v->>'id'),'[]')into rows from jsonb_array_elements(rows)v where not pulse_private.social_blocked((v->>'sender_id')::uuid);
 return jsonb_build_object('items',rows,'after',last_time,'cursor',last_id);
end $$;
create or replace function pulse_private.live_battle(p_action text,p_session uuid,p_opponent uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.pulse_live_sessions;b pulse_private.live_battles; hs bigint; os bigint;
begin
 perform pulse_private.require_active();
 select * into s from public.pulse_live_sessions where id=p_session for update;
 if not pulse_private.live_read(p_session) then raise exception 'LIVE unavailable';end if;
 if s.id is null or pulse_private.social_blocked(s.host_id) then raise exception 'LIVE unavailable';end if;
 select * into b from pulse_private.live_battles where session_id=p_session order by created_at desc,id desc limit 1 for update;
 if b.state='active' and (b.ends_at<=now() or s.status<>'live' or s.expires_at<=now() or not exists(select 1 from pulse_private.live_guests where session_id=p_session and user_id=b.opponent_id and state='approved')) or b.state='invited' and (b.created_at<now()-interval '60 seconds' or s.status<>'live') then
 update pulse_private.live_battles set state='ended',ends_at=least(coalesce(ends_at,now()),clock_timestamp()) where id=b.id returning * into b;end if;
 if p_action='invite' then
 if s.host_id<>auth.uid() or s.status<>'live' or s.expires_at<=now() then raise exception 'Active host required';end if;
 if b.state in('invited','active') then raise exception 'A battle is already open';end if;
 if p_opponent=auth.uid() or p_opponent is null or pulse_private.social_blocked(p_opponent) or not exists(select 1 from pulse_private.live_guests where session_id=p_session and user_id=p_opponent and state='approved')then raise exception 'Choose an approved guest';end if;
 insert into pulse_private.live_battles(session_id,host_id,opponent_id)values(p_session,auth.uid(),p_opponent)returning * into b;
 elsif p_action in('accept','decline') then
 if b.state<>'invited' or b.opponent_id<>auth.uid() or s.status<>'live' or s.expires_at<=now() then raise exception 'Invitation unavailable';end if;
 if not exists(select 1 from pulse_private.live_guests where session_id=p_session and user_id=auth.uid() and state='approved')then raise exception 'Join the stage first';end if;
 update pulse_private.live_battles set state=case when p_action='accept' then 'active' else 'declined' end,starts_at=case when p_action='accept' then clock_timestamp()end,ends_at=case when p_action='accept' then clock_timestamp()+interval '3 minutes'end where id=b.id returning * into b;
 elsif p_action='end' then
 if auth.uid() not in(b.host_id,b.opponent_id) then raise exception 'Battle participant required';end if;
 update pulse_private.live_battles set state='ended',ends_at=least(coalesce(ends_at,now()),clock_timestamp())where id=b.id returning * into b;
 elsif p_action<>'info' then raise exception 'Invalid battle action';end if;
 if b.id is null then return '{}'::jsonb;end if;
 select coalesce(sum(coins)filter(where recipient_id=b.host_id),0),coalesce(sum(coins)filter(where recipient_id=b.opponent_id),0) into hs,os from pulse_private.gift_events where session_id=p_session and created_at>=b.starts_at and created_at<=b.ends_at;
 return to_jsonb(b)||jsonb_build_object('host_score',hs,'opponent_score',os,'remaining',greatest(0,extract(epoch from b.ends_at-now())::integer),'winner',case when b.state='ended' and hs<>os then case when hs>os then b.host_id else b.opponent_id end else null end);
end $$;

create or replace function pulse_private.live_start(p_channel uuid,p_title text) returns uuid language plpgsql security definer set search_path='' as $$
begin
 perform pulse_private.require_active();
 raise exception 'Channel LIVE has been removed. Go live from your personal account.';
end $$;
-- Do not delete channels or historical sessions, gifts or messages.
update public.pulse_live_sessions set status='ended',ended_at=coalesce(ended_at,clock_timestamp()),expires_at=least(expires_at,clock_timestamp()) where channel_id is not null and status='live';
commit;
