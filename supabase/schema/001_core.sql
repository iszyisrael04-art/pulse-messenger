-- Applied to Pulse using the Supabase migration API. Public wrappers are invokers.
create schema if not exists pulse_private;
revoke all on schema pulse_private from public, anon;
grant usage on schema pulse_private to authenticated, service_role;
create table public.pulse_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 username text unique check (username ~ '^[a-z][a-z0-9_]{2,23}$'),
 display_name text not null default 'Pulse user' check(length(display_name) between 1 and 60),
 bio text not null default '' check(length(bio)<=300), avatar_path text,
 created_at timestamptz not null default now()
);
create table public.pulse_chats (
 id uuid primary key default gen_random_uuid(), kind text not null check(kind in ('direct','group')),
 name text not null check(length(name) between 1 and 80), owner_id uuid not null references public.pulse_profiles,
 direct_key text unique, created_at timestamptz not null default now()
);
create table public.pulse_members (
 chat_id uuid references public.pulse_chats on delete cascade,
 user_id uuid references public.pulse_profiles on delete cascade,
 role text not null default 'member' check(role in ('owner','admin','member')),
 joined_at timestamptz not null default now(), primary key(chat_id,user_id)
);
create index pulse_members_user on public.pulse_members(user_id,chat_id);
create table public.pulse_messages (
 id uuid primary key, chat_id uuid not null references public.pulse_chats on delete cascade,
 sender_id uuid not null references public.pulse_profiles, body text not null check(length(body)<=8000),
 reply_to uuid references public.pulse_messages, attachment_path text,
 created_at timestamptz not null default now(), edited_at timestamptz, deleted_at timestamptz
);
create index pulse_messages_chat_time on public.pulse_messages(chat_id,created_at);
create table public.pulse_receipts (
 message_id uuid references public.pulse_messages on delete cascade, user_id uuid references public.pulse_profiles on delete cascade,
 delivered_at timestamptz not null default now(), read_at timestamptz,
 primary key(message_id,user_id)
);
create table public.pulse_reactions (
 message_id uuid references public.pulse_messages on delete cascade, user_id uuid references public.pulse_profiles on delete cascade,
 emoji text not null check(emoji in ('❤️','👍','😂','😮','😢','🙏')), primary key(message_id,user_id)
);
create table public.pulse_message_preferences (
 message_id uuid references public.pulse_messages on delete cascade, user_id uuid references public.pulse_profiles on delete cascade,
 hidden boolean not null default false, starred boolean not null default false, primary key(message_id,user_id)
);
create table public.pulse_blocks (
 user_id uuid references public.pulse_profiles on delete cascade, blocked_id uuid references public.pulse_profiles on delete cascade,
 primary key(user_id,blocked_id), check(user_id<>blocked_id)
);
create table public.pulse_statuses (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.pulse_profiles,
 body text not null check(length(body) between 1 and 1000), created_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '24 hours'
);
create table public.pulse_channels (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references public.pulse_profiles,
 name text not null check(length(name) between 1 and 80), description text not null default '' check(length(description)<=500),
 verified boolean not null default false, created_at timestamptz not null default now()
);
create table public.pulse_followers (
 channel_id uuid references public.pulse_channels on delete cascade, user_id uuid references public.pulse_profiles on delete cascade,
 primary key(channel_id,user_id)
);
create table public.pulse_posts (
 id uuid primary key default gen_random_uuid(), channel_id uuid not null references public.pulse_channels on delete cascade,
 author_id uuid not null references public.pulse_profiles, body text not null check(length(body) between 1 and 8000),
 created_at timestamptz not null default now()
);
create table public.pulse_reports (
 id uuid primary key default gen_random_uuid(), reporter_id uuid not null references public.pulse_profiles,
 reported_id uuid not null references public.pulse_profiles, reason text not null check(length(reason) between 1 and 1000),
 state text not null default 'open' check(state in ('open','reviewed','closed')), created_at timestamptz not null default now()
);
create table public.pulse_premium (
 user_id uuid primary key references public.pulse_profiles on delete cascade, expires_at timestamptz not null
);
create table pulse_private.promo_codes (
 code text primary key, days int not null check(days between 1 and 365), active boolean not null default true,
 expires_at timestamptz, max_uses int, uses int not null default 0
);
insert into pulse_private.promo_codes(code,days) values ('30DAYSPULSE',30);
create table pulse_private.redemptions (
 user_id uuid references public.pulse_profiles on delete cascade, code text references pulse_private.promo_codes,
 redeemed_at timestamptz not null default now(), primary key(user_id,code)
);
create table pulse_private.login_limits (key text primary key, started_at timestamptz not null, attempts int not null);
create table pulse_private.admins (user_id uuid primary key references auth.users on delete cascade);

