begin;
create table pulse_private.presence_settings (
 user_id uuid primary key references public.pulse_profiles on delete cascade,
 sharing boolean not null default true
);
create table pulse_private.presence_devices (
 user_id uuid not null references public.pulse_profiles on delete cascade,
 device_id uuid not null,sequence bigint not null check(sequence>0),
 seen_at timestamptz not null default now(),expires_at timestamptz not null,
 primary key(user_id,device_id)
);
create index presence_device_expiry on pulse_private.presence_devices(user_id,expires_at);
alter table pulse_private.presence_settings enable row level security;
alter table pulse_private.presence_devices enable row level security;
revoke all on pulse_private.presence_settings,pulse_private.presence_devices from public,anon,authenticated;
create policy presence_settings_private on pulse_private.presence_settings for all to anon,authenticated using(false) with check(false);
create policy presence_devices_private on pulse_private.presence_devices for all to anon,authenticated using(false) with check(false);
create function pulse_private.presence_tick(p_device uuid,p_sequence bigint,p_active boolean) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform pulse_private.require_active();
 perform pulse_private.social_rate('presence_tick',120,60);
 if p_device is null or p_sequence is null or p_sequence<1 or p_active is null then raise exception 'Invalid presence update';end if;
 insert into pulse_private.presence_devices(user_id,device_id,sequence,seen_at,expires_at)
 values(auth.uid(),p_device,p_sequence,clock_timestamp(),case when p_active then clock_timestamp()+interval '70 seconds' else clock_timestamp() end)
 on conflict(user_id,device_id) do update set sequence=excluded.sequence,seen_at=excluded.seen_at,expires_at=excluded.expires_at
 where excluded.sequence>pulse_private.presence_devices.sequence;
 delete from pulse_private.presence_devices where user_id=auth.uid() and seen_at<now()-interval '7 days';
 return jsonb_build_object('sharing',coalesce((select sharing from pulse_private.presence_settings where user_id=auth.uid()),true));
end $$;
create function pulse_private.presence_info(p_users uuid[]) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform pulse_private.require_active();
 if p_users is null or cardinality(p_users)>200 then raise exception 'Select up to 200 people';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('user_id',q.user_id,'online',q.expires_at>now(),'expires_in',greatest(0,least(70,extract(epoch from q.expires_at-now())))::integer,'last_seen',q.seen_at)) from (
 select d.user_id,max(d.expires_at) expires_at,max(d.seen_at) seen_at from pulse_private.presence_devices d
 where d.user_id=any(p_users) and (
 d.user_id=auth.uid() or (
 coalesce((select sharing from pulse_private.presence_settings s where s.user_id=d.user_id),true)
 and not pulse_private.social_blocked(d.user_id)
 and not exists(select 1 from pulse_private.account_limits l where l.user_id=d.user_id and (l.state='banned' or l.state='suspended' and l.until_at>now()))
 and (exists(select 1 from public.pulse_members a join public.pulse_members b on b.chat_id=a.chat_id join public.pulse_chats c on c.id=a.chat_id
 where a.user_id=auth.uid() and b.user_id=d.user_id and c.kind='direct' and not exists(select 1 from public.pulse_chat_requests r where r.chat_id=c.id and r.state<>'accepted'))
 or exists(select 1 from public.pulse_social_follows f where f.follower_id=auth.uid() and f.creator_id=d.user_id and f.state='accepted'))))
 group by d.user_id)q),'[]'::jsonb);
end $$;
create function pulse_private.presence_sharing(p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform pulse_private.require_active();
 if p_enabled is null then raise exception 'Choose a privacy setting';end if;
 insert into pulse_private.presence_settings(user_id,sharing) values(auth.uid(),p_enabled) on conflict(user_id) do update set sharing=excluded.sharing;
end $$;
create function public.pulse_presence_tick(p_device uuid,p_sequence bigint,p_active boolean) returns jsonb language sql security invoker set search_path='' as $$select pulse_private.presence_tick(p_device,p_sequence,p_active)$$;
create function public.pulse_presence_info(p_users uuid[]) returns jsonb language sql stable security invoker set search_path='' as $$select pulse_private.presence_info(p_users)$$;
create function public.pulse_presence_sharing(p_enabled boolean) returns void language sql security invoker set search_path='' as $$select pulse_private.presence_sharing(p_enabled)$$;
revoke all on function pulse_private.presence_tick(uuid,bigint,boolean),pulse_private.presence_info(uuid[]),pulse_private.presence_sharing(boolean),public.pulse_presence_tick(uuid,bigint,boolean),public.pulse_presence_info(uuid[]),public.pulse_presence_sharing(boolean) from public,anon;
grant execute on function pulse_private.presence_tick(uuid,bigint,boolean),pulse_private.presence_info(uuid[]),pulse_private.presence_sharing(boolean),public.pulse_presence_tick(uuid,bigint,boolean),public.pulse_presence_info(uuid[]),public.pulse_presence_sharing(boolean) to authenticated;
notify pgrst,'reload schema';
commit;
