begin;
create table pulse_private.live_guests(session_id uuid references public.pulse_live_sessions on delete cascade,user_id uuid references public.pulse_profiles on delete cascade,state text not null check(state in('pending','approved','rejected','removed','left')),mode text not null default 'video' check(mode in('audio','video')),requested_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),request_window timestamptz not null default clock_timestamp(),request_count integer not null default 1,primary key(session_id,user_id));
create index live_guests_user on pulse_private.live_guests(user_id);
alter table pulse_private.live_guests enable row level security;
revoke all on pulse_private.live_guests from public,anon,authenticated;
create function pulse_private.live_party(p_action text,p_session uuid,p_user uuid,p_mode text) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.pulse_live_sessions; g pulse_private.live_guests;mod boolean;target uuid;allowed boolean;watch boolean;result jsonb;host_profile jsonb;
begin
 perform pulse_private.require_active();
 if p_action in('info','access') then select * into s from public.pulse_live_sessions where id=p_session;
 else select * into s from public.pulse_live_sessions where id=p_session for update;end if;
 if s.id is null then raise exception 'Live session unavailable';end if;
 mod=pulse_private.channel_admin(s.channel_id);
 target=coalesce(p_user,auth.uid());
 if p_action='access' then
  if target<>auth.uid() and not mod then raise exception 'Own access only';end if;
  select * into g from pulse_private.live_guests where session_id=p_session and user_id=target;
  watch=s.status='live' and s.expires_at>now() and not exists(select 1 from pulse_private.account_limits where user_id=target and (state='banned' or state='suspended' and until_at>now()));
  allowed=watch and (
   target=s.host_id and exists(select 1 from public.pulse_channels where id=s.channel_id and owner_id=target union all select 1 from public.pulse_channel_admins where channel_id=s.channel_id and user_id=target)
   or g.state='approved' and exists(select 1 from public.pulse_followers where channel_id=s.channel_id and user_id=target));
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
  if not exists(select 1 from public.pulse_followers where channel_id=s.channel_id and user_id=auth.uid()) then raise exception 'Follow the channel to request a seat';end if;
  select * into g from pulse_private.live_guests where session_id=p_session and user_id=auth.uid();
  if g.state in('pending','approved') then return jsonb_build_object('state',g.state);end if;
  if g.updated_at>clock_timestamp()-interval '30 seconds' or g.request_window>clock_timestamp()-interval '10 minutes' and g.request_count>=5 then raise exception 'Wait before requesting again';end if;
  insert into pulse_private.live_guests(session_id,user_id,state,mode) values(p_session,auth.uid(),'pending',p_mode) on conflict(session_id,user_id) do update set state='pending',mode=excluded.mode,requested_at=clock_timestamp(),updated_at=clock_timestamp(),request_window=case when pulse_private.live_guests.request_window<clock_timestamp()-interval '10 minutes' then clock_timestamp() else pulse_private.live_guests.request_window end,request_count=case when pulse_private.live_guests.request_window<clock_timestamp()-interval '10 minutes' then 1 else pulse_private.live_guests.request_count+1 end;
 elsif p_action='leave' then
  update pulse_private.live_guests set state='left',updated_at=clock_timestamp() where session_id=p_session and user_id=auth.uid();
 elsif p_action in('approve','reject','remove') then
  if not mod then raise exception 'Channel administrator required';end if;
  if p_user is null or p_user=s.host_id then raise exception 'Select a guest';end if;
  select * into g from pulse_private.live_guests where session_id=p_session and user_id=p_user;
  if g.user_id is null or p_action in('approve','reject') and g.state<>'pending' then raise exception 'Request unavailable';end if;
  if p_action='approve' then
   if (select count(*) from pulse_private.live_guests where session_id=p_session and state='approved')>=8 then raise exception 'All eight guest seats are full';end if;
   if not exists(select 1 from public.pulse_followers where channel_id=s.channel_id and user_id=p_user) or exists(select 1 from pulse_private.account_limits where user_id=p_user and (state='banned' or state='suspended' and until_at>now())) then raise exception 'Guest is not eligible';end if;
  end if;
  update pulse_private.live_guests set state=case p_action when 'approve' then 'approved' when 'reject' then 'rejected' else 'removed' end,updated_at=clock_timestamp() where session_id=p_session and user_id=p_user;
 else raise exception 'Unknown party action';end if;
 return jsonb_build_object('saved',true);
end $$;
revoke all on function pulse_private.live_party(text,uuid,uuid,text) from public,anon;
grant execute on function pulse_private.live_party(text,uuid,uuid,text) to authenticated;
create function public.pulse_live_party(p_action text,p_session uuid,p_user uuid default null,p_mode text default 'video') returns jsonb language sql security invoker set search_path='' as $$select pulse_private.require_active();select pulse_private.live_party(p_action,p_session,p_user,p_mode)$$;
revoke all on function public.pulse_live_party(text,uuid,uuid,text) from public,anon;
grant execute on function public.pulse_live_party(text,uuid,uuid,text) to authenticated;
commit;