create function pulse_private.is_member(cid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.pulse_members where chat_id=cid and user_id=auth.uid())
$$;
create function pulse_private.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from pulse_private.admins where user_id=auth.uid())
$$;
create function pulse_private.can_see_status(uid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (uid=auth.uid() or exists(
 select 1 from public.pulse_members a join public.pulse_members b using(chat_id)
 where a.user_id=uid and b.user_id=auth.uid()))
 and not exists(select 1 from public.pulse_blocks where (user_id=uid and blocked_id=auth.uid()) or (blocked_id=uid and user_id=auth.uid()))
$$;
create function pulse_private.bootstrap() returns trigger language plpgsql security definer set search_path='' as $$
 begin insert into public.pulse_profiles(id) values(new.id); return new; end
$$;
create trigger pulse_bootstrap after insert on auth.users for each row execute function pulse_private.bootstrap();
insert into public.pulse_profiles(id) select id from auth.users on conflict do nothing;

-- RLS is required even though mutations are handled through restricted RPCs.
alter table public.pulse_profiles enable row level security;
create policy profiles_read on public.pulse_profiles for select to authenticated using(true);
alter table public.pulse_chats enable row level security;
create policy chats_read on public.pulse_chats for select to authenticated using(pulse_private.is_member(id));
alter table public.pulse_members enable row level security;
create policy members_read on public.pulse_members for select to authenticated using(pulse_private.is_member(chat_id));
alter table public.pulse_messages enable row level security;
create policy messages_read on public.pulse_messages for select to authenticated using(pulse_private.is_member(chat_id));
alter table public.pulse_receipts enable row level security;
create policy receipts_read on public.pulse_receipts for select to authenticated using(exists(select 1 from public.pulse_messages where id=message_id));
alter table public.pulse_reactions enable row level security;
create policy reactions_read on public.pulse_reactions for select to authenticated using(exists(select 1 from public.pulse_messages where id=message_id));
alter table public.pulse_message_preferences enable row level security;
create policy preferences_read on public.pulse_message_preferences for select to authenticated using(user_id=auth.uid());
alter table public.pulse_blocks enable row level security;
create policy blocks_read on public.pulse_blocks for select to authenticated using(user_id=auth.uid());
alter table public.pulse_statuses enable row level security;
create policy statuses_read on public.pulse_statuses for select to authenticated using(expires_at>now() and pulse_private.can_see_status(user_id));
alter table public.pulse_channels enable row level security;
create policy channels_read on public.pulse_channels for select to authenticated using(true);
alter table public.pulse_followers enable row level security;
create policy followers_read on public.pulse_followers for select to authenticated using(true);
alter table public.pulse_posts enable row level security;
create policy posts_read on public.pulse_posts for select to authenticated using(true);
alter table public.pulse_reports enable row level security;
create policy reports_read on public.pulse_reports for select to authenticated using(reporter_id=auth.uid() or pulse_private.is_admin());
alter table public.pulse_premium enable row level security;
create policy premium_read on public.pulse_premium for select to authenticated using(user_id=auth.uid());
alter table pulse_private.promo_codes enable row level security;
alter table pulse_private.redemptions enable row level security;
alter table pulse_private.admins enable row level security;
alter table pulse_private.login_limits enable row level security;

create function pulse_private.save_profile(p_username text,p_name text,p_bio text,p_avatar text) returns void language plpgsql security definer set search_path='' as $$
 begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_avatar is not null and split_part(p_avatar,'/',1)<>auth.uid()::text then raise exception 'Invalid avatar'; end if;
 update public.pulse_profiles set username=lower(trim(p_username)),display_name=trim(p_name),bio=p_bio,avatar_path=p_avatar where id=auth.uid();
 end
$$;
create function pulse_private.start_chat(p_users uuid[],p_name text,p_group boolean) returns uuid language plpgsql security definer set search_path='' as $$
 declare cid uuid; peer uuid; dk text; n int;
 begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select count(distinct u) into n from unnest(p_users) u where u<>auth.uid();
 if n<1 or n>100 then raise exception 'Choose 1 to 100 people'; end if;
 if exists(select 1 from public.pulse_blocks where (user_id=auth.uid() and blocked_id=any(p_users)) or (blocked_id=auth.uid() and user_id=any(p_users))) then raise exception 'Unavailable contact'; end if;
 if not p_group then
 if n<>1 then raise exception 'One recipient required'; end if;
 select u into peer from unnest(p_users) u where u<>auth.uid() limit 1;
 dk=least(peer::text,auth.uid()::text)||':'||greatest(peer::text,auth.uid()::text);
 perform pg_advisory_xact_lock(hashtextextended(dk,0));
 select id into cid from public.pulse_chats where direct_key=dk;
 if cid is not null then return cid; end if;
 end if;
 insert into public.pulse_chats(kind,name,owner_id,direct_key) values(case when p_group then 'group' else 'direct' end,p_name,auth.uid(),dk) returning id into cid;
 insert into public.pulse_members(chat_id,user_id,role) values(cid,auth.uid(),'owner');
 insert into public.pulse_members(chat_id,user_id) select cid,u from (select distinct unnest(p_users) u) x where u<>auth.uid();
 return cid;
 end
$$;
create function pulse_private.send_message(p_id uuid,p_chat uuid,p_body text,p_reply uuid,p_attachment text) returns uuid language plpgsql security definer set search_path='' as $$
 begin
 if not pulse_private.is_member(p_chat) then raise exception 'Chat unavailable'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,1));
 -- Retries with the same UUID are safe, but cannot overwrite another sender's message.
 if exists(select 1 from public.pulse_messages where id=p_id and sender_id=auth.uid() and chat_id=p_chat) then return p_id; end if;
 if exists(select 1 from public.pulse_messages where sender_id=auth.uid() and created_at>now()-interval '1 minute' having count(*)>=60) then raise exception 'Slow down; try again shortly'; end if;
 if exists(select 1 from public.pulse_members m join public.pulse_blocks b on (b.user_id=m.user_id and b.blocked_id=auth.uid()) or (b.blocked_id=m.user_id and b.user_id=auth.uid()) where m.chat_id=p_chat) then raise exception 'Unavailable contact'; end if;
 if p_reply is not null and not exists(select 1 from public.pulse_messages where id=p_reply and chat_id=p_chat) then raise exception 'Invalid reply'; end if;
 if p_attachment is not null and (split_part(p_attachment,'/',1)<>p_chat::text or split_part(p_attachment,'/',2)<>auth.uid()::text) then raise exception 'Invalid attachment'; end if;
 if length(trim(p_body))=0 and p_attachment is null then raise exception 'Empty message'; end if;
 insert into public.pulse_messages(id,chat_id,sender_id,body,reply_to,attachment_path) values(p_id,p_chat,auth.uid(),p_body,p_reply,p_attachment); return p_id;
 end
