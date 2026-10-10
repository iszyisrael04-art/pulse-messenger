begin;
create table public.pulse_calls (
 id uuid primary key default gen_random_uuid(), chat_id uuid not null references public.pulse_chats on delete cascade,
 caller_id uuid not null references public.pulse_profiles,
 kind text not null check(kind in ('voice','video')),
 status text not null default 'ringing' check(status in ('ringing','active','ended')),
 created_at timestamptz not null default now(), started_at timestamptz,
 ring_deadline timestamptz not null default now()+interval '45 seconds',
 expires_at timestamptz not null default now()+interval '90 seconds',
 ended_at timestamptz, ended_reason text
);
create table public.pulse_call_members (
 call_id uuid references public.pulse_calls on delete cascade,
 user_id uuid references public.pulse_profiles,
 state text not null check(state in ('ringing','joined','declined','left','missed')),
 last_touch timestamptz not null default now(), primary key(call_id,user_id)
);
create index pulse_call_members_user on public.pulse_call_members(user_id,call_id);
create index pulse_calls_chat_created on public.pulse_calls(chat_id,created_at desc);
create function pulse_private.is_call_member(p_call uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.pulse_call_members where call_id=p_call and user_id=auth.uid())
$$;
alter table public.pulse_calls enable row level security;
alter table public.pulse_call_members enable row level security;
create policy calls_read on public.pulse_calls for select to authenticated using(pulse_private.is_call_member(id));
create policy call_members_read on public.pulse_call_members for select to authenticated using(pulse_private.is_call_member(call_id));
grant select on public.pulse_calls,public.pulse_call_members to authenticated;
revoke all on function pulse_private.is_call_member(uuid) from public,anon;
grant execute on function pulse_private.is_call_member(uuid) to authenticated;

-- Internal lease reconciliation. No direct client execution.
create function pulse_private.cleanup_call(p_call uuid) returns void language plpgsql security definer set search_path='' as $$
 declare c public.pulse_calls; joined int; ringing int;
 begin
 select * into c from public.pulse_calls where id=p_call for update;
 if not found or c.status='ended' then return; end if;
 update public.pulse_call_members set state='missed' where call_id=p_call and state='ringing' and c.ring_deadline<=now();
 update public.pulse_call_members set state='left' where call_id=p_call and state='joined' and last_touch<now()-interval '90 seconds';
 -- Removed group members cannot remain authorized on the signaling side.
 update public.pulse_call_members cm set state='left' where cm.call_id=p_call and cm.state in ('ringing','joined')
 and not exists(select 1 from public.pulse_members m where m.chat_id=c.chat_id and m.user_id=cm.user_id);
 select count(*) filter(where state='joined'),count(*) filter(where state='ringing') into joined,ringing from public.pulse_call_members where call_id=p_call;
 if c.expires_at<=now() or joined=0 or (joined<2 and ringing=0) then
 update public.pulse_calls set status='ended',ended_at=now(),ended_reason=case when started_at is null then 'missed' else 'finished' end where id=p_call;
 update public.pulse_call_members set state=case when state='ringing' then 'missed' else 'left' end where call_id=p_call and state in ('ringing','joined');
 end if;
 end
$$;
revoke all on function pulse_private.cleanup_call(uuid) from public,anon,authenticated;

create function pulse_private.call_start(p_chat uuid,p_kind text) returns uuid language plpgsql security definer set search_path='' as $$
 declare ids uuid[]; u uuid; existing uuid; callid uuid;
 begin
 if not pulse_private.is_member(p_chat) then raise exception 'Chat unavailable'; end if;
 if p_kind is null or p_kind not in ('voice','video') then raise exception 'Invalid call type'; end if;
 select array_agg(user_id order by user_id) into ids from public.pulse_members where chat_id=p_chat;
 if cardinality(ids)<2 or cardinality(ids)>8 then raise exception 'This beta supports calls with 2 to 8 chat members'; end if;
 -- Consistent locks prevent simultaneous calls from reserving the same person.
 foreach u in array ids loop perform pg_advisory_xact_lock(hashtextextended(u::text,7)); end loop;
 for existing in select distinct c.id from public.pulse_calls c join public.pulse_call_members m on m.call_id=c.id
 where m.user_id=any(ids) and c.status<>'ended' loop perform pulse_private.cleanup_call(existing); end loop;
 if exists(select 1 from public.pulse_calls c join public.pulse_call_members m on m.call_id=c.id where m.user_id=any(ids) and m.state in ('ringing','joined') and c.status<>'ended') then raise exception 'Someone is already in a call'; end if;
 if exists(select 1 from public.pulse_blocks where (user_id=auth.uid() and blocked_id=any(ids)) or (blocked_id=auth.uid() and user_id=any(ids))) then raise exception 'Unavailable contact'; end if;
 if (select count(*) from public.pulse_calls where caller_id=auth.uid() and created_at>now()-interval '1 hour')>=20 then raise exception 'Call limit reached. Try again later'; end if;
 insert into public.pulse_calls(chat_id,caller_id,kind) values(p_chat,auth.uid(),p_kind) returning id into callid;
 insert into public.pulse_call_members(call_id,user_id,state) select callid,member_id,case when member_id=auth.uid() then 'joined' else 'ringing' end from unnest(ids) as invited(member_id);
 return callid;
 end
