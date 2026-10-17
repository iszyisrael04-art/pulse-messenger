begin;
create table pulse_private.account_limits(user_id uuid primary key references public.pulse_profiles on delete cascade,state text not null check(state in('active','banned','suspended')),until_at timestamptz,reason text not null default '',updated_at timestamptz not null default now(),check(state<>'suspended' or until_at is not null));
create table pulse_private.control_audit(id uuid primary key default gen_random_uuid(),staff_id uuid references public.pulse_profiles,subject_id uuid references public.pulse_profiles,action text not null,detail jsonb not null default '{}',created_at timestamptz not null default now());
create index control_audit_staff on pulse_private.control_audit(staff_id);
create index control_audit_subject on pulse_private.control_audit(subject_id,created_at desc);
create table pulse_private.system_mail(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.pulse_profiles on delete cascade,title text not null,body text not null,created_at timestamptz not null default now(),read_at timestamptz);
create index system_mail_user on pulse_private.system_mail(user_id,created_at desc,id desc);
create table pulse_private.email_jobs(id uuid primary key default gen_random_uuid(),user_id uuid references public.pulse_profiles on delete cascade,recipient text not null,subject text not null,body text not null,video_path text,state text not null default 'pending' check(state in('pending','sending','sent','failed')),created_at timestamptz not null default now());
create index email_jobs_user on pulse_private.email_jobs(user_id);
create index email_jobs_pending on pulse_private.email_jobs(state,created_at);
create function pulse_private.account_active() returns boolean language sql stable security definer set search_path='' as $$ select auth.uid() is not null and not exists(select 1 from pulse_private.account_limits where user_id=auth.uid() and (state='banned' or state='suspended' and until_at>now())) $$;
create function pulse_private.require_active() returns void language plpgsql stable security definer set search_path='' as $$ begin
 if coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb->>'role'='service_role' then return;end if;
 if not pulse_private.account_active() then raise exception 'Account access restricted';end if;end $$;
revoke all on function pulse_private.account_active(),pulse_private.require_active() from public,anon;
grant execute on function pulse_private.account_active(),pulse_private.require_active() to authenticated,service_role;
create function public.pulse_account_status() returns jsonb language sql stable security definer set search_path='' as $$
 select case when auth.uid() is null then null else jsonb_build_object('active',pulse_private.account_active(),'state',coalesce(l.state,'active'),'until',l.until_at,'reason',coalesce(l.reason,''),'name',p.display_name,'username',p.username) end from public.pulse_profiles p left join pulse_private.account_limits l on l.user_id=p.id where p.id=auth.uid()
$$;
-- Public status is the sole intentionally scoped definer projection: move implementation private.
alter function public.pulse_account_status() set schema pulse_private;
create function public.pulse_account_status() returns jsonb language sql stable security invoker set search_path='' as $$ select pulse_private.pulse_account_status() $$;
revoke all on function pulse_private.pulse_account_status(),public.pulse_account_status() from public,anon;
grant execute on function pulse_private.pulse_account_status(),public.pulse_account_status() to authenticated;

create table pulse_private.community_cards(chat_id uuid primary key references public.pulse_chats on delete cascade,handle text not null unique check(handle ~ '^[a-z][a-z0-9_]{2,39}$'),description text not null default '' check(length(description)<=500),avatar_path text,is_private boolean not null default false);
create table pulse_private.community_requests(chat_id uuid references public.pulse_chats on delete cascade,user_id uuid references public.pulse_profiles on delete cascade,state text not null default 'pending' check(state in('pending','approved','declined')),created_at timestamptz not null default clock_timestamp(),primary key(chat_id,user_id));
create index community_requests_user on pulse_private.community_requests(user_id,created_at desc);
-- Preserve all previous group memberships. Legacy groups default to private.
insert into pulse_private.community_cards(chat_id,handle,is_private) select id,'group_'||replace(id::text,'-',''),true from public.pulse_chats where kind='group';
-- Generated handles above need the same length rule as user handles.
alter table pulse_private.community_cards drop constraint community_cards_handle_check;
alter table pulse_private.community_cards add constraint community_cards_handle_check check(handle ~ '^[a-z][a-z0-9_]{2,39}$');
create function pulse_private.community_new_group() returns trigger language plpgsql security definer set search_path='' as $$ begin
 if new.kind='group' then insert into pulse_private.community_cards(chat_id,handle,is_private) values(new.id,'group_'||replace(new.id::text,'-',''),true) on conflict do nothing;end if;return new;end $$;
