-- Additive private chat tools. Do not reinstall earlier scripts on existing data.
begin;
create table pulse_private.chat_notes (
 user_id uuid references public.pulse_profiles on delete cascade,
 chat_id uuid references public.pulse_chats on delete cascade,
 body text not null check(length(body)<=4000),updated_at timestamptz not null default now(),
 primary key(user_id,chat_id)
);
create index chat_notes_chat on pulse_private.chat_notes(chat_id);
create table pulse_private.quick_replies (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.pulse_profiles on delete cascade,
 label text not null check(length(label) between 1 and 40),body text not null check(length(body) between 1 and 2000),
 updated_at timestamptz not null default now(),unique(user_id,label)
);
create table pulse_private.chat_styles (
 user_id uuid references public.pulse_profiles on delete cascade,
 chat_id uuid references public.pulse_chats on delete cascade,
 style text not null check(style in ('classic','aurora','rose','ocean')),
 primary key(user_id,chat_id)
);
create index chat_styles_chat on pulse_private.chat_styles(chat_id);
alter table pulse_private.chat_notes enable row level security;
alter table pulse_private.quick_replies enable row level security;
alter table pulse_private.chat_styles enable row level security;
revoke all on pulse_private.chat_notes,pulse_private.quick_replies,pulse_private.chat_styles from public,anon,authenticated;
create or replace function pulse_private.user_tools(p_action text,p_chat uuid default null,p_id uuid default null,p_label text default null,p_text text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare who uuid:=auth.uid(); paid boolean; saved uuid; style_name text;
begin
 if who is null then raise exception 'Sign in required'; end if;
 if p_action in ('note_save','quick_save','quick_delete','style_save') then perform pulse_private.social_rate('chat_tools',60,60); end if;
 paid=exists(select 1 from public.pulse_premium where user_id=who and expires_at>now());
 if p_action in ('note_get','note_save','style_get','style_save') and not pulse_private.is_member(p_chat) then raise exception 'Chat unavailable'; end if;
 if p_action='note_get' then
  return jsonb_build_object('body',coalesce((select body from pulse_private.chat_notes where user_id=who and chat_id=p_chat),''));
 elsif p_action='note_save' then
  if p_text is null or length(p_text)>4000 then raise exception 'Note must be under 4000 characters'; end if;
  insert into pulse_private.chat_notes(user_id,chat_id,body) values(who,p_chat,p_text) on conflict(user_id,chat_id) do update set body=excluded.body,updated_at=now();
  return jsonb_build_object('saved',true);
 elsif p_action='quick_list' then
  return jsonb_build_object('premium',paid,'items',coalesce((select jsonb_agg(jsonb_build_object('id',id,'label',label,'body',body) order by label) from pulse_private.quick_replies where user_id=who),'[]'::jsonb));
 elsif p_action='quick_save' then
  if not paid then raise exception 'Active Premium required'; end if;
  if p_label is null or length(trim(p_label)) not between 1 and 40 or p_text is null or length(trim(p_text)) not between 1 and 2000 then raise exception 'Enter a title and reply'; end if;
  perform pg_advisory_xact_lock(hashtextextended(who::text,44));
  if not exists(select 1 from pulse_private.quick_replies where id=p_id and user_id=who) and (select count(*) from pulse_private.quick_replies where user_id=who)>=20 then raise exception 'You can save up to 20 quick replies'; end if;
  insert into pulse_private.quick_replies(id,user_id,label,body) values(coalesce(p_id,gen_random_uuid()),who,trim(p_label),trim(p_text))
   on conflict(id) do update set label=excluded.label,body=excluded.body,updated_at=now() where pulse_private.quick_replies.user_id=who returning id into saved;
  if saved is null then raise exception 'Reply unavailable'; end if;
  return jsonb_build_object('id',saved);
 elsif p_action='quick_delete' then
  delete from pulse_private.quick_replies where id=p_id and user_id=who;
  return jsonb_build_object('deleted',found);
 elsif p_action='quick_use' then
  if not paid then raise exception 'Active Premium required'; end if;
  select id into saved from pulse_private.quick_replies where id=p_id and user_id=who;
  if saved is null then raise exception 'Reply unavailable'; end if;
  return (select jsonb_build_object('body',body) from pulse_private.quick_replies where id=saved);
 elsif p_action='style_get' then
  select style into style_name from pulse_private.chat_styles where user_id=who and chat_id=p_chat;
  return jsonb_build_object('premium',paid,'style',case when paid then coalesce(style_name,'classic') else 'classic' end);
 elsif p_action='style_save' then
  if p_label is null or p_label not in ('classic','aurora','rose','ocean') then raise exception 'Unknown style'; end if;
  if p_label<>'classic' and not paid then raise exception 'Active Premium required'; end if;
  insert into pulse_private.chat_styles(user_id,chat_id,style) values(who,p_chat,p_label) on conflict(user_id,chat_id) do update set style=excluded.style;
  return jsonb_build_object('style',p_label);
 end if;
 raise exception 'Unknown chat tool';
end
$$;
create or replace function public.pulse_user_tools(p_action text,p_chat uuid default null,p_id uuid default null,p_label text default null,p_text text default null)
returns jsonb language sql security invoker set search_path='' as $$select pulse_private.user_tools(p_action,p_chat,p_id,p_label,p_text)$$;
revoke all on function pulse_private.user_tools(text,uuid,uuid,text,text),public.pulse_user_tools(text,uuid,uuid,text,text) from public,anon;
grant execute on function pulse_private.user_tools(text,uuid,uuid,text,text),public.pulse_user_tools(text,uuid,uuid,text,text) to authenticated;
notify pgrst,'reload schema';
commit;

-- Notification eligibility refinements.
begin;
create or replace function pulse_private.unread_counts() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_object_agg(chat_id,n),'{}'::jsonb) from (
 select m.chat_id,count(*) n from public.pulse_messages m join public.pulse_members own on own.chat_id=m.chat_id and own.user_id=auth.uid()
 where m.sender_id<>auth.uid() and m.deleted_at is null
 and not exists(select 1 from public.pulse_receipts r where r.message_id=m.id and r.user_id=auth.uid() and r.read_at is not null)
 and not exists(select 1 from public.pulse_message_preferences p where p.message_id=m.id and p.user_id=auth.uid() and p.hidden)
 and not exists(select 1 from public.pulse_blocks b where (b.user_id=auth.uid() and b.blocked_id=m.sender_id) or (b.blocked_id=auth.uid() and b.user_id=m.sender_id))
 group by m.chat_id) counts
