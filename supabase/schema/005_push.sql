-- FCM device registration and durable queue. Tokens are never readable by clients.
create table pulse_private.push_devices (
 device_id uuid primary key,user_id uuid not null references public.pulse_profiles on delete cascade,
 token text unique not null check(length(token) between 20 and 4096),updated_at timestamptz not null default now()
);
create index pulse_push_device_user on pulse_private.push_devices(user_id);
alter table pulse_private.push_devices enable row level security;
create table pulse_private.push_outbox (
 id bigint generated always as identity primary key,message_id uuid not null references public.pulse_messages on delete cascade,
 recipient_id uuid not null references public.pulse_profiles on delete cascade,
 state text not null default 'pending' check(state in ('pending','leased','done','failed')),
 attempts integer not null default 0,available_at timestamptz not null default now(),created_at timestamptz not null default now(),
 unique(message_id,recipient_id)
);
create index pulse_push_available on pulse_private.push_outbox(state,available_at);
alter table pulse_private.push_outbox enable row level security;
revoke all on pulse_private.push_devices,pulse_private.push_outbox from public,anon,authenticated;
grant all on pulse_private.push_devices,pulse_private.push_outbox to service_role;
grant usage,select on sequence pulse_private.push_outbox_id_seq to service_role;
create function pulse_private.push_register(p_device uuid,p_token text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_token is null then delete from pulse_private.push_devices where device_id=p_device and user_id=auth.uid(); return; end if;
 -- Device IDs are local identifiers, not an authorization boundary. Never overwrite another user's device.
 if exists(select 1 from pulse_private.push_devices where device_id=p_device and user_id<>auth.uid()) then raise exception 'Device belongs to another account'; end if;
 if not exists(select 1 from pulse_private.push_devices where device_id=p_device) and (select count(*) from pulse_private.push_devices where user_id=auth.uid())>=10 then raise exception 'Device limit reached'; end if;
 insert into pulse_private.push_devices(device_id,user_id,token) values(p_device,auth.uid(),p_token) on conflict(device_id) do update set token=excluded.token,updated_at=now();
end $$;
revoke all on function pulse_private.push_register(uuid,text) from public,anon,authenticated;
grant execute on function pulse_private.push_register(uuid,text) to authenticated;
create function public.pulse_push_register(p_device uuid,p_token text) returns void language sql security invoker set search_path='' as $$ select pulse_private.push_register(p_device,p_token) $$;
revoke all on function public.pulse_push_register(uuid,text) from public,anon,authenticated;
grant execute on function public.pulse_push_register(uuid,text) to authenticated;
create function pulse_private.enqueue_push() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into pulse_private.push_outbox(message_id,recipient_id)
 select new.id,m.user_id from public.pulse_members m where m.chat_id=new.chat_id and m.user_id<>new.sender_id
 and not exists(select 1 from public.pulse_blocks b where (b.user_id=m.user_id and b.blocked_id=new.sender_id) or (b.user_id=new.sender_id and b.blocked_id=m.user_id))
 on conflict do nothing;
 return new;
end $$;
revoke all on function pulse_private.enqueue_push() from public,anon,authenticated;
create trigger pulse_message_push after insert on public.pulse_messages for each row execute function pulse_private.enqueue_push();
-- Claims are server-only. Lease expiry allows retry after worker failure.
create function pulse_private.push_claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 update pulse_private.push_outbox set state='failed' where state='leased' and attempts>=5 and available_at<=now();
 with candidates as (
 select id from pulse_private.push_outbox where state in ('pending','leased') and available_at<=now() and attempts<5 order by id for update skip locked limit 20
 ), claimed as (
 update pulse_private.push_outbox o set state='leased',attempts=attempts+1,available_at=now()+interval '2 minutes' from candidates c where o.id=c.id returning o.*
 ) select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('tokens',(select coalesce(jsonb_agg(d.token),'[]'::jsonb) from pulse_private.push_devices d where d.user_id=c.recipient_id))), '[]'::jsonb) into result from claimed c;
 return result;
end $$;
create function pulse_private.push_finish(p_id bigint,p_success boolean) returns void language sql security definer set search_path='' as $$
 update pulse_private.push_outbox set state=case when p_success then 'done' when attempts>=5 then 'failed' else 'pending' end,available_at=now()+interval '1 minute' where id=p_id;
$$;
-- Read current eligibility at delivery time. Keep all private content out of push payloads.
create function pulse_private.push_allowed(p_message uuid,p_recipient uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.pulse_messages msg join public.pulse_members m on m.chat_id=msg.chat_id where msg.id=p_message and msg.deleted_at is null and m.user_id=p_recipient and not exists(select 1 from public.pulse_blocks b where (b.user_id=m.user_id and b.blocked_id=msg.sender_id) or (b.user_id=msg.sender_id and b.blocked_id=m.user_id)));
$$;
create function pulse_private.push_invalid(p_token text) returns void language sql security definer set search_path='' as $$ delete from pulse_private.push_devices where token=p_token $$;

revoke all on function pulse_private.push_claim() from public,anon,authenticated;
grant execute on function pulse_private.push_claim() to service_role;
create function public.pulse_push_claim() returns jsonb language sql security invoker set search_path='' as $$ select pulse_private.push_claim() $$;
revoke all on function public.pulse_push_claim() from public,anon,authenticated;
grant execute on function public.pulse_push_claim() to service_role;

revoke all on function pulse_private.push_finish(bigint,boolean) from public,anon,authenticated;
grant execute on function pulse_private.push_finish(bigint,boolean) to service_role;
create function public.pulse_push_finish(p_id bigint,p_success boolean) returns void language sql security invoker set search_path='' as $$ select pulse_private.push_finish(p_id,p_success) $$;
revoke all on function public.pulse_push_finish(bigint,boolean) from public,anon,authenticated;
grant execute on function public.pulse_push_finish(bigint,boolean) to service_role;

revoke all on function pulse_private.push_allowed(uuid,uuid) from public,anon,authenticated;
grant execute on function pulse_private.push_allowed(uuid,uuid) to service_role;
create function public.pulse_push_allowed(p_message uuid,p_recipient uuid) returns boolean language sql security invoker set search_path='' as $$ select pulse_private.push_allowed(p_message,p_recipient) $$;
revoke all on function public.pulse_push_allowed(uuid,uuid) from public,anon,authenticated;
grant execute on function public.pulse_push_allowed(uuid,uuid) to service_role;

revoke all on function pulse_private.push_invalid(text) from public,anon,authenticated;
grant execute on function pulse_private.push_invalid(text) to service_role;
create function public.pulse_push_invalid(p_token text) returns void language sql security invoker set search_path='' as $$ select pulse_private.push_invalid(p_token) $$;
revoke all on function public.pulse_push_invalid(text) from public,anon,authenticated;
grant execute on function public.pulse_push_invalid(text) to service_role;
grant usage on schema pulse_private to service_role;

create function pulse_private.push_disable(p_device uuid,p_all boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 delete from pulse_private.push_devices where user_id=auth.uid() and (p_all or device_id=p_device);
end $$;
revoke all on function pulse_private.push_disable(uuid,boolean) from public,anon,authenticated;
grant execute on function pulse_private.push_disable(uuid,boolean) to authenticated;
create function public.pulse_push_disable(p_device uuid,p_all boolean) returns void language sql security invoker set search_path='' as $$ select pulse_private.push_disable(p_device,p_all) $$;
revoke all on function public.pulse_push_disable(uuid,boolean) from public,anon,authenticated;
grant execute on function public.pulse_push_disable(uuid,boolean) to authenticated;
