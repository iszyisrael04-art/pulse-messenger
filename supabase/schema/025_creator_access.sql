-- Pulse: free core features, standalone motion profiles and real-view promotion.
begin;
create table pulse_private.creator_products (
 sku text primary key, title text not null, usd_cents integer not null check(usd_cents>0),
 period text not null check(period in ('once','month','year')), view_cap integer not null default 0 check(view_cap>=0)
);
insert into pulse_private.creator_products values
 ('motion','Animated profile',100,'once',0),
 ('boost_50k','Boost 50K',2500,'month',50000),
 ('boost_100k','Boost 100K',4000,'month',100000),
 ('boost_500k','Boost 500K',100000,'year',500000);
create table pulse_private.creator_purchases (
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.pulse_profiles on delete cascade,
 sku text not null references pulse_private.creator_products,provider text not null,receipt text not null,
 usd_cents integer not null,starts_at timestamptz not null default now(),ends_at timestamptz,
 revoked_at timestamptz,created_at timestamptz not null default now(),unique(provider,receipt)
);
create index creator_purchase_owner on pulse_private.creator_purchases(user_id,starts_at,ends_at);
create table pulse_private.motion_access (
 user_id uuid primary key references public.pulse_profiles on delete cascade,
 source text not null check(source in ('owner','purchase')),granted_at timestamptz not null default now()
);
create table pulse_private.boost_views (
 purchase_id uuid references pulse_private.creator_purchases on delete cascade,
 post_id uuid references public.pulse_social_content on delete cascade,
 viewer_id uuid references public.pulse_profiles on delete cascade,
 created_at timestamptz not null default now(),primary key(purchase_id,post_id,viewer_id)
);
create table pulse_private.boost_exposures (
 purchase_id uuid references pulse_private.creator_purchases on delete cascade,
 post_id uuid references public.pulse_social_content on delete cascade,
 viewer_id uuid references public.pulse_profiles on delete cascade,
 served_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null default (clock_timestamp()+interval '10 minutes'),
 primary key(purchase_id,post_id,viewer_id)
);
alter table pulse_private.boost_exposures enable row level security;
revoke all on pulse_private.boost_exposures from public,anon,authenticated;
create index boost_view_post on pulse_private.boost_views(post_id);
alter table pulse_private.creator_products enable row level security;
alter table pulse_private.creator_purchases enable row level security;
alter table pulse_private.motion_access enable row level security;
alter table pulse_private.boost_views enable row level security;
revoke all on pulse_private.creator_products,pulse_private.creator_purchases,pulse_private.motion_access,pulse_private.boost_views from public,anon,authenticated;
-- The owner exemption is a stored grant independent of names or staff roles.
insert into pulse_private.motion_access(user_id,source)
 select p.id,'owner' from public.pulse_profiles p join pulse_private.admins a on a.user_id=p.id where p.username='iszy'
 on conflict(user_id) do update set source='owner';
