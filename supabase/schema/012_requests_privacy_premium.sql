begin;
-- New direct conversations require recipient consent; existing chats are preserved.
create table if not exists public.pulse_chat_requests (
 chat_id uuid primary key references public.pulse_chats on delete cascade,
 sender_id uuid not null references public.pulse_profiles,
 recipient_id uuid not null references public.pulse_profiles,
 state text not null default 'pending' check(state in ('pending','accepted','declined')),
 sent_at timestamptz,updated_at timestamptz not null default now(),check(sender_id<>recipient_id)
);
create index if not exists pulse_requests_recipient on public.pulse_chat_requests(recipient_id,state,sent_at desc);
alter table public.pulse_chat_requests enable row level security;
revoke all on public.pulse_chat_requests from public,anon,authenticated;
grant select on public.pulse_chat_requests to authenticated;
create policy chat_requests_own on public.pulse_chat_requests for select to authenticated using((sender_id=(select auth.uid()) or recipient_id=(select auth.uid())) and pulse_private.is_member(chat_id));
create or replace function pulse_private.chat_request_new_member() returns trigger language plpgsql security definer set search_path='' as $$
 declare c public.pulse_chats;
 begin
 select * into c from public.pulse_chats where id=new.chat_id;
 if c.kind='direct' and new.user_id<>c.owner_id then
 insert into public.pulse_chat_requests(chat_id,sender_id,recipient_id) values(c.id,c.owner_id,new.user_id) on conflict do nothing;
 end if;
 return new;
 end
$$;
revoke all on function pulse_private.chat_request_new_member() from public,anon,authenticated;
create trigger pulse_new_chat_request after insert on public.pulse_members for each row execute function pulse_private.chat_request_new_member();
create or replace function pulse_private.request_can_send(p_chat uuid) returns boolean language sql stable security definer set search_path='' as $$
 select pulse_private.is_member(p_chat) and not exists(select 1 from public.pulse_chat_requests r where r.chat_id=p_chat and (r.state='declined' or r.state='pending' and r.recipient_id=auth.uid()))
$$;
revoke all on function pulse_private.request_can_send(uuid) from public,anon;
grant execute on function pulse_private.request_can_send(uuid) to authenticated;
create or replace function pulse_private.guard_request_message() returns trigger language plpgsql security definer set search_path='' as $$
 begin
 if not pulse_private.request_can_send(new.chat_id) then raise exception 'Accept the message request before replying, or this request was declined'; end if;
 update public.pulse_chat_requests set sent_at=coalesce(sent_at,now()),updated_at=now() where chat_id=new.chat_id and sender_id=auth.uid();
 return new;
 end
$$;
revoke all on function pulse_private.guard_request_message() from public,anon,authenticated;
create trigger pulse_request_message_guard before insert on public.pulse_messages for each row execute function pulse_private.guard_request_message();
create or replace function pulse_private.guard_request_call() returns trigger language plpgsql security definer set search_path='' as $$
 begin
 if exists(select 1 from public.pulse_chat_requests where chat_id=new.chat_id and state<>'accepted') then raise exception 'Calls are available after the message request is accepted'; end if;
 return new;
 end
$$;
revoke all on function pulse_private.guard_request_call() from public,anon,authenticated;
create trigger pulse_request_call_guard before insert on public.pulse_calls for each row execute function pulse_private.guard_request_call();
create or replace function pulse_private.respond_request(p_chat uuid,p_accept boolean) returns void language plpgsql security definer set search_path='' as $$
 begin
 if auth.uid() is null or p_accept is null then raise exception 'Sign in required'; end if;
 update public.pulse_chat_requests set state=case when p_accept then 'accepted' else 'declined' end,updated_at=now() where chat_id=p_chat and recipient_id=auth.uid() and state='pending' and pulse_private.is_member(chat_id);
 if not found then raise exception 'Message request unavailable'; end if;
 end
