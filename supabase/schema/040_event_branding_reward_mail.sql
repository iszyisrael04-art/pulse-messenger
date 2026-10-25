begin;
create table pulse_private.reward_announcements(id uuid primary key default gen_random_uuid(),code_id uuid unique not null references pulse_private.reward_codes,code text not null,created_at timestamptz not null default clock_timestamp());
create table pulse_private.reward_mail_reads(user_id uuid references auth.users on delete cascade,announcement uuid references pulse_private.reward_announcements on delete cascade,primary key(user_id,announcement));
create index reward_mail_read_announcement on pulse_private.reward_mail_reads(announcement);
alter table pulse_private.reward_announcements enable row level security;
alter table pulse_private.reward_mail_reads enable row level security;
revoke all on pulse_private.reward_announcements,pulse_private.reward_mail_reads from public,anon,authenticated;
create policy deny_clients on pulse_private.reward_announcements for all to authenticated using(false)with check(false);
create policy deny_clients on pulse_private.reward_mail_reads for all to authenticated using(false)with check(false);
create or replace function pulse_private.staff_rewards(p_action text,p_data jsonb)returns jsonb language plpgsql security definer set search_path=''as $$
declare owner boolean;target uuid;code text;cid uuid;days integer;kind text;amount integer;uses integer;reward_days integer;r pulse_private.reward_codes;
begin
 perform pulse_private.require_active();
 if not pulse_private.is_admin()then raise exception 'Administrator required';end if;
 owner=exists(select 1 from pulse_private.staff_owners where user_id=auth.uid());
 if p_action='overview'then return jsonb_build_object('owner',owner,'administrators',(select jsonb_agg(jsonb_build_object('id',p.id,'username',p.username,'owner',exists(select 1 from pulse_private.staff_owners where user_id=p.id)))from public.pulse_profiles p join pulse_private.admins a on a.user_id=p.id),'codes',coalesce((select jsonb_agg(to_jsonb(x))from(select id,kind,amount,max_uses,uses,expires_at,reward_days,disabled from pulse_private.reward_codes order by created_at desc limit 100)x),'[]'::jsonb));end if;
 if p_action in('grant_admin','remove_admin')then
  if not owner then raise exception 'Only the owner can choose administrators';end if;
  select id into target from public.pulse_profiles where username=lower(trim(leading '@'from p_data->>'username'));
  if target is null then raise exception 'Username not found';end if;
  if exists(select 1 from pulse_private.staff_owners where user_id=target)then raise exception 'Owner access cannot be changed here';end if;
  if p_action='grant_admin'then insert into pulse_private.admins values(target)on conflict do nothing;else delete from pulse_private.admins where user_id=target;end if;
 elsif p_action='create'then
  perform pulse_private.social_rate('reward_create',10,3600);
  days=(p_data->>'days')::integer;reward_days=(p_data->>'reward_days')::integer;kind=p_data->>'kind';amount=(p_data->>'amount')::integer;uses=(p_data->>'max_uses')::integer;
  if days is null or days not between 1 and 365 or reward_days is null or reward_days not between 1 and 365 or kind is null or kind not in('coins','views')or amount is null or amount not between 1 and 100000 or uses is null or uses not between 1 and 1000 then raise exception 'Invalid reward limits';end if;
  code=upper(encode(extensions.gen_random_bytes(12),'hex'));
  insert into pulse_private.reward_codes(code_hash,kind,amount,max_uses,expires_at,reward_days,created_by)values(encode(extensions.digest(code,'sha256'),'hex'),kind,amount,uses,clock_timestamp()+make_interval(days=>days),reward_days,auth.uid())returning id into cid;
  if coalesce((p_data->>'public')::boolean,false)then insert into pulse_private.reward_announcements(code_id,code)values(cid,code);end if;
 elsif p_action='disable'then
  update pulse_private.reward_codes set disabled=true where id=(p_data->>'id')::uuid;
 else raise exception 'Unknown action';end if;
 insert into pulse_private.control_audit(staff_id,action,detail)values(auth.uid(),'rewards_'||p_action,p_data- 'code');
 return jsonb_build_object('saved',true,'code',code,'id',cid);
