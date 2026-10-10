-- Pulse 0.2: channel administration, reactions, live sessions and moderated chat.
alter table public.pulse_channels add column avatar_path text;
create table public.pulse_channel_admins (
 channel_id uuid references public.pulse_channels on delete cascade,
 user_id uuid references public.pulse_profiles on delete cascade,
 primary key(channel_id,user_id)
);
create table public.pulse_post_reactions (
 post_id uuid references public.pulse_posts on delete cascade,
 user_id uuid references public.pulse_profiles on delete cascade,
 emoji text not null check(emoji in ('❤️','🔥','👏','👍','🎉')),
 primary key(post_id,user_id)
);
create table public.pulse_live_sessions (
 id uuid primary key default gen_random_uuid(), channel_id uuid not null references public.pulse_channels on delete cascade,
 host_id uuid not null references public.pulse_profiles,
 title text not null check(length(title) between 1 and 100),
 status text not null default 'live' check(status in ('live','ended')),
 created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '90 seconds',
 ended_at timestamptz
);
create index pulse_live_channel on public.pulse_live_sessions(channel_id,created_at desc);
create table public.pulse_live_chat (
 id uuid primary key, session_id uuid not null references public.pulse_live_sessions on delete cascade,
 user_id uuid not null references public.pulse_profiles,
 body text not null check(length(body) between 1 and 500),
 created_at timestamptz not null default now(), hidden boolean not null default false
);
create index pulse_live_chat_time on public.pulse_live_chat(session_id,created_at desc);
create index pulse_live_chat_user on public.pulse_live_chat(user_id,created_at desc);
alter table public.pulse_channel_admins enable row level security;
alter table public.pulse_post_reactions enable row level security;
alter table public.pulse_live_sessions enable row level security;
alter table public.pulse_live_chat enable row level security;
create policy channel_admins_read on public.pulse_channel_admins for select to authenticated using(true);
create policy post_reactions_read on public.pulse_post_reactions for select to authenticated using(true);
create policy live_sessions_read on public.pulse_live_sessions for select to authenticated using(true);
create policy live_chat_read on public.pulse_live_chat for select to authenticated using(not hidden);
revoke all on public.pulse_channel_admins,public.pulse_post_reactions,public.pulse_live_sessions,public.pulse_live_chat from anon,authenticated;
grant select on public.pulse_channel_admins,public.pulse_post_reactions,public.pulse_live_sessions,public.pulse_live_chat to authenticated;
create function pulse_private.channel_admin(p_channel uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (exists(select 1 from public.pulse_channels where id=p_channel and owner_id=auth.uid()) or exists(select 1 from public.pulse_channel_admins where channel_id=p_channel and user_id=auth.uid()));
$$;
create or replace function pulse_private.channel_post(p_channel uuid,p_body text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not pulse_private.channel_admin(p_channel) then raise exception 'Channel administrator required'; end if;
 if exists(select 1 from public.pulse_posts where author_id=auth.uid() and created_at>now()-interval '5 seconds') then raise exception 'Please wait before posting again'; end if;
 insert into public.pulse_posts(channel_id,author_id,body) values(p_channel,auth.uid(),trim(p_body));
end $$;
create function pulse_private.channel_update(p_channel uuid,p_name text,p_description text,p_avatar text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not pulse_private.channel_admin(p_channel) then raise exception 'Channel administrator required'; end if;
 if p_avatar is not null and p_avatar is distinct from (select avatar_path from public.pulse_channels where id=p_channel) and p_avatar not like auth.uid()::text||'/%' then raise exception 'Own uploaded image required'; end if;
 update public.pulse_channels set name=trim(p_name),description=trim(p_description),avatar_path=p_avatar where id=p_channel;
end $$;
create function pulse_private.channel_set_admin(p_channel uuid,p_user uuid,p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.pulse_channels where id=p_channel and owner_id=auth.uid()) then raise exception 'Channel owner required'; end if;
 if p_enabled then insert into public.pulse_channel_admins values(p_channel,p_user) on conflict do nothing;
 else delete from public.pulse_channel_admins where channel_id=p_channel and user_id=p_user; end if;
end $$;
create function pulse_private.post_react(p_post uuid,p_emoji text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_emoji is null then delete from public.pulse_post_reactions where post_id=p_post and user_id=auth.uid();
 else insert into public.pulse_post_reactions values(p_post,auth.uid(),p_emoji) on conflict(post_id,user_id) do update set emoji=excluded.emoji; end if;
end $$;
create function pulse_private.live_start(p_channel uuid,p_title text) returns uuid language plpgsql security definer set search_path='' as $$
declare sid uuid;
begin
 if not pulse_private.channel_admin(p_channel) then raise exception 'Channel administrator required'; end if;
 perform 1 from public.pulse_channels where id=p_channel for update;
 if exists(select 1 from public.pulse_live_sessions where channel_id=p_channel and status='live' and expires_at>now()) then raise exception 'This channel is already live'; end if;
 update public.pulse_live_sessions set status='ended',ended_at=now() where channel_id=p_channel and status='live';
 insert into public.pulse_live_sessions(channel_id,host_id,title) values(p_channel,auth.uid(),trim(p_title)) returning id into sid;
 return sid;
end $$;
create function pulse_private.live_touch(p_session uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.pulse_live_sessions set expires_at=now()+interval '90 seconds' where id=p_session and host_id=auth.uid() and status='live' and expires_at>now();
 if not found then raise exception 'Live session ended or host required'; end if;
end $$;
create function pulse_private.live_end(p_session uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.pulse_live_sessions where id=p_session and (host_id=auth.uid() or pulse_private.channel_admin(channel_id))) then raise exception 'Administrator required'; end if;
 update public.pulse_live_sessions set status='ended',ended_at=now(),expires_at=now() where id=p_session;
end $$;
create function pulse_private.live_chat_send(p_session uuid,p_id uuid,p_body text) returns void language plpgsql security definer set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 -- Lock the session for rate-limit serialization and to serialize with live_end.
 select channel_id into cid from public.pulse_live_sessions where id=p_session and status='live' and expires_at>now() for update;
 if cid is null then raise exception 'Chat is available only while live'; end if;
 if not pulse_private.channel_admin(cid) and not exists(select 1 from public.pulse_followers where channel_id=cid and user_id=auth.uid()) then raise exception 'Follow this channel to chat'; end if;
 if exists(select 1 from public.pulse_live_chat where id=p_id and user_id=auth.uid() and session_id=p_session) then return; end if;
 if exists(select 1 from public.pulse_live_chat where user_id=auth.uid() and created_at>now()-interval '2 seconds') or (select count(*) from public.pulse_live_chat where user_id=auth.uid() and created_at>now()-interval '1 minute')>=10 then raise exception 'Slow down: live chat rate limit'; end if;
 insert into public.pulse_live_chat(id,session_id,user_id,body) values(p_id,p_session,auth.uid(),trim(p_body));
end $$;
create function pulse_private.live_chat_hide(p_message uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.pulse_live_chat m join public.pulse_live_sessions s on s.id=m.session_id where m.id=p_message and pulse_private.channel_admin(s.channel_id)) then raise exception 'Administrator required'; end if;
 update public.pulse_live_chat set hidden=true where id=p_message;
end $$;

revoke all on function pulse_private.channel_admin(uuid) from public,anon,authenticated;
grant execute on function pulse_private.channel_admin(uuid) to authenticated;
create function public.pulse_channel_admin(p_channel uuid) returns boolean language sql security invoker set search_path='' as $$ select pulse_private.channel_admin(p_channel) $$;
revoke all on function public.pulse_channel_admin(uuid) from public,anon,authenticated;
grant execute on function public.pulse_channel_admin(uuid) to authenticated;

revoke all on function pulse_private.channel_update(uuid,text,text,text) from public,anon,authenticated;
grant execute on function pulse_private.channel_update(uuid,text,text,text) to authenticated;
create function public.pulse_channel_update(p_channel uuid,p_name text,p_description text,p_avatar text) returns void language sql security invoker set search_path='' as $$ select pulse_private.channel_update(p_channel,p_name,p_description,p_avatar) $$;
revoke all on function public.pulse_channel_update(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.pulse_channel_update(uuid,text,text,text) to authenticated;

revoke all on function pulse_private.channel_set_admin(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function pulse_private.channel_set_admin(uuid,uuid,boolean) to authenticated;
create function public.pulse_channel_set_admin(p_channel uuid,p_user uuid,p_enabled boolean) returns void language sql security invoker set search_path='' as $$ select pulse_private.channel_set_admin(p_channel,p_user,p_enabled) $$;
revoke all on function public.pulse_channel_set_admin(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function public.pulse_channel_set_admin(uuid,uuid,boolean) to authenticated;

revoke all on function pulse_private.post_react(uuid,text) from public,anon,authenticated;
grant execute on function pulse_private.post_react(uuid,text) to authenticated;
create function public.pulse_post_react(p_post uuid,p_emoji text) returns void language sql security invoker set search_path='' as $$ select pulse_private.post_react(p_post,p_emoji) $$;
revoke all on function public.pulse_post_react(uuid,text) from public,anon,authenticated;
grant execute on function public.pulse_post_react(uuid,text) to authenticated;

revoke all on function pulse_private.live_start(uuid,text) from public,anon,authenticated;
grant execute on function pulse_private.live_start(uuid,text) to authenticated;
create function public.pulse_live_start(p_channel uuid,p_title text) returns uuid language sql security invoker set search_path='' as $$ select pulse_private.live_start(p_channel,p_title) $$;
revoke all on function public.pulse_live_start(uuid,text) from public,anon,authenticated;
grant execute on function public.pulse_live_start(uuid,text) to authenticated;

revoke all on function pulse_private.live_touch(uuid) from public,anon,authenticated;
grant execute on function pulse_private.live_touch(uuid) to authenticated;
create function public.pulse_live_touch(p_session uuid) returns void language sql security invoker set search_path='' as $$ select pulse_private.live_touch(p_session) $$;
revoke all on function public.pulse_live_touch(uuid) from public,anon,authenticated;
grant execute on function public.pulse_live_touch(uuid) to authenticated;

revoke all on function pulse_private.live_end(uuid) from public,anon,authenticated;
grant execute on function pulse_private.live_end(uuid) to authenticated;
create function public.pulse_live_end(p_session uuid) returns void language sql security invoker set search_path='' as $$ select pulse_private.live_end(p_session) $$;
revoke all on function public.pulse_live_end(uuid) from public,anon,authenticated;
grant execute on function public.pulse_live_end(uuid) to authenticated;

revoke all on function pulse_private.live_chat_send(uuid,uuid,text) from public,anon,authenticated;
grant execute on function pulse_private.live_chat_send(uuid,uuid,text) to authenticated;
create function public.pulse_live_chat_send(p_session uuid,p_id uuid,p_body text) returns void language sql security invoker set search_path='' as $$ select pulse_private.live_chat_send(p_session,p_id,p_body) $$;
revoke all on function public.pulse_live_chat_send(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.pulse_live_chat_send(uuid,uuid,text) to authenticated;

revoke all on function pulse_private.live_chat_hide(uuid) from public,anon,authenticated;
grant execute on function pulse_private.live_chat_hide(uuid) to authenticated;
create function public.pulse_live_chat_hide(p_message uuid) returns void language sql security invoker set search_path='' as $$ select pulse_private.live_chat_hide(p_message) $$;
revoke all on function public.pulse_live_chat_hide(uuid) from public,anon,authenticated;
grant execute on function public.pulse_live_chat_hide(uuid) to authenticated;