$$;
create or replace function pulse_private.unread_preview(p_message uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('message',to_jsonb(m),'unread_count',(pulse_private.unread_counts()->>m.chat_id::text)::int)
 from public.pulse_messages m where m.id=p_message and auth.uid() is not null and m.sender_id<>auth.uid() and m.deleted_at is null
 and pulse_private.is_member(m.chat_id)
 and not exists(select 1 from public.pulse_receipts r where r.message_id=m.id and r.user_id=auth.uid() and r.read_at is not null)
 and not exists(select 1 from public.pulse_message_preferences p where p.message_id=m.id and p.user_id=auth.uid() and p.hidden)
 and not exists(select 1 from public.pulse_blocks b where (b.user_id=auth.uid() and b.blocked_id=m.sender_id) or (b.blocked_id=auth.uid() and b.user_id=m.sender_id))
$$;
create or replace function public.pulse_unread_preview(p_message uuid) returns jsonb language sql stable security invoker set search_path='' as $$select pulse_private.unread_preview(p_message)$$;
revoke all on function pulse_private.unread_preview(uuid),public.pulse_unread_preview(uuid) from public,anon;
grant execute on function pulse_private.unread_preview(uuid),public.pulse_unread_preview(uuid) to authenticated;
create or replace function pulse_private.push_allowed(p_message uuid,p_recipient uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.pulse_messages msg join public.pulse_members m on m.chat_id=msg.chat_id where msg.id=p_message and msg.deleted_at is null and m.user_id=p_recipient
 and not exists(select 1 from public.pulse_blocks b where (b.user_id=m.user_id and b.blocked_id=msg.sender_id) or (b.user_id=msg.sender_id and b.blocked_id=m.user_id))
 and not exists(select 1 from public.pulse_receipts r where r.message_id=msg.id and r.user_id=p_recipient and r.read_at is not null)
 and not exists(select 1 from public.pulse_message_preferences p where p.message_id=msg.id and p.user_id=p_recipient and p.hidden));
$$;
revoke all on function pulse_private.push_allowed(uuid,uuid) from public,anon,authenticated;
grant execute on function pulse_private.push_allowed(uuid,uuid) to service_role;
notify pgrst,'reload schema';
commit;