$$;
create function pulse_private.change_message(p_id uuid,p_body text,p_delete boolean) returns void language plpgsql security definer set search_path='' as $$
 begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 update public.pulse_messages set body=case when p_delete then '' else p_body end,attachment_path=case when p_delete then null else attachment_path end,
 edited_at=case when p_delete then edited_at else now() end,deleted_at=case when p_delete then now() else null end
 where id=p_id and sender_id=auth.uid() and deleted_at is null and pulse_private.is_member(chat_id);
 if not found then raise exception 'Message unavailable'; end if;
 end
$$;
create function pulse_private.mark_read(p_chat uuid) returns void language plpgsql security definer set search_path='' as $$
 begin
 if not pulse_private.is_member(p_chat) then raise exception 'Chat unavailable'; end if;
 insert into public.pulse_receipts(message_id,user_id,read_at)
 select id,auth.uid(),now() from public.pulse_messages where chat_id=p_chat and sender_id<>auth.uid()
 on conflict(message_id,user_id) do update set read_at=excluded.read_at;
 end
$$;
create function pulse_private.react(p_id uuid,p_emoji text) returns void language plpgsql security definer set search_path='' as $$
 begin
 if not exists(select 1 from public.pulse_messages where id=p_id and pulse_private.is_member(chat_id)) then raise exception 'Message unavailable'; end if;
 if p_emoji is null then delete from public.pulse_reactions where message_id=p_id and user_id=auth.uid();
 else insert into public.pulse_reactions values(p_id,auth.uid(),p_emoji) on conflict(message_id,user_id) do update set emoji=excluded.emoji; end if;
 end