$$;
create function pulse_private.call_accept(p_call uuid) returns void language plpgsql security definer set search_path='' as $$
 declare c public.pulse_calls;
 begin
 if not pulse_private.is_call_member(p_call) then raise exception 'Call unavailable'; end if;
 perform pulse_private.cleanup_call(p_call);
 select * into c from public.pulse_calls where id=p_call for update;
 if c.status='ended' or not pulse_private.is_member(c.chat_id) then raise exception 'Call ended'; end if;
 if not exists(select 1 from public.pulse_call_members where call_id=p_call and user_id=auth.uid() and state in ('ringing','joined')) then raise exception 'Invitation unavailable'; end if;
 if exists(select 1 from public.pulse_blocks b join public.pulse_call_members m on m.call_id=p_call and m.state='joined'
 where (b.user_id=auth.uid() and b.blocked_id=m.user_id) or (b.blocked_id=auth.uid() and b.user_id=m.user_id)) then raise exception 'Unavailable contact'; end if;
 update public.pulse_call_members set state='joined',last_touch=now() where call_id=p_call and user_id=auth.uid();
 update public.pulse_calls set status='active',started_at=coalesce(started_at,now()),expires_at=now()+interval '90 seconds' where id=p_call;
 end
$$;
create function pulse_private.call_leave(p_call uuid,p_decline boolean) returns void language plpgsql security definer set search_path='' as $$
 declare c public.pulse_calls;
 begin
 if not pulse_private.is_call_member(p_call) then raise exception 'Call unavailable'; end if;
 select * into c from public.pulse_calls where id=p_call for update;
 update public.pulse_call_members set state=case when p_decline then 'declined' else 'left' end where call_id=p_call and user_id=auth.uid();
 if c.caller_id=auth.uid() and c.status='ringing' then
 update public.pulse_calls set status='ended',ended_at=now(),ended_reason='cancelled' where id=p_call;
 update public.pulse_call_members set state='missed' where call_id=p_call and state='ringing';
 else perform pulse_private.cleanup_call(p_call); end if;
 end
$$;
create function pulse_private.call_state(p_call uuid,p_touch boolean) returns jsonb language plpgsql security definer set search_path='' as $$
 declare result jsonb; cid uuid;
 begin
 if not pulse_private.is_call_member(p_call) then raise exception 'Call unavailable'; end if;
 select chat_id into cid from public.pulse_calls where id=p_call;
 perform pulse_private.cleanup_call(p_call);
 if p_touch and pulse_private.is_member(cid) then
 if exists(select 1 from public.pulse_blocks b join public.pulse_call_members m on m.call_id=p_call and m.state='joined'
 where (b.user_id=auth.uid() and b.blocked_id=m.user_id) or (b.blocked_id=auth.uid() and b.user_id=m.user_id)) then
 perform pulse_private.call_leave(p_call,false);
 else
 update public.pulse_call_members set last_touch=now() where call_id=p_call and user_id=auth.uid() and state='joined';
 if found then update public.pulse_calls set expires_at=now()+interval '90 seconds' where id=p_call and status<>'ended'; end if;
 end if;
 end if;
 select to_jsonb(c)||jsonb_build_object('members',(select jsonb_agg(to_jsonb(m)) from public.pulse_call_members m where m.call_id=p_call)) into result from public.pulse_calls c where c.id=p_call;
 return result;
 end
$$;
create function public.pulse_call_start(p_chat uuid,p_kind text) returns uuid language sql security invoker set search_path='' as $$ select pulse_private.call_start(p_chat,p_kind) $$;
create function public.pulse_call_accept(p_call uuid) returns void language sql security invoker set search_path='' as $$ select pulse_private.call_accept(p_call) $$;
create function public.pulse_call_leave(p_call uuid,p_decline boolean) returns void language sql security invoker set search_path='' as $$ select pulse_private.call_leave(p_call,p_decline) $$;
create function public.pulse_call_state(p_call uuid,p_touch boolean) returns jsonb language sql security invoker set search_path='' as $$ select pulse_private.call_state(p_call,p_touch) $$;
revoke all on function pulse_private.call_start(uuid,text),pulse_private.call_accept(uuid),pulse_private.call_leave(uuid,boolean),pulse_private.call_state(uuid,boolean),
 public.pulse_call_start(uuid,text),public.pulse_call_accept(uuid),public.pulse_call_leave(uuid,boolean),public.pulse_call_state(uuid,boolean) from public,anon;
grant execute on function pulse_private.call_start(uuid,text),pulse_private.call_accept(uuid),pulse_private.call_leave(uuid,boolean),pulse_private.call_state(uuid,boolean),
 public.pulse_call_start(uuid,text),public.pulse_call_accept(uuid),public.pulse_call_leave(uuid,boolean),public.pulse_call_state(uuid,boolean) to authenticated;
alter publication supabase_realtime add table public.pulse_calls,public.pulse_call_members;
commit;