$$;
create or replace function public.pulse_respond_request(p_chat uuid,p_accept boolean) returns void language sql security invoker set search_path='' as $$ select pulse_private.respond_request(p_chat,p_accept) $$;
revoke all on function pulse_private.respond_request(uuid,boolean),public.pulse_respond_request(uuid,boolean) from public,anon;
grant execute on function pulse_private.respond_request(uuid,boolean),public.pulse_respond_request(uuid,boolean) to authenticated;
create or replace function pulse_private.unread_counts() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_object_agg(chat_id,n),'{}'::jsonb) from (
 select m.chat_id,count(*) n from public.pulse_messages m join public.pulse_members own on own.chat_id=m.chat_id and own.user_id=auth.uid()
 where m.sender_id<>auth.uid() and m.deleted_at is null and not exists(select 1 from public.pulse_receipts r where r.message_id=m.id and r.user_id=auth.uid() and r.read_at is not null)
 group by m.chat_id) counts
$$;
create or replace function public.pulse_unread_counts() returns jsonb language sql stable security invoker set search_path='' as $$ select pulse_private.unread_counts() $$;
revoke all on function pulse_private.unread_counts(),public.pulse_unread_counts() from public,anon;
grant execute on function pulse_private.unread_counts(),public.pulse_unread_counts() to authenticated;
-- A lost successful redemption response can be retried without granting again.
create or replace function pulse_private.redeem_result(p_code text) returns jsonb language plpgsql security definer set search_path='' as $$
 declare expiry timestamptz; normalized text; was_used boolean;
 begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 normalized=upper(trim(p_code));
 if normalized is null or length(normalized) not between 1 and 40 then raise exception 'Enter a valid code'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||normalized,31));
 select exists(select 1 from pulse_private.redemptions where user_id=auth.uid() and code=normalized) into was_used;
 if was_used then
 select expires_at into expiry from public.pulse_premium where user_id=auth.uid();
 if expiry is null or expiry<=now() then raise exception 'This account already used this one-time code. Its Premium period has ended'; end if;
 else expiry=pulse_private.redeem(normalized); end if;
 return jsonb_build_object('expires_at',expiry,'already_redeemed',was_used);
 end
$$;
create or replace function public.pulse_redeem_result(p_code text) returns jsonb language sql security invoker set search_path='' as $$ select pulse_private.redeem_result(p_code) $$;
revoke all on function pulse_private.redeem_result(text),public.pulse_redeem_result(text) from public,anon;
grant execute on function pulse_private.redeem_result(text),public.pulse_redeem_result(text) to authenticated;
alter table public.pulse_social_content drop constraint pulse_social_content_audience_check;
alter table public.pulse_social_content add constraint pulse_social_content_audience_check check(audience in ('public','followers','private'));
create or replace function pulse_private.social_write(p_id uuid,p_kind text,p_body text,p_media jsonb,p_audience text,p_draft boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare m jsonb; mime text; total bigint; existing public.pulse_social_content;
begin
 perform pulse_private.social_rate('write',40,3600);
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,13));
 select * into existing from public.pulse_social_content where id=p_id for update;
 if found and (existing.author_id<>auth.uid() or existing.state='deleted') then raise exception 'Post unavailable'; end if;
 -- Retried publishing after an uncertain network response is idempotent. Editing is a separate RPC.
 if found and existing.state='published' then return p_id; end if;
 if p_id is null or p_kind is null or p_kind not in ('post','reel') or p_audience is null or p_audience not in ('public','followers','private') or p_draft is null or p_body is null or length(p_body)>4000 then raise exception 'Invalid post'; end if;
 if p_media is null or jsonb_typeof(p_media)<>'array' or jsonb_array_length(p_media)>8 then raise exception 'Choose up to 8 photos or one video'; end if;
 if p_kind='reel' and (jsonb_array_length(p_media)<>1 or p_media->0->>'kind' is distinct from 'video') then raise exception 'A Reel needs one video'; end if;
 if length(trim(p_body))=0 and jsonb_array_length(p_media)=0 then raise exception 'Add text or media'; end if;
 if exists(select 1 from jsonb_array_elements(p_media) x where x->>'kind'='video') and jsonb_array_length(p_media)<>1 then raise exception 'Upload one video per post'; end if;
 for m in select value from jsonb_array_elements(p_media) loop
 if m->>'kind' is null or m->>'kind' not in ('image','video') or m->>'path' is null or split_part(m->>'path','/',1)<>auth.uid()::text or split_part(m->>'path','/',2)<>p_id::text then raise exception 'Invalid media owner'; end if;
 select metadata->>'mimetype',(metadata->>'size')::bigint into mime,total from storage.objects where bucket_id='pulse-social' and name=m->>'path';
 if mime is null or mime is distinct from m->>'mime' then raise exception 'Upload media before publishing'; end if;
 if (m->>'kind'='image' and mime not in ('image/jpeg','image/png','image/webp')) or (m->>'kind'='video' and mime not in ('video/mp4','video/webm','video/quicktime')) then raise exception 'Unsupported media type'; end if;
 if not pulse_private.social_size_allowed(total) then raise exception 'Your file is over 500MB. Please upgrade to Premium to continue.'; end if;
 if m ? 'cover_path' and (split_part(m->>'cover_path','/',1)<>auth.uid()::text or split_part(m->>'cover_path','/',2)<>p_id::text or not exists(select 1 from storage.objects where bucket_id='pulse-social' and name=m->>'cover_path' and metadata->>'mimetype'='image/jpeg' and (metadata->>'size')::bigint between 1 and 10485760)) then raise exception 'Invalid video cover'; end if;
 end loop;
 insert into public.pulse_social_content(id,author_id,kind,body,media,audience,state) values(p_id,auth.uid(),p_kind,trim(p_body),p_media,p_audience,case when p_draft then 'draft' else 'published' end)
 on conflict(id) do update set body=excluded.body,media=excluded.media,audience=excluded.audience,kind=excluded.kind,state=excluded.state,
 created_at=case when excluded.state='published' then now() else pulse_social_content.created_at end;
 return p_id;