revoke all on function pulse_private.community_new_group() from public,anon,authenticated;
create trigger pulse_community_new_group after insert on public.pulse_chats for each row execute function pulse_private.community_new_group();
create function pulse_private.community_visible(p_chat uuid) returns boolean language sql stable security definer set search_path='' as $$ select pulse_private.account_active() and exists(select 1 from pulse_private.community_cards where chat_id=p_chat and (not is_private or pulse_private.is_member(p_chat))) $$;
create function pulse_private.community_admin(p_chat uuid) returns boolean language sql stable security definer set search_path='' as $$ select pulse_private.account_active() and exists(select 1 from public.pulse_members where chat_id=p_chat and user_id=auth.uid() and role in('owner','admin')) $$;
create function pulse_private.communities(p_action text,p_chat uuid,p_user uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; target uuid; own uuid; h text;
begin
 perform pulse_private.require_active();
 if p_action='list' then
 select coalesce(jsonb_agg(q),'[]') into result from (select c.chat_id,c.handle,c.description,c.avatar_path,c.is_private,g.name,
 (select count(*) from public.pulse_members m where m.chat_id=c.chat_id) members,
 coalesce((select role from public.pulse_members m where m.chat_id=c.chat_id and user_id=auth.uid()),'none') role,
 coalesce((select state from pulse_private.community_requests r where r.chat_id=c.chat_id and user_id=auth.uid()),'none') request_state
 from pulse_private.community_cards c join public.pulse_chats g on g.id=c.chat_id
 where pulse_private.community_visible(c.chat_id) and (p_chat is null or c.chat_id=p_chat)
 and (p_user is null or exists(select 1 from public.pulse_members where chat_id=c.chat_id and user_id=p_user))
 and (coalesce(p_data->>'query','')='' or c.handle ilike '%'||left(p_data->>'query',40)||'%' or g.name ilike '%'||left(p_data->>'query',40)||'%')
 order by g.created_at desc,c.chat_id limit 100) q;return result;
 end if;
 perform pulse_private.social_rate('community_actions',60,60);
 if p_action='create' then
 h=lower(trim(p_data->>'handle'));
 if h is null or h !~ '^[a-z][a-z0-9_]{2,29}$' or length(trim(coalesce(p_data->>'name',''))) not between 1 and 80 then raise exception 'Check community name and handle';end if;
 insert into public.pulse_chats(kind,name,owner_id) values('group',trim(p_data->>'name'),auth.uid()) returning id into target;
 insert into public.pulse_members(chat_id,user_id,role) values(target,auth.uid(),'owner');
 insert into pulse_private.community_cards(chat_id,handle,description,is_private) values(target,h,coalesce(p_data->>'description',''),coalesce((p_data->>'private')::boolean,false)) on conflict(chat_id) do update set handle=excluded.handle,description=excluded.description,is_private=excluded.is_private;return to_jsonb(target);
 elsif p_action='request' then
 if not pulse_private.community_visible(p_chat) then raise exception 'Community unavailable';end if;
 if pulse_private.is_member(p_chat) then return '"member"';end if;
 insert into pulse_private.community_requests(chat_id,user_id) values(p_chat,auth.uid()) on conflict(chat_id,user_id) do update set state='pending',created_at=clock_timestamp();
 elsif p_action='cancel' then delete from pulse_private.community_requests where chat_id=p_chat and user_id=auth.uid() and state='pending';
 elsif p_action in('approve','decline') then
 if not pulse_private.community_admin(p_chat) then raise exception 'Community administrator required';end if;
 perform 1 from public.pulse_chats where id=p_chat for update;
 if p_action='approve' then
 if (select count(*) from public.pulse_members where chat_id=p_chat)>=101 then raise exception 'Community full';end if;
 if not exists(select 1 from pulse_private.community_requests where chat_id=p_chat and user_id=p_user and state='pending') then raise exception 'Request unavailable';end if;
 insert into public.pulse_members(chat_id,user_id) values(p_chat,p_user) on conflict do nothing;
 end if;
 update pulse_private.community_requests set state=case when p_action='approve' then 'approved' else 'declined' end where chat_id=p_chat and user_id=p_user and state='pending';
 if found then insert into pulse_private.system_mail(user_id,title,body) values(p_user,'Community request',case when p_action='approve' then 'Your join request was approved.' else 'Your join request was declined.' end);end if;
 elsif p_action='update' then
 if not pulse_private.community_admin(p_chat) then raise exception 'Community administrator required';end if;
 if p_data->>'avatar' is not null and not exists(select 1 from storage.objects where bucket_id='pulse-avatars' and name=p_data->>'avatar' and split_part(name,'/',1)=auth.uid()::text and metadata->>'mimetype' in('image/jpeg','image/png','image/webp')) then raise exception 'Upload your own community image';end if;
 update pulse_private.community_cards set avatar_path=p_data->>'avatar',description=coalesce(p_data->>'description',description),is_private=coalesce((p_data->>'private')::boolean,is_private) where chat_id=p_chat;
 elsif p_action='leave' then
 if exists(select 1 from public.pulse_chats where id=p_chat and owner_id=auth.uid()) then raise exception 'Owner must keep this community or transfer ownership first';end if;
 delete from public.pulse_members where chat_id=p_chat and user_id=auth.uid();
 else raise exception 'Unknown community action';end if;
 return 'true';end $$;
create function public.pulse_communities(p_action text,p_chat uuid default null,p_user uuid default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$ select pulse_private.communities(p_action,p_chat,p_user,p_data) $$;
revoke all on function pulse_private.community_visible(uuid),pulse_private.community_admin(uuid) from public,anon,authenticated;
revoke all on function pulse_private.communities(text,uuid,uuid,jsonb),public.pulse_communities(text,uuid,uuid,jsonb) from public,anon;
grant execute on function pulse_private.communities(text,uuid,uuid,jsonb),public.pulse_communities(text,uuid,uuid,jsonb) to authenticated;

create function pulse_private.inbox(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$ declare result jsonb;begin
 perform pulse_private.require_active();
 if p_action='read' then update pulse_private.system_mail set read_at=now() where id=(p_data->>'id')::uuid and user_id=auth.uid();return 'true';end if;
 if p_action<>'list' then raise exception 'Unknown inbox action';end if;
 select jsonb_build_object('mail',(select coalesce(jsonb_agg(q),'[]') from (select id,title,body,created_at,read_at from pulse_private.system_mail where user_id=auth.uid() order by created_at desc limit 100) q),
 'community_requests',(select coalesce(jsonb_agg(q),'[]') from (select r.chat_id,r.user_id,r.created_at,p.username,p.display_name,p.avatar_path,g.name community from pulse_private.community_requests r join public.pulse_profiles p on p.id=r.user_id join public.pulse_chats g on g.id=r.chat_id where r.state='pending' and pulse_private.community_admin(r.chat_id) order by r.created_at desc limit 100)q),
 'chat_requests',(select coalesce(jsonb_agg(q),'[]') from (select r.chat_id,r.sender_id,p.username,p.display_name from public.pulse_chat_requests r join public.pulse_profiles p on p.id=r.sender_id where r.recipient_id=auth.uid() and r.state='pending' and r.sent_at is not null order by r.sent_at desc limit 100)q),
 'announcements',(select coalesce(jsonb_agg(q),'[]') from (select id,body,created_at from public.pulse_announcements order by created_at desc limit 20)q)) into result;return result;
end $$;
create function public.pulse_inbox(p_action text default 'list',p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$ select pulse_private.inbox(p_action,p_data) $$;
revoke all on function pulse_private.inbox(text,jsonb),public.pulse_inbox(text,jsonb) from public,anon;
grant execute on function pulse_private.inbox(text,jsonb),public.pulse_inbox(text,jsonb) to authenticated;

create function pulse_private.control(p_action text,p_user uuid,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; email text; title text; body text;until_time timestamptz;
begin
 perform pulse_private.require_active();
 if not pulse_private.is_admin() then raise exception 'Staff access required';end if;
 if p_action='search' then
 select coalesce(jsonb_agg(q),'[]') into result from (select p.id,p.username,p.display_name,p.avatar_path,coalesce(a.verified,false) verified,coalesce(l.state,'active') state,l.until_at,l.reason from public.pulse_profiles p left join public.pulse_social_accounts a on a.user_id=p.id left join pulse_private.account_limits l on l.user_id=p.id where p.username is not null and p.username ilike '%'||left(coalesce(p_data->>'query',''),40)||'%' and (p_data->>'after' is null or p.username>p_data->>'after') order by p.username limit 50)q;return result;
 end if;
 if p_user is null or not exists(select 1 from public.pulse_profiles where id=p_user) or p_action not in('verify','unverify','ban','suspend','release') then raise exception 'Unknown account action';end if;
 if p_action in('ban','suspend') and (p_user=auth.uid() or exists(select 1 from pulse_private.admins where user_id=p_user)) then raise exception 'Staff accounts cannot be restricted here';end if;
 if p_action in('ban','suspend') and length(trim(coalesce(p_data->>'reason',''))) not between 5 and 1000 then raise exception 'Enter a clear reason';end if;
 if p_action='suspend' then
 if coalesce((p_data->>'days')::int,0) not between 1 and 365 then raise exception 'Suspension must be 1–365 days';end if;
 until_time=now()+make_interval(days=>(p_data->>'days')::int);
 end if;
 if p_action in('verify','unverify') then
 insert into public.pulse_social_accounts(user_id,verified) values(p_user,p_action='verify') on conflict(user_id) do update set verified=excluded.verified;
 title=case when p_action='verify' then 'Your Pulse account is verified' else 'Your Pulse verification was removed' end;
 body='Your account verification status was updated by Pulse staff. Contact pulseservicemanagement@gmail.com if you have questions.';
 else
 insert into pulse_private.account_limits(user_id,state,until_at,reason) values(p_user,case when p_action='release' then 'active' when p_action='ban' then 'banned' else 'suspended' end,until_time,case when p_action='release' then '' else p_data->>'reason' end) on conflict(user_id) do update set state=excluded.state,until_at=excluded.until_at,reason=excluded.reason,updated_at=now();
 title=case when p_action='release' then 'Your Pulse account access was restored' when p_action='ban' then 'Your Pulse account is banned' else 'Your Pulse account is suspended' end;
 body=case when p_action='release' then 'You can sign in again.' else coalesce(p_data->>'reason','')||case when until_time is not null then ' Until '||until_time::text else '' end||'. You can submit a video appeal from the account restriction screen.' end;
 end if;
 insert into pulse_private.control_audit(staff_id,subject_id,action,detail) values(auth.uid(),p_user,p_action,p_data);
 insert into pulse_private.system_mail(user_id,title,body) values(p_user,title,body);
 select u.email into email from auth.users u where u.id=p_user and u.email_confirmed_at is not null;
 if email is not null then insert into pulse_private.email_jobs(user_id,recipient,subject,body) values(p_user,email,title,body);end if;
 return jsonb_build_object('updated',true,'email_queued',email is not null);
end $$;
create function public.pulse_control(p_action text,p_user uuid default null,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$ select pulse_private.control(p_action,p_user,p_data) $$;
revoke all on function pulse_private.control(text,uuid,jsonb),public.pulse_control(text,uuid,jsonb) from public,anon;
grant execute on function pulse_private.control(text,uuid,jsonb),public.pulse_control(text,uuid,jsonb) to authenticated;

create table pulse_private.appeals(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.pulse_profiles on delete cascade,phrase text not null,expires_at timestamptz not null default(now()+interval '15 minutes'),video_path text,state text not null default 'draft' check(state in('draft','submitted','accepted','rejected')),message text not null default '',created_at timestamptz not null default now());
create index appeals_user on pulse_private.appeals(user_id,created_at desc);
create function pulse_private.appeal_media(p_path text,p_write boolean) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and ((not p_write and pulse_private.account_active() and pulse_private.is_admin()) or exists(select 1 from pulse_private.appeals a where a.user_id=auth.uid() and split_part(p_path,'/',1)=auth.uid()::text and split_part(p_path,'/',2)=a.id::text and split_part(p_path,'/',3)='appeal-video' and array_length(string_to_array(p_path,'/'),1)=3 and (not p_write or a.state='draft' and a.expires_at>now())))
$$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('pulse-appeals','pulse-appeals',false,26214400,array['video/mp4','video/webm','video/quicktime']);
create policy appeal_upload on storage.objects for insert to authenticated with check(bucket_id='pulse-appeals' and pulse_private.appeal_media(name,true));
create policy appeal_read on storage.objects for select to authenticated using(bucket_id='pulse-appeals' and pulse_private.appeal_media(name,false));
revoke all on function pulse_private.appeal_media(text,boolean) from public,anon;
grant execute on function pulse_private.appeal_media(text,boolean) to authenticated;
create function pulse_private.appeals_api(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a pulse_private.appeals; result jsonb; phrase text; mail_body text;
begin
 if auth.uid() is null then raise exception 'Sign in to appeal';end if;
 if p_action='start' then
 perform pulse_private.social_rate('appeal_start',3,86400);
 phrase='Pulse appeal. '||(array['Violet river','Silver cloud','Golden forest','Quiet ocean'])[1+floor(random()*4)::int]||' '||left(encode(extensions.gen_random_bytes(8),'hex'),12);
 insert into pulse_private.appeals(user_id,phrase) values(auth.uid(),phrase) returning * into a;return to_jsonb(a);
 elsif p_action='submit' then
 select * into a from pulse_private.appeals where id=(p_data->>'id')::uuid and user_id=auth.uid() for update;
 if not found or a.state<>'draft' or a.expires_at<=now() then raise exception 'Appeal challenge expired or unavailable';end if;
 if coalesce((p_data->>'consent')::boolean,false) is not true then raise exception 'Consent is required to send the appeal video to Pulse support';end if;
 if length(coalesce(p_data->>'message',''))>2000 or not exists(select 1 from storage.objects where bucket_id='pulse-appeals' and name=p_data->>'path' and split_part(name,'/',1)=auth.uid()::text and split_part(name,'/',2)=a.id::text and metadata->>'mimetype' in('video/mp4','video/webm','video/quicktime') and (metadata->>'size')::bigint between 1 and 26214400) then raise exception 'Upload your appeal video (up to 25 MB)';end if;
 update pulse_private.appeals set state='submitted',video_path=p_data->>'path',message=coalesce(p_data->>'message','') where id=a.id;
 mail_body='New appeal '||a.id::text||'. Read phrase: '||a.phrase||'. User: '||auth.uid()::text||'. Message: '||coalesce(p_data->>'message','');
 insert into pulse_private.email_jobs(user_id,recipient,subject,body,video_path) values(auth.uid(),'pulseservicemanagement@gmail.com','Pulse video appeal',mail_body,p_data->>'path');
 return jsonb_build_object('submitted',true,'email_queued',true);
 elsif p_action='mine' then select coalesce(jsonb_agg(q),'[]') into result from(select id,state,created_at from pulse_private.appeals where user_id=auth.uid() order by created_at desc limit 20)q;return result;
 elsif p_action in('staff_list','accept','reject') then
 perform pulse_private.require_active();if not pulse_private.is_admin() then raise exception 'Staff access required';end if;
 if p_action='staff_list' then select coalesce(jsonb_agg(q),'[]') into result from(select a.*,p.username,p.display_name from pulse_private.appeals a join public.pulse_profiles p on p.id=a.user_id where a.state='submitted' order by a.created_at limit 50)q;return result;end if;
 select * into a from pulse_private.appeals where id=(p_data->>'id')::uuid and state='submitted' for update;
 if not found then raise exception 'Appeal unavailable';end if;
 if p_action='accept' then perform pulse_private.control('release',a.user_id,'{}');end if;
 update pulse_private.appeals set state=case when p_action='accept' then 'accepted' else 'rejected' end where id=a.id;
 insert into pulse_private.system_mail(user_id,title,body) values(a.user_id,'Appeal reviewed',case when p_action='accept' then 'Your appeal was accepted and account access restored.' else 'Your appeal was not accepted. Contact Pulse support if you have more information.' end);
 insert into pulse_private.control_audit(staff_id,subject_id,action,detail) values(auth.uid(),a.user_id,'appeal_'||p_action,jsonb_build_object('id',a.id));return 'true';
 end if;
 raise exception 'Unknown appeal action';end $$;
create function public.pulse_appeals(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$ select pulse_private.appeals_api(p_action,p_data) $$;
revoke all on function pulse_private.appeals_api(text,jsonb),public.pulse_appeals(text,jsonb) from public,anon;
grant execute on function pulse_private.appeals_api(text,jsonb),public.pulse_appeals(text,jsonb) to authenticated;

-- Explicitly deny raw access on all newly added private tables.
do $$ declare t text;begin foreach t in array array['account_limits','control_audit','system_mail','email_jobs','community_cards','community_requests','appeals'] loop execute format('alter table pulse_private.%I enable row level security',t);execute format('revoke all on pulse_private.%I from public,anon,authenticated',t);end loop;end $$;
-- Apply restriction checks to existing invoker RPCs too; a stale JWT cannot bypass them.
do $$ declare r record;def text;begin
 for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang where n.nspname='public' and p.proname like 'pulse_%' and l.lanname='sql' and not p.prosecdef and p.proname not in('pulse_account_status','pulse_appeals') loop
 def=pg_get_functiondef(r.oid);if position('select pulse_private.require_active();' in def)=0 then def=replace(def,'AS $function$','AS $function$ select pulse_private.require_active(); ');execute def;end if;
 end loop;
 for r in select tablename from pg_tables where schemaname='public' and tablename like 'pulse_%' loop execute format('create policy pulse_account_access on public.%I as restrictive for all to authenticated using(pulse_private.account_active()) with check(pulse_private.account_active())',r.tablename);end loop;
end $$;
create policy pulse_account_storage_access on storage.objects as restrictive for all to authenticated
using(pulse_private.account_active() or bucket_id='pulse-appeals' and pulse_private.appeal_media(name,false))
with check(pulse_private.account_active() or bucket_id='pulse-appeals' and pulse_private.appeal_media(name,true));
notify pgrst,'reload schema';
commit;