$$;
create function pulse_private.message_pref(p_id uuid,p_hidden boolean,p_starred boolean) returns void language plpgsql security definer set search_path='' as $$
 begin
 if not exists(select 1 from public.pulse_messages where id=p_id and pulse_private.is_member(chat_id)) then raise exception 'Message unavailable'; end if;
 insert into public.pulse_message_preferences values(p_id,auth.uid(),p_hidden,p_starred) on conflict(message_id,user_id) do update set hidden=excluded.hidden,starred=excluded.starred;
 end
$$;
create function pulse_private.block_user(p_user uuid,p_block boolean) returns void language plpgsql security definer set search_path='' as $$
 begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_block then insert into public.pulse_blocks values(auth.uid(),p_user) on conflict do nothing;
 else delete from public.pulse_blocks where user_id=auth.uid() and blocked_id=p_user; end if;
 end
$$;
create function pulse_private.report_user(p_user uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
 begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if (select count(*) from public.pulse_reports where reporter_id=auth.uid() and created_at>now()-interval '1 day')>=10 then raise exception 'Report limit reached'; end if;
 insert into public.pulse_reports(reporter_id,reported_id,reason) values(auth.uid(),p_user,p_reason);
 end
$$;
create function pulse_private.post_status(p_body text) returns void language plpgsql security definer set search_path='' as $$
 begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if (select count(*) from public.pulse_statuses where user_id=auth.uid() and created_at>now()-interval '1 day')>=30 then raise exception 'Status limit reached'; end if;
 insert into public.pulse_statuses(user_id,body) values(auth.uid(),p_body);
 end
$$;
create function pulse_private.create_channel(p_name text,p_description text) returns uuid language plpgsql security definer set search_path='' as $$
 declare cid uuid;
 begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if (select count(*) from public.pulse_channels where owner_id=auth.uid())>=10 then raise exception 'Channel limit reached'; end if;
 insert into public.pulse_channels(owner_id,name,description) values(auth.uid(),p_name,p_description) returning id into cid; return cid;
 end
$$;
create function pulse_private.follow_channel(p_channel uuid,p_follow boolean) returns void language plpgsql security definer set search_path='' as $$
 begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_follow then insert into public.pulse_followers values(p_channel,auth.uid()) on conflict do nothing;
 else delete from public.pulse_followers where channel_id=p_channel and user_id=auth.uid(); end if;
 end
$$;
create function pulse_private.channel_post(p_channel uuid,p_body text) returns void language plpgsql security definer set search_path='' as $$
 begin
 if auth.uid() is null or not exists(select 1 from public.pulse_channels where id=p_channel and owner_id=auth.uid()) then raise exception 'Channel owner required'; end if;
 insert into public.pulse_posts(channel_id,author_id,body) values(p_channel,auth.uid(),p_body);
 end
$$;
create function pulse_private.redeem(p_code text) returns timestamptz language plpgsql security definer set search_path='' as $$
 declare promo pulse_private.promo_codes; expiry timestamptz;
 begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not exists(select 1 from auth.users where id=auth.uid() and (email_confirmed_at is not null or phone_confirmed_at is not null)) then raise exception 'Verify your email or phone first'; end if;
 select * into promo from pulse_private.promo_codes where code=upper(trim(p_code)) for update;
 if not found or not promo.active or (promo.expires_at is not null and promo.expires_at<=now()) or (promo.max_uses is not null and promo.uses>=promo.max_uses) then raise exception 'Code unavailable'; end if;
 if exists(select 1 from pulse_private.redemptions where user_id=auth.uid() and code=promo.code) then raise exception 'Code already redeemed'; end if;
 insert into pulse_private.redemptions(user_id,code) values(auth.uid(),promo.code);
 insert into public.pulse_premium(user_id,expires_at) values(auth.uid(),now()+make_interval(days=>promo.days))
 on conflict(user_id) do update set expires_at=greatest(public.pulse_premium.expires_at,now())+make_interval(days=>promo.days) returning expires_at into expiry;
 update pulse_private.promo_codes set uses=uses+1 where code=promo.code; return expiry;
 end
$$;
-- Username lookup is available only to the authenticated Edge service role.
create function pulse_private.login_lookup(p_username text,p_key text) returns text language plpgsql security definer set search_path='' as $$
 declare n int; email text;
 begin
 if (current_setting('request.jwt.claims',true)::jsonb->>'role') is distinct from 'service_role' then raise exception 'Service required'; end if;
 insert into pulse_private.login_limits(key,started_at,attempts) values(p_key,now(),1)
 on conflict(key) do update set started_at=case when pulse_private.login_limits.started_at<now()-interval '15 minutes' then now() else pulse_private.login_limits.started_at end,
 attempts=case when pulse_private.login_limits.started_at<now()-interval '15 minutes' then 1 else pulse_private.login_limits.attempts+1 end returning attempts into n;
 if n>20 then return null; end if;
 select u.email into email from public.pulse_profiles p join auth.users u on p.id=u.id where p.username=lower(p_username);
 return email;
 end
$$;

create function public.pulse_save_profile(p_username text,p_name text,p_bio text,p_avatar text) returns void language sql security invoker set search_path='' as $$ select pulse_private.save_profile(p_username,p_name,p_bio,p_avatar) $$;
revoke all on function public.pulse_save_profile(text,text,text,text) from public,anon,authenticated;
grant execute on function public.pulse_save_profile(text,text,text,text) to authenticated;

create function public.pulse_start_chat(p_users uuid[],p_name text,p_group boolean) returns uuid language sql security invoker set search_path='' as $$ select pulse_private.start_chat(p_users,p_name,p_group) $$;
revoke all on function public.pulse_start_chat(uuid[],text,boolean) from public,anon,authenticated;
grant execute on function public.pulse_start_chat(uuid[],text,boolean) to authenticated;

create function public.pulse_send_message(p_id uuid,p_chat uuid,p_body text,p_reply uuid,p_attachment text) returns uuid language sql security invoker set search_path='' as $$ select pulse_private.send_message(p_id,p_chat,p_body,p_reply,p_attachment) $$;
revoke all on function public.pulse_send_message(uuid,uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public.pulse_send_message(uuid,uuid,text,uuid,text) to authenticated;

create function public.pulse_change_message(p_id uuid,p_body text,p_delete boolean) returns void language sql security invoker set search_path='' as $$ select pulse_private.change_message(p_id,p_body,p_delete) $$;
revoke all on function public.pulse_change_message(uuid,text,boolean) from public,anon,authenticated;
grant execute on function public.pulse_change_message(uuid,text,boolean) to authenticated;

create function public.pulse_mark_read(p_chat uuid) returns void language sql security invoker set search_path='' as $$ select pulse_private.mark_read(p_chat) $$;
revoke all on function public.pulse_mark_read(uuid) from public,anon,authenticated;
grant execute on function public.pulse_mark_read(uuid) to authenticated;

create function public.pulse_react(p_id uuid,p_emoji text) returns void language sql security invoker set search_path='' as $$ select pulse_private.react(p_id,p_emoji) $$;
revoke all on function public.pulse_react(uuid,text) from public,anon,authenticated;
grant execute on function public.pulse_react(uuid,text) to authenticated;

create function public.pulse_message_pref(p_id uuid,p_hidden boolean,p_starred boolean) returns void language sql security invoker set search_path='' as $$ select pulse_private.message_pref(p_id,p_hidden,p_starred) $$;
revoke all on function public.pulse_message_pref(uuid,boolean,boolean) from public,anon,authenticated;
grant execute on function public.pulse_message_pref(uuid,boolean,boolean) to authenticated;

create function public.pulse_block_user(p_user uuid,p_block boolean) returns void language sql security invoker set search_path='' as $$ select pulse_private.block_user(p_user,p_block) $$;
revoke all on function public.pulse_block_user(uuid,boolean) from public,anon,authenticated;
grant execute on function public.pulse_block_user(uuid,boolean) to authenticated;

create function public.pulse_report_user(p_user uuid,p_reason text) returns void language sql security invoker set search_path='' as $$ select pulse_private.report_user(p_user,p_reason) $$;
revoke all on function public.pulse_report_user(uuid,text) from public,anon,authenticated;
grant execute on function public.pulse_report_user(uuid,text) to authenticated;

create function public.pulse_post_status(p_body text) returns void language sql security invoker set search_path='' as $$ select pulse_private.post_status(p_body) $$;
revoke all on function public.pulse_post_status(text) from public,anon,authenticated;
grant execute on function public.pulse_post_status(text) to authenticated;

create function public.pulse_create_channel(p_name text,p_description text) returns uuid language sql security invoker set search_path='' as $$ select pulse_private.create_channel(p_name,p_description) $$;
revoke all on function public.pulse_create_channel(text,text) from public,anon,authenticated;
grant execute on function public.pulse_create_channel(text,text) to authenticated;

create function public.pulse_follow_channel(p_channel uuid,p_follow boolean) returns void language sql security invoker set search_path='' as $$ select pulse_private.follow_channel(p_channel,p_follow) $$;
revoke all on function public.pulse_follow_channel(uuid,boolean) from public,anon,authenticated;
grant execute on function public.pulse_follow_channel(uuid,boolean) to authenticated;

create function public.pulse_channel_post(p_channel uuid,p_body text) returns void language sql security invoker set search_path='' as $$ select pulse_private.channel_post(p_channel,p_body) $$;
revoke all on function public.pulse_channel_post(uuid,text) from public,anon,authenticated;
grant execute on function public.pulse_channel_post(uuid,text) to authenticated;

create function public.pulse_redeem(p_code text) returns timestamptz language sql security invoker set search_path='' as $$ select pulse_private.redeem(p_code) $$;
revoke all on function public.pulse_redeem(text) from public,anon,authenticated;
grant execute on function public.pulse_redeem(text) to authenticated;

create function public.pulse_login_lookup(p_username text,p_key text) returns text language sql security invoker set search_path='' as $$ select pulse_private.login_lookup(p_username,p_key) $$;
revoke all on function public.pulse_login_lookup(text,text) from public,anon,authenticated;
grant execute on function public.pulse_login_lookup(text,text) to service_role;

revoke all on all functions in schema pulse_private from public,anon,authenticated;
grant execute on function pulse_private.is_member(uuid),pulse_private.is_admin(),pulse_private.can_see_status(uuid) to authenticated;
grant execute on function pulse_private.save_profile(text,text,text,text) to authenticated;
grant execute on function pulse_private.start_chat(uuid[],text,boolean) to authenticated;
grant execute on function pulse_private.send_message(uuid,uuid,text,uuid,text) to authenticated;
grant execute on function pulse_private.change_message(uuid,text,boolean) to authenticated;
grant execute on function pulse_private.mark_read(uuid) to authenticated;
grant execute on function pulse_private.react(uuid,text) to authenticated;
grant execute on function pulse_private.message_pref(uuid,boolean,boolean) to authenticated;
grant execute on function pulse_private.block_user(uuid,boolean) to authenticated;
grant execute on function pulse_private.report_user(uuid,text) to authenticated;
grant execute on function pulse_private.post_status(text) to authenticated;
grant execute on function pulse_private.create_channel(text,text) to authenticated;
grant execute on function pulse_private.follow_channel(uuid,boolean) to authenticated;
grant execute on function pulse_private.channel_post(uuid,text) to authenticated;
grant execute on function pulse_private.redeem(text) to authenticated;
grant execute on function pulse_private.login_lookup(text,text) to service_role;

revoke all on all tables in schema pulse_private from anon,authenticated;
revoke all on public.pulse_profiles,public.pulse_chats,public.pulse_members,public.pulse_messages,public.pulse_receipts,public.pulse_reactions,public.pulse_message_preferences,public.pulse_blocks,public.pulse_statuses,public.pulse_channels,public.pulse_followers,public.pulse_posts,public.pulse_reports,public.pulse_premium from anon,authenticated;
grant select on public.pulse_profiles,public.pulse_chats,public.pulse_members,public.pulse_messages,public.pulse_receipts,public.pulse_reactions,public.pulse_message_preferences,public.pulse_blocks,public.pulse_statuses,public.pulse_channels,public.pulse_followers,public.pulse_posts,public.pulse_reports,public.pulse_premium to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
('pulse-avatars','pulse-avatars',false,2097152,array['image/jpeg','image/png','image/webp']),
('pulse-media','pulse-media',false,10485760,null);
create policy pulse_avatar_read on storage.objects for select to authenticated using(bucket_id='pulse-avatars');
create policy pulse_avatar_insert on storage.objects for insert to authenticated with check(bucket_id='pulse-avatars' and (storage.foldername(name))[1]=auth.uid()::text);
create policy pulse_media_read on storage.objects for select to authenticated using(bucket_id='pulse-media' and pulse_private.is_member(((storage.foldername(name))[1])::uuid));
create policy pulse_media_insert on storage.objects for insert to authenticated with check(bucket_id='pulse-media' and (storage.foldername(name))[2]=auth.uid()::text and pulse_private.is_member(((storage.foldername(name))[1])::uuid));
alter publication supabase_realtime add table public.pulse_messages,public.pulse_chats,public.pulse_receipts,public.pulse_reactions,public.pulse_posts;