end
$$;
create or replace function pulse_private.social_read(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.pulse_social_content c where c.id=p_id and c.state<>'deleted' and
 (c.author_id=auth.uid() or (c.state='published' and not c.hidden and not pulse_private.social_blocked(c.author_id) and
 (c.audience<>'private' and ((c.audience='public' and not coalesce((select is_private from public.pulse_social_accounts where user_id=c.author_id),false)) or pulse_private.social_follows(c.author_id))))))
$$;

-- Gated cosmetic profile styles; expiration is checked every read and write.
alter table public.pulse_social_accounts add column if not exists profile_theme text not null default 'classic' check(profile_theme in ('classic','aurora','sunset','midnight'));
create or replace function pulse_private.social_profile_style(p_user uuid) returns text language sql stable security definer set search_path='' as $$
 select case when not pulse_private.social_blocked(p_user) and exists(select 1 from public.pulse_premium where user_id=p_user and expires_at>now()) then coalesce((select profile_theme from public.pulse_social_accounts where user_id=p_user),'classic') else 'classic' end
$$;
create or replace function public.pulse_social_profile_style(p_user uuid) returns text language sql stable security invoker set search_path='' as $$ select pulse_private.social_profile_style(p_user) $$;
create or replace function pulse_private.social_set_profile_style(p_theme text) returns void language plpgsql security definer set search_path='' as $$
 begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_theme is null or p_theme not in ('classic','aurora','sunset','midnight') then raise exception 'Unknown profile theme'; end if;
 if p_theme<>'classic' and not exists(select 1 from public.pulse_premium where user_id=auth.uid() and expires_at>now()) then raise exception 'This profile theme requires Pulse Premium'; end if;
 insert into public.pulse_social_accounts(user_id,profile_theme) values(auth.uid(),p_theme) on conflict(user_id) do update set profile_theme=excluded.profile_theme;
 end
$$;
create or replace function public.pulse_social_set_profile_style(p_theme text) returns void language sql security invoker set search_path='' as $$ select pulse_private.social_set_profile_style(p_theme) $$;
revoke all on function pulse_private.social_profile_style(uuid),public.pulse_social_profile_style(uuid),pulse_private.social_set_profile_style(text),public.pulse_social_set_profile_style(text) from public,anon;
grant execute on function pulse_private.social_profile_style(uuid),public.pulse_social_profile_style(uuid),pulse_private.social_set_profile_style(text),public.pulse_social_set_profile_style(text) to authenticated;
commit;
