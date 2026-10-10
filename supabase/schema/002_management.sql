create table public.pulse_announcements(id uuid primary key default gen_random_uuid(), body text not null check(length(body) between 1 and 2000),created_at timestamptz not null default now());
create table public.pulse_feature_flags(key text primary key,value boolean not null default false);
create table public.pulse_plans(id text primary key,currency text not null default 'USD',amount_minor int not null check(amount_minor>0),interval_months int not null check(interval_months>0));
insert into public.pulse_plans values ('premium','USD',300,1);
alter table public.pulse_announcements enable row level security;
alter table public.pulse_feature_flags enable row level security;
alter table public.pulse_plans enable row level security;
create policy announcement_read on public.pulse_announcements for select to authenticated using(true);
create policy flags_read on public.pulse_feature_flags for select to authenticated using(true);
create policy plans_read on public.pulse_plans for select to authenticated using(true);
grant select on public.pulse_announcements,public.pulse_feature_flags,public.pulse_plans to authenticated;

create function pulse_private.manage_group(p_chat uuid,p_user uuid,p_action text) returns void language plpgsql security definer set search_path='' as $$
 declare own uuid;
 begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select owner_id into own from public.pulse_chats where id=p_chat and kind='group' for update;
 if own is null or not exists(select 1 from public.pulse_members where chat_id=p_chat and user_id=auth.uid() and role in ('owner','admin')) then raise exception 'Group administrator required'; end if;
 if p_user=own then raise exception 'Owner cannot be removed or demoted'; end if;
 if p_action='add' then
 if (select count(*) from public.pulse_members where chat_id=p_chat)>=101 then raise exception 'Group full'; end if;
 insert into public.pulse_members(chat_id,user_id) values(p_chat,p_user) on conflict do nothing;
 elsif p_action='remove' then
 if auth.uid()<>own and exists(select 1 from public.pulse_members where chat_id=p_chat and user_id=p_user and role='admin') then raise exception 'Owner required'; end if;
 delete from public.pulse_members where chat_id=p_chat and user_id=p_user;
 elsif p_action in ('admin','member') then
 if auth.uid()<>own then raise exception 'Owner required'; end if;
 update public.pulse_members set role=p_action where chat_id=p_chat and user_id=p_user;
 else raise exception 'Invalid action'; end if;
 end
$$;
create function public.pulse_manage_group(p_chat uuid,p_user uuid,p_action text) returns void language sql security invoker set search_path='' as $$ select pulse_private.manage_group(p_chat,p_user,p_action) $$;
revoke all on function pulse_private.manage_group(uuid,uuid,text),public.pulse_manage_group(uuid,uuid,text) from public,anon;
grant execute on function pulse_private.manage_group(uuid,uuid,text),public.pulse_manage_group(uuid,uuid,text) to authenticated;

create function pulse_private.admin_overview() returns jsonb language plpgsql security definer set search_path='' as $$
 begin
 if not pulse_private.is_admin() then raise exception 'Administrator required'; end if;
 return jsonb_build_object('users',(select count(*) from public.pulse_profiles),'messages',(select count(*) from public.pulse_messages),'groups',(select count(*) from public.pulse_chats where kind='group'),'channels',(select count(*) from public.pulse_channels),'premium',(select count(*) from public.pulse_premium where expires_at>now()),'reports',(select coalesce(jsonb_agg(r),'[]'::jsonb) from (select * from public.pulse_reports order by created_at desc limit 100) r),'promos',(select coalesce(jsonb_agg(r),'[]'::jsonb) from pulse_private.promo_codes r));
 end
$$;
create function public.pulse_admin_overview() returns jsonb language sql security invoker set search_path='' as $$ select pulse_private.admin_overview() $$;
revoke all on function pulse_private.admin_overview(),public.pulse_admin_overview() from public,anon;
grant execute on function pulse_private.admin_overview(),public.pulse_admin_overview() to authenticated;
create function pulse_private.admin_action(p_action text,p_data jsonb) returns void language plpgsql security definer set search_path='' as $$
 begin
 if not pulse_private.is_admin() then raise exception 'Administrator required'; end if;
 if p_action='report' then update public.pulse_reports set state=p_data->>'state' where id=(p_data->>'id')::uuid;
 elsif p_action='verify_channel' then update public.pulse_channels set verified=(p_data->>'verified')::boolean where id=(p_data->>'id')::uuid;
 elsif p_action='promo' then
 if upper(p_data->>'code') !~ '^[A-Z0-9_]{6,40}$' then raise exception 'Invalid promo'; end if;
 insert into pulse_private.promo_codes(code,days,max_uses,expires_at) values(upper(p_data->>'code'),(p_data->>'days')::int,(p_data->>'max_uses')::int,(p_data->>'expires_at')::timestamptz);
 elsif p_action='announcement' then insert into public.pulse_announcements(body) values(p_data->>'body');
 elsif p_action='flag' then insert into public.pulse_feature_flags(key,value) values(p_data->>'key',(p_data->>'value')::boolean) on conflict(key) do update set value=excluded.value;
 else raise exception 'Invalid admin action'; end if;
 end
$$;
create function public.pulse_admin_action(p_action text,p_data jsonb) returns void language sql security invoker set search_path='' as $$ select pulse_private.admin_action(p_action,p_data) $$;
revoke all on function pulse_private.admin_action(text,jsonb),public.pulse_admin_action(text,jsonb) from public,anon;
grant execute on function pulse_private.admin_action(text,jsonb),public.pulse_admin_action(text,jsonb) to authenticated;
create function public.pulse_is_admin() returns boolean language sql security invoker set search_path='' as $$ select pulse_private.is_admin() $$;
revoke all on function public.pulse_is_admin() from public,anon;
grant execute on function public.pulse_is_admin() to authenticated;