end$$;
create function pulse_private.reward_mail(p_seen uuid[])returns jsonb language plpgsql security definer set search_path=''as $$
begin
 perform pulse_private.require_active();
 if cardinality(p_seen)>50 then raise exception 'Too many acknowledgements';end if;
 insert into pulse_private.reward_mail_reads select auth.uid(),id from pulse_private.reward_announcements where id=any(p_seen)on conflict do nothing;
 return jsonb_build_object('unread',(select count(*)from pulse_private.reward_announcements a join pulse_private.reward_codes c on c.id=a.code_id where not c.disabled and c.expires_at>now()and c.uses<c.max_uses and not exists(select 1 from pulse_private.reward_mail_reads r where r.user_id=auth.uid()and r.announcement=a.id)),
 'items',coalesce((select jsonb_agg(x)from(select a.id,a.code,c.kind,c.amount,c.expires_at,a.created_at from pulse_private.reward_announcements a join pulse_private.reward_codes c on c.id=a.code_id where not c.disabled and c.expires_at>now()and c.uses<c.max_uses order by a.created_at desc limit 50)x),'[]'::jsonb));
end$$;
create function public.pulse_reward_mail(p_seen uuid[]default '{}')returns jsonb language sql security invoker set search_path=''as $$select pulse_private.reward_mail(p_seen)$$;
revoke all on function pulse_private.reward_mail(uuid[]),public.pulse_reward_mail(uuid[])from public,anon,authenticated;
grant execute on function pulse_private.reward_mail(uuid[]),public.pulse_reward_mail(uuid[])to authenticated;
create table public.pulse_event_branding(singleton boolean primary key default true check(singleton),path text,title text not null default '',until_at timestamptz);
insert into public.pulse_event_branding(singleton)values(true);
alter table public.pulse_event_branding enable row level security;
revoke all on public.pulse_event_branding from public,anon,authenticated;
grant select on public.pulse_event_branding to anon,authenticated;
create policy public_branding on public.pulse_event_branding for select to anon,authenticated using(true);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)values('pulse-branding','pulse-branding',true,2097152,array['image/png','image/jpeg','image/webp']);
create policy staff_brand_upload on storage.objects for insert to authenticated with check(bucket_id='pulse-branding'and split_part(name,'/',1)=auth.uid()::text and pulse_private.account_active()and pulse_private.is_admin());
create function pulse_private.event_branding(p_path text,p_title text,p_days integer)returns void language plpgsql security definer set search_path=''as $$
begin
 perform pulse_private.require_active();if not pulse_private.is_admin()then raise exception 'Administrator required';end if;
 if p_days is null or p_days not between 1 and 90 or length(coalesce(p_title,''))>80 then raise exception 'Invalid event duration or title';end if;
 if p_path is not null and not exists(select 1 from storage.objects where bucket_id='pulse-branding'and name=p_path and split_part(name,'/',1)=auth.uid()::text and metadata->>'mimetype'in('image/png','image/jpeg','image/webp')and(metadata->>'size')::bigint between 1 and 2097152)then raise exception 'Upload your event image first';end if;
 update public.pulse_event_branding set path=p_path,title=coalesce(p_title,''),until_at=clock_timestamp()+make_interval(days=>p_days)where singleton;
 insert into pulse_private.control_audit(staff_id,action,detail)values(auth.uid(),'event_branding',jsonb_build_object('path',p_path,'days',p_days));
end$$;
create function public.pulse_event_branding_save(p_path text,p_title text,p_days integer)returns void language sql security invoker set search_path=''as $$select pulse_private.event_branding(p_path,p_title,p_days)$$;
revoke all on function pulse_private.event_branding(text,text,integer),public.pulse_event_branding_save(text,text,integer)from public,anon,authenticated;
grant execute on function pulse_private.event_branding(text,text,integer),public.pulse_event_branding_save(text,text,integer)to authenticated;
commit;