create function pulse_private.motion_allowed(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from pulse_private.motion_access m where m.user_id=p_user and (m.source='owner' or exists(select 1 from pulse_private.creator_purchases p where p.user_id=m.user_id and p.sku='motion' and p.revoked_at is null)))
$$;
revoke all on function pulse_private.motion_allowed(uuid) from public,anon;
grant execute on function pulse_private.motion_allowed(uuid) to authenticated;
CREATE OR REPLACE FUNCTION pulse_private.social_size_allowed(p_size bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and p_size between 1 and 2147483648
$function$
;
CREATE OR REPLACE FUNCTION pulse_private.social_set_profile_style(p_theme text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_theme is null or p_theme not in ('classic','aurora','sunset','midnight','ocean','bloom','paper','circuit') then raise exception 'Unknown profile background'; end if;
 insert into public.pulse_social_accounts(user_id,profile_theme) values(auth.uid(),p_theme)
 on conflict(user_id) do update set profile_theme=excluded.profile_theme;
end $function$;
CREATE OR REPLACE FUNCTION pulse_private.social_profile_style(p_user uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select case when not pulse_private.social_blocked(p_user) then coalesce((select profile_theme from public.pulse_social_accounts where user_id=p_user),'classic') else 'classic' end
$function$
;
CREATE OR REPLACE FUNCTION pulse_private.profile_features_save(p_background text, p_signal text, p_mode text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_signal is null or length(p_signal)>120 or p_mode is null or p_mode not in ('creating','collaborating','learning','available') then raise exception 'Choose a valid Profile Signal of up to 120 characters'; end if;
 perform pulse_private.social_rate('profile_features',30,60);
 perform pulse_private.social_set_profile_style(p_background);
 insert into pulse_private.profile_signals(user_id,body,mode) values(auth.uid(),trim(p_signal),p_mode)
 on conflict(user_id) do update set body=excluded.body,mode=excluded.mode,updated_at=now();
end $function$;
CREATE OR REPLACE FUNCTION pulse_private.profile_features(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare expiry timestamptz; signal pulse_private.profile_signals;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_user is null or pulse_private.social_blocked(p_user) or not exists(select 1 from public.pulse_profiles where id=p_user) then return null; end if;
 if pulse_private.motion_allowed(p_user) then expiry=now()+interval '60 seconds'; end if;
 select * into signal from pulse_private.profile_signals where user_id=p_user;
 return jsonb_build_object('background',pulse_private.social_profile_style(p_user),
 'motion_until',case when expiry is not null then least(expiry,now()+interval '60 seconds') else null end,
 'signal',coalesce(signal.body,''),
 'mode',coalesce(signal.mode,'creating'));
end $function$
;
CREATE OR REPLACE FUNCTION pulse_private.avatar_upload_allowed(p_name text, p_mime text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and split_part(p_name,'/',1)=auth.uid()::text
 and ((p_mime in ('image/jpeg','image/png','image/webp') and lower(p_name) !~ '\.(gif|mp4)$')
 or (p_mime='image/gif' and lower(p_name) like '%.gif' and pulse_private.motion_allowed(auth.uid()))
 or (p_mime='video/mp4' and lower(p_name) like '%.mp4' and pulse_private.motion_allowed(auth.uid())))
$function$
;
CREATE OR REPLACE FUNCTION pulse_private.user_tools(p_action text, p_chat uuid DEFAULT NULL::uuid, p_id uuid DEFAULT NULL::uuid, p_label text DEFAULT NULL::text, p_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare who uuid:=auth.uid(); paid boolean; saved uuid; style_name text;
begin
 if who is null then raise exception 'Sign in required'; end if;
 if p_action in ('note_save','quick_save','quick_delete','style_save') then perform pulse_private.social_rate('chat_tools',60,60); end if;
 paid=true;
 if p_action in ('note_get','note_save','style_get','style_save') and not pulse_private.is_member(p_chat) then raise exception 'Chat unavailable'; end if;
 if p_action='note_get' then
  return jsonb_build_object('body',coalesce((select body from pulse_private.chat_notes where user_id=who and chat_id=p_chat),''));
 elsif p_action='note_save' then
  if p_text is null or length(p_text)>4000 then raise exception 'Note must be under 4000 characters'; end if;
  insert into pulse_private.chat_notes(user_id,chat_id,body) values(who,p_chat,p_text) on conflict(user_id,chat_id) do update set body=excluded.body,updated_at=now();
  return jsonb_build_object('saved',true);
 elsif p_action='quick_list' then
  return jsonb_build_object('available',true,'items',coalesce((select jsonb_agg(jsonb_build_object('id',id,'label',label,'body',body) order by label) from pulse_private.quick_replies where user_id=who),'[]'::jsonb));
 elsif p_action='quick_save' then
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
  select id into saved from pulse_private.quick_replies where id=p_id and user_id=who;
  if saved is null then raise exception 'Reply unavailable'; end if;
  return (select jsonb_build_object('body',body) from pulse_private.quick_replies where id=saved);
 elsif p_action='style_get' then
  select style into style_name from pulse_private.chat_styles where user_id=who and chat_id=p_chat;
  return jsonb_build_object('available',true,'style',case when paid then coalesce(style_name,'classic') else 'classic' end);
 elsif p_action='style_save' then
  if p_label is null or p_label not in ('classic','aurora','rose','ocean') then raise exception 'Unknown style'; end if;
  insert into pulse_private.chat_styles(user_id,chat_id,style) values(who,p_chat,p_label) on conflict(user_id,chat_id) do update set style=excluded.style;
  return jsonb_build_object('style',p_label);
 end if;
 raise exception 'Unknown chat tool';
end
$function$;
CREATE OR REPLACE FUNCTION pulse_private.social_card(p_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
select to_jsonb(c)||jsonb_build_object(
 'author',(select jsonb_build_object('id',p.id,'username',p.username,'display_name',p.display_name,'bio',p.bio,'avatar_path',p.avatar_path,
 'verified',coalesce(a.verified,false),'premium',false) from public.pulse_profiles p left join public.pulse_social_accounts a on a.user_id=p.id where p.id=c.author_id),
 'likes',(select count(*) from public.pulse_social_likes where post_id=c.id),
 'comments',(select count(*) from public.pulse_social_comments where post_id=c.id and deleted_at is null and not pulse_private.social_blocked(author_id)),
 'views',(select count(*) from public.pulse_social_views where post_id=c.id),
 'shares',(select count(*) from pulse_private.social_shares where post_id=c.id),
 'reposts',(select count(*) from public.pulse_social_reposts where post_id=c.id),
 'liked',exists(select 1 from public.pulse_social_likes where post_id=c.id and user_id=auth.uid()),
 'saved',exists(select 1 from public.pulse_social_saves where post_id=c.id and user_id=auth.uid()),
 'reposted',exists(select 1 from public.pulse_social_reposts where post_id=c.id and user_id=auth.uid()),
 'follow_state',coalesce((select state from public.pulse_social_follows where follower_id=auth.uid() and creator_id=c.author_id),'none'))
 from public.pulse_social_content c where c.id=p_id and pulse_private.social_read(c.id)
$function$
;
create or replace function pulse_private.redeem(p_code text) returns timestamptz language plpgsql security definer set search_path='' as $$ begin raise exception 'Redemption codes have been retired'; end $$;
create or replace function pulse_private.redeem_result(p_code text) returns jsonb language plpgsql security definer set search_path='' as $$ begin raise exception 'Redemption codes have been retired'; end $$;
revoke all on function public.pulse_redeem(text),public.pulse_redeem_result(text),pulse_private.redeem(text),pulse_private.redeem_result(text) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION pulse_private.admin_action(p_action text, p_data jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 begin
 if not pulse_private.is_admin() then raise exception 'Administrator required'; end if;
 if p_action='report' then update public.pulse_reports set state=p_data->>'state' where id=(p_data->>'id')::uuid;
 elsif p_action='verify_channel' then update public.pulse_channels set verified=(p_data->>'verified')::boolean where id=(p_data->>'id')::uuid;
 elsif p_action='announcement' then insert into public.pulse_announcements(body) values(p_data->>'body');
 elsif p_action='flag' then insert into public.pulse_feature_flags(key,value) values(p_data->>'key',(p_data->>'value')::boolean) on conflict(key) do update set value=excluded.value;
 else raise exception 'Invalid admin action'; end if;
 end
$function$
;
CREATE OR REPLACE FUNCTION pulse_private.admin_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 begin
 if not pulse_private.is_admin() then raise exception 'Administrator required'; end if;
 return jsonb_build_object('users',(select count(*) from public.pulse_profiles),'messages',(select count(*) from public.pulse_messages),'groups',(select count(*) from public.pulse_chats where kind='group'),'channels',(select count(*) from public.pulse_channels),'reports',(select coalesce(jsonb_agg(r),'[]'::jsonb) from (select * from public.pulse_reports order by created_at desc limit 100) r));
 end
$function$
;
-- Called only by a trusted receipt-verification worker, after checking the
-- provider's signature/API, product, USD amount and purchaser identity.
-- Never grant this function to mobile clients; checkout is not connected yet.
create function pulse_private.confirm_creator_purchase(p_user uuid,p_sku text,p_provider text,p_receipt text,p_usd_cents integer) returns uuid
language plpgsql security definer set search_path='' as $$
declare product pulse_private.creator_products; prior pulse_private.creator_purchases; purchase uuid;
begin
 if current_setting('request.jwt.claim.role',true) is distinct from 'service_role'
 and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','')<>'service_role'
 then raise exception 'Receipt verifier required'; end if;
 if p_user is null or p_provider is null or p_receipt is null or length(trim(p_provider)) not between 1 and 40 or length(trim(p_receipt)) not between 1 and 300 then raise exception 'Invalid purchase';end if;
 select * into product from pulse_private.creator_products where sku=p_sku;
 if product.sku is null or p_usd_cents is distinct from product.usd_cents then raise exception 'Price mismatch';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_provider||':'||p_receipt,66));
 select * into prior from pulse_private.creator_purchases where provider=p_provider and receipt=p_receipt;
 if found then
  if prior.user_id<>p_user or prior.sku<>p_sku or prior.usd_cents<>p_usd_cents or prior.revoked_at is not null then raise exception 'Receipt mismatch';end if;
  return prior.id;
 end if;
 insert into pulse_private.creator_purchases(user_id,sku,provider,receipt,usd_cents,ends_at)
 values(p_user,p_sku,p_provider,p_receipt,p_usd_cents,case product.period when 'month' then now()+interval '1 month' when 'year' then now()+interval '1 year' else null end) returning id into purchase;
 if p_sku='motion' then insert into pulse_private.motion_access(user_id,source) values(p_user,'purchase') on conflict do nothing;end if;
 return purchase;
end $$;
create function public.pulse_confirm_creator_purchase(p_user uuid,p_sku text,p_provider text,p_receipt text,p_usd_cents integer) returns uuid
language sql security invoker set search_path='' as $$select pulse_private.confirm_creator_purchase(p_user,p_sku,p_provider,p_receipt,p_usd_cents)$$;
revoke all on function pulse_private.confirm_creator_purchase(uuid,text,text,text,integer),public.pulse_confirm_creator_purchase(uuid,text,text,text,integer) from public,anon,authenticated;
grant execute on function pulse_private.confirm_creator_purchase(uuid,text,text,text,integer),public.pulse_confirm_creator_purchase(uuid,text,text,text,integer) to service_role;
create function pulse_private.creator_access() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform pulse_private.require_active();
 return jsonb_build_object('motion',pulse_private.motion_allowed(auth.uid()),
 'motion_free',exists(select 1 from pulse_private.motion_access where user_id=auth.uid() and source='owner'),
 'checkout_enabled',false,'currency','USD',
 'products',(select jsonb_agg(to_jsonb(p) order by usd_cents) from pulse_private.creator_products p),
 'purchases',coalesce((select jsonb_agg(q) from (
  select c.id,c.sku,c.starts_at,c.ends_at,p.view_cap,
   (select count(*) from pulse_private.boost_views v where v.purchase_id=c.id) as delivered_views
  from pulse_private.creator_purchases c join pulse_private.creator_products p on p.sku=c.sku
  where c.user_id=auth.uid() and c.revoked_at is null order by c.created_at desc limit 30)q),'[]'::jsonb));
end $$;
create function public.pulse_creator_access() returns jsonb language sql stable security invoker set search_path='' as $$select pulse_private.creator_access()$$;
revoke all on function pulse_private.creator_access(),public.pulse_creator_access() from public,anon;
grant execute on function pulse_private.creator_access(),public.pulse_creator_access() to authenticated;
-- Candidates are existing public videos. Payment never manufactures a view.
create function pulse_private.boost_candidate() returns jsonb language plpgsql security definer set search_path='' as $$
declare candidate uuid; purchase uuid;
begin
 perform pulse_private.require_active();
 select c.id,b.id into candidate,purchase from public.pulse_social_content c
 join pulse_private.creator_purchases b on b.user_id=c.author_id
 join pulse_private.creator_products p on p.sku=b.sku
 where c.state='published' and not c.hidden and c.audience='public' and c.author_id<>auth.uid()
 and exists(select 1 from jsonb_array_elements(c.media) m where m->>'kind'='video')
 and b.starts_at<=now() and b.ends_at>now() and b.revoked_at is null and p.view_cap>0
 and pulse_private.social_read(c.id)
 and not exists(select 1 from public.pulse_social_accounts a where a.user_id=c.author_id and a.is_private)
 and not exists(select 1 from public.pulse_social_views v where v.post_id=c.id and v.user_id=auth.uid())
 and not exists(select 1 from pulse_private.boost_views v where v.purchase_id=b.id and v.post_id=c.id and v.viewer_id=auth.uid())
 and (select count(*) from pulse_private.boost_views v where v.purchase_id=b.id and v.post_id=c.id)<p.view_cap
 order by (select count(*) from pulse_private.boost_views v where v.post_id=c.id),c.created_at desc,c.id limit 1;
 if candidate is null then return null;end if;
 insert into pulse_private.boost_exposures(purchase_id,post_id,viewer_id) values(purchase,candidate,auth.uid())
 on conflict(purchase_id,post_id,viewer_id) do update set
 served_at=case when pulse_private.boost_exposures.expires_at<clock_timestamp() then clock_timestamp() else pulse_private.boost_exposures.served_at end,
 expires_at=clock_timestamp()+interval '10 minutes';
 return pulse_private.social_card(candidate)||jsonb_build_object('promoted',true);
end $$;
create function public.pulse_boost_candidate() returns jsonb language sql security invoker set search_path='' as $$select pulse_private.boost_candidate()$$;
revoke all on function pulse_private.boost_candidate(),public.pulse_boost_candidate() from public,anon;
grant execute on function pulse_private.boost_candidate(),public.pulse_boost_candidate() to authenticated;
create function pulse_private.boost_view(p_post uuid) returns void language plpgsql security definer set search_path='' as $$
declare b record;
begin
 perform pulse_private.require_active();
 if not exists(select 1 from public.pulse_social_content c where c.id=p_post and c.author_id<>auth.uid() and c.state='published' and not c.hidden and c.audience='public' and pulse_private.social_read(c.id) and not exists(select 1 from public.pulse_social_accounts a where a.user_id=c.author_id and a.is_private)) then return;end if;
 select q.id,p.view_cap into b from pulse_private.creator_purchases q
 join pulse_private.creator_products p on p.sku=q.sku join public.pulse_social_content c on c.author_id=q.user_id
 where c.id=p_post and exists(select 1 from pulse_private.boost_exposures e where e.purchase_id=q.id and e.post_id=p_post and e.viewer_id=auth.uid() and e.served_at<=clock_timestamp()-interval '3 seconds' and e.expires_at>clock_timestamp()) and q.revoked_at is null and q.starts_at<=now() and q.ends_at>now() and p.view_cap>0
 order by p.view_cap desc,q.created_at desc limit 1;
 if not found then return;end if;
 perform pg_advisory_xact_lock(hashtextextended(b.id::text||':'||p_post::text,67));
 if (select count(*) from pulse_private.boost_views where purchase_id=b.id and post_id=p_post)<b.view_cap then
 insert into pulse_private.boost_views(purchase_id,post_id,viewer_id) values(b.id,p_post,auth.uid()) on conflict do nothing;
 end if;
end $$;
revoke all on function pulse_private.boost_view(uuid) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION pulse_private.social_action(p_id uuid, p_action text, p_enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform pulse_private.social_rate('engagement',300,60);
 if p_enabled is null or not pulse_private.social_read(p_id) or not exists(select 1 from public.pulse_social_content where id=p_id and state='published' and not hidden) then raise exception 'Post unavailable'; end if;
 if p_action='view' and p_enabled then perform pulse_private.boost_view(p_id); end if;
 if p_action='like' then
 if p_enabled then insert into public.pulse_social_likes values(p_id,auth.uid()) on conflict do nothing; else delete from public.pulse_social_likes where post_id=p_id and user_id=auth.uid(); end if;
 elsif p_action='save' then
 if p_enabled then insert into public.pulse_social_saves values(p_id,auth.uid()) on conflict do nothing; else delete from public.pulse_social_saves where post_id=p_id and user_id=auth.uid(); end if;
 elsif p_action='repost' then
 if p_enabled then insert into public.pulse_social_reposts(post_id,user_id) values(p_id,auth.uid()) on conflict do nothing; else delete from public.pulse_social_reposts where post_id=p_id and user_id=auth.uid(); end if;
 elsif p_action='view' then
 if (select author_id from public.pulse_social_content where id=p_id)<>auth.uid() then insert into public.pulse_social_views(post_id,user_id) values(p_id,auth.uid()) on conflict do nothing; end if;
 else raise exception 'Unknown action'; end if;
end
$function$
;
CREATE OR REPLACE FUNCTION pulse_private.social_profile(p_user uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if pulse_private.social_blocked(p_user) then raise exception 'Profile unavailable'; end if;
 select jsonb_build_object('id',p.id,'username',p.username,'display_name',p.display_name,'bio',p.bio,'avatar_path',p.avatar_path,
 'cover_path',a.cover_path,'is_private',coalesce(a.is_private,false),'verified',coalesce(a.verified,false),
 'premium',false,
 'follow_state',coalesce((select state from public.pulse_social_follows where follower_id=auth.uid() and creator_id=p.id),'none'),
 'followers',(select count(*) from public.pulse_social_follows where creator_id=p.id and state='accepted'),
 'following',(select count(*) from public.pulse_social_follows where follower_id=p.id and state='accepted'),
 'likes',(select count(*) from public.pulse_social_likes l join public.pulse_social_content c on c.id=l.post_id where c.author_id=p.id and c.state='published'),
 'analytics',case when p.id=auth.uid() then jsonb_build_object(
 'posts',(select count(*) from public.pulse_social_content where author_id=p.id and state='published' and kind='post'),
 'reels',(select count(*) from public.pulse_social_content where author_id=p.id and state='published' and kind='reel'),
 'views',(select count(*) from public.pulse_social_views v join public.pulse_social_content c on c.id=v.post_id where c.author_id=p.id and c.state='published'),
 'likes',(select count(*) from public.pulse_social_likes l join public.pulse_social_content c on c.id=l.post_id where c.author_id=p.id and c.state='published'),
 'comments',(select count(*) from public.pulse_social_comments m join public.pulse_social_content c on c.id=m.post_id where c.author_id=p.id and c.state='published' and m.deleted_at is null)) else null end)
 into result from public.pulse_profiles p left join public.pulse_social_accounts a on a.user_id=p.id where p.id=p_user;
 return result;
end
$function$
;
CREATE OR REPLACE FUNCTION pulse_private.social_upload_access(p_bytes bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_bytes is null or p_bytes<=0 then raise exception 'Empty file'; end if;
 return jsonb_build_object('allowed',pulse_private.social_size_allowed(p_bytes),'premium',false,'maximum',2147483648);
 end
$function$
;
create policy creator_products_no_direct_access on pulse_private.creator_products for all to anon,authenticated using(false) with check(false);
create policy creator_purchases_no_direct_access on pulse_private.creator_purchases for all to anon,authenticated using(false) with check(false);
create policy motion_access_no_direct_access on pulse_private.motion_access for all to anon,authenticated using(false) with check(false);
create policy boost_views_no_direct_access on pulse_private.boost_views for all to anon,authenticated using(false) with check(false);
create policy boost_exposures_no_direct_access on pulse_private.boost_exposures for all to anon,authenticated using(false) with check(false);
notify pgrst,'reload schema';
commit;
