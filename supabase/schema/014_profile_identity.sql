begin;
-- Additive private-beta upgrade. Existing accounts and conversations are untouched.
create table if not exists pulse_private.policy_acceptances (
 user_id uuid primary key references auth.users(id) on delete cascade,
 version text not null, accepted_at timestamptz not null default now()
);
alter table pulse_private.policy_acceptances enable row level security;
revoke all on pulse_private.policy_acceptances from public,anon,authenticated;
create or replace function pulse_private.capture_policy_acceptance() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 -- New clients record an explicit acknowledgement. Legacy clients remain compatible.
 if new.raw_user_meta_data->>'privacy_version'='2026-10-17'
 and new.raw_user_meta_data->'privacy_accepted'='true'::jsonb then
   insert into pulse_private.policy_acceptances(user_id,version)
   values(new.id,'2026-10-17') on conflict do nothing;
 end if;
 return new;
end $$;
revoke all on function pulse_private.capture_policy_acceptance() from public,anon,authenticated;
create trigger pulse_capture_privacy after insert on auth.users
for each row execute function pulse_private.capture_policy_acceptance();

create table if not exists pulse_private.profile_signals (
 user_id uuid primary key references public.pulse_profiles(id) on delete cascade,
 body text not null default '' check(length(body)<=120),
 mode text not null default 'creating' check(mode in ('creating','collaborating','learning','available')),
 updated_at timestamptz not null default now()
);
alter table pulse_private.profile_signals enable row level security;
revoke all on pulse_private.profile_signals from public,anon,authenticated;
alter table public.pulse_social_accounts drop constraint pulse_social_accounts_profile_theme_check;
alter table public.pulse_social_accounts add constraint pulse_social_accounts_profile_theme_check
 check(profile_theme in ('classic','aurora','sunset','midnight','ocean','bloom','paper','circuit'));
create or replace function pulse_private.social_set_profile_style(p_theme text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_theme is null or p_theme not in ('classic','aurora','sunset','midnight','ocean','bloom','paper','circuit') then raise exception 'Unknown profile background'; end if;
 if p_theme<>'classic' and not exists(select 1 from public.pulse_premium where user_id=auth.uid() and expires_at>now()) then raise exception 'This profile background requires Pulse Premium'; end if;
 insert into public.pulse_social_accounts(user_id,profile_theme) values(auth.uid(),p_theme)
 on conflict(user_id) do update set profile_theme=excluded.profile_theme;
end $$;

create or replace function pulse_private.profile_features(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare expiry timestamptz; signal pulse_private.profile_signals;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_user is null or pulse_private.social_blocked(p_user) or not exists(select 1 from public.pulse_profiles where id=p_user) then return null; end if;
 select expires_at into expiry from public.pulse_premium where user_id=p_user and expires_at>now();
 select * into signal from pulse_private.profile_signals where user_id=p_user;
 return jsonb_build_object('background',pulse_private.social_profile_style(p_user),
 'motion_until',case when expiry is not null then least(expiry,now()+interval '60 seconds') else null end,
 'signal',case when expiry is not null then coalesce(signal.body,'') else '' end,
 'mode',coalesce(signal.mode,'creating'));
end $$;
create or replace function public.pulse_profile_features(p_user uuid) returns jsonb
language sql stable security invoker set search_path='' as $$ select pulse_private.profile_features(p_user) $$;
create or replace function pulse_private.profile_features_save(p_background text,p_signal text,p_mode text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_signal is null or length(p_signal)>120 or p_mode is null or p_mode not in ('creating','collaborating','learning','available') then raise exception 'Choose a valid Profile Signal of up to 120 characters'; end if;
 perform pulse_private.social_rate('profile_features',30,60);
 if trim(p_signal)<>'' and not exists(select 1 from public.pulse_premium where user_id=auth.uid() and expires_at>now()) then raise exception 'Profile Signals require Pulse Premium'; end if;
 perform pulse_private.social_set_profile_style(p_background);
 insert into pulse_private.profile_signals(user_id,body,mode) values(auth.uid(),trim(p_signal),p_mode)
 on conflict(user_id) do update set body=excluded.body,mode=excluded.mode,updated_at=now();
end $$;
create or replace function public.pulse_profile_features_save(p_background text,p_signal text,p_mode text) returns void
language sql security invoker set search_path='' as $$ select pulse_private.profile_features_save(p_background,p_signal,p_mode) $$;
revoke all on function pulse_private.profile_features(uuid),public.pulse_profile_features(uuid),
 pulse_private.profile_features_save(text,text,text),public.pulse_profile_features_save(text,text,text) from public,anon;
grant execute on function pulse_private.profile_features(uuid),public.pulse_profile_features(uuid),
 pulse_private.profile_features_save(text,text,text),public.pulse_profile_features_save(text,text,text) to authenticated;

create or replace function pulse_private.avatar_upload_allowed(p_name text,p_mime text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and split_part(p_name,'/',1)=auth.uid()::text
 and (p_mime in ('image/jpeg','image/png','image/webp','image/gif'))
 and ((p_mime<>'image/gif' and lower(p_name) not like '%.gif')
 or exists(select 1 from public.pulse_premium where user_id=auth.uid() and expires_at>now()))
$$;
revoke all on function pulse_private.avatar_upload_allowed(text,text) from public,anon;
grant execute on function pulse_private.avatar_upload_allowed(text,text) to authenticated;
update storage.buckets set allowed_mime_types=array['image/jpeg','image/png','image/webp','image/gif']
 where id='pulse-avatars';
drop policy pulse_avatar_insert on storage.objects;
create policy pulse_avatar_insert on storage.objects for insert to authenticated
with check(bucket_id='pulse-avatars' and pulse_private.avatar_upload_allowed(name,metadata->>'mimetype'));
-- Attaching a stored GIF is gated too, including after an entitlement expires.
create or replace function pulse_private.save_profile(p_username text,p_name text,p_bio text,p_avatar text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_username is null or lower(trim(p_username)) !~ '^[a-z][a-z0-9_]{2,23}$' or p_name is null or length(trim(p_name)) not between 1 and 60 or p_bio is null or length(p_bio)>300 then raise exception 'Check your username, name and bio'; end if;
 if p_avatar is not null then
   if split_part(p_avatar,'/',1)<>auth.uid()::text then raise exception 'Invalid avatar'; end if;
   -- Existing static pictures remain editable. A changed GIF must be owned and Premium.
   if p_avatar is distinct from (select avatar_path from public.pulse_profiles where id=auth.uid()) then
     if not exists(select 1 from storage.objects where bucket_id='pulse-avatars' and name=p_avatar
       and pulse_private.avatar_upload_allowed(name,metadata->>'mimetype')) then raise exception 'Choose your own uploaded photo. Animated GIFs require Premium'; end if;
   end if;
 end if;
 update public.pulse_profiles set username=lower(trim(p_username)),display_name=trim(p_name),bio=p_bio,avatar_path=p_avatar where id=auth.uid();
end $$;
notify pgrst,'reload schema';
commit;
