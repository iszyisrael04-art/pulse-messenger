-- Owner-only role delegation; staff-created promotional rewards, not receipts.
begin;
create table pulse_private.staff_owners(user_id uuid primary key references auth.users on delete restrict);
-- Bootstrap only the existing sole administrator; never an arbitrary client.
insert into pulse_private.staff_owners select user_id from pulse_private.admins where (select count(*) from pulse_private.admins)=1;
alter table pulse_private.staff_owners enable row level security;
revoke all on pulse_private.staff_owners from public,anon,authenticated;
create policy deny_clients on pulse_private.staff_owners for all to authenticated using(false)with check(false);
create table pulse_private.reward_codes(id uuid primary key default gen_random_uuid(),code_hash text unique not null,kind text not null check(kind in('coins','views')),amount integer not null check(amount between 1 and 100000),max_uses integer not null check(max_uses between 1 and 1000),uses integer not null default 0,expires_at timestamptz not null,reward_days integer not null check(reward_days between 1 and 365),created_by uuid not null references auth.users,disabled boolean not null default false,created_at timestamptz not null default now());
create table pulse_private.reward_redemptions(code_id uuid references pulse_private.reward_codes,user_id uuid references auth.users,created_at timestamptz not null default now(),primary key(code_id,user_id));
create index reward_code_staff on pulse_private.reward_codes(created_by);
create index reward_user on pulse_private.reward_redemptions(user_id);
alter table pulse_private.reward_codes enable row level security;
alter table pulse_private.reward_redemptions enable row level security;
revoke all on pulse_private.reward_codes,pulse_private.reward_redemptions from public,anon,authenticated;
create policy deny_clients on pulse_private.reward_codes for all to authenticated using(false)with check(false);
create policy deny_clients on pulse_private.reward_redemptions for all to authenticated using(false)with check(false);
create function pulse_private.staff_rewards(p_action text,p_data jsonb)returns jsonb language plpgsql security definer set search_path=''as $$
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
 elsif p_action='disable'then
  update pulse_private.reward_codes set disabled=true where id=(p_data->>'id')::uuid;
 else raise exception 'Unknown action';end if;
 insert into pulse_private.control_audit(staff_id,action,detail)values(auth.uid(),'rewards_'||p_action,p_data- 'code');
 return jsonb_build_object('saved',true,'code',code,'id',cid);
end$$;
create function pulse_private.claim_reward(p_code text)returns jsonb language plpgsql security definer set search_path=''as $$
declare r pulse_private.reward_codes;sku text;
begin
 perform pulse_private.require_active();perform pulse_private.social_rate('reward_claim',5,60);
 if p_code is null or length(p_code)>100 then raise exception 'Invalid code';end if;
 select * into r from pulse_private.reward_codes where code_hash=encode(extensions.digest(upper(trim(p_code)),'sha256'),'hex')for update;
 if r.id is null or r.disabled or r.expires_at<=clock_timestamp()or r.uses>=r.max_uses then raise exception 'Code unavailable or expired';end if;
 if exists(select 1 from pulse_private.reward_redemptions where code_id=r.id and user_id=auth.uid())then raise exception 'Code already redeemed';end if;
 insert into pulse_private.reward_redemptions(code_id,user_id)values(r.id,auth.uid());
 if r.kind='coins'then
  insert into pulse_private.wallets(user_id,coins)values(auth.uid(),r.amount)on conflict(user_id)do update set coins=pulse_private.wallets.coins+excluded.coins;
 else
  sku='reward_'||r.id::text;
  insert into pulse_private.creator_products values(sku,'Promotional views',1,'once',r.amount)on conflict do nothing;
  insert into pulse_private.creator_purchases(user_id,sku,provider,receipt,usd_cents,ends_at)values(auth.uid(),sku,'admin-reward',r.id::text||':'||auth.uid()::text,0,clock_timestamp()+make_interval(days=>r.reward_days));
 end if;
 update pulse_private.reward_codes set uses=uses+1 where id=r.id;
 return jsonb_build_object('kind',r.kind,'amount',r.amount,'days',r.reward_days,'message',case when r.kind='coins'then 'Coins added. Coins are not withdrawable.'else 'Promotion activated. Real viewers are counted; views are not guaranteed.'end);
end$$;
create function public.pulse_staff_rewards(p_action text,p_data jsonb default '{}')returns jsonb language sql security invoker set search_path=''as $$select pulse_private.staff_rewards(p_action,p_data)$$;
create function public.pulse_claim_reward(p_code text)returns jsonb language sql security invoker set search_path=''as $$select pulse_private.claim_reward(p_code)$$;
revoke all on function pulse_private.staff_rewards(text,jsonb),pulse_private.claim_reward(text),public.pulse_staff_rewards(text,jsonb),public.pulse_claim_reward(text)from public,anon,authenticated;
grant execute on function pulse_private.staff_rewards(text,jsonb),pulse_private.claim_reward(text),public.pulse_staff_rewards(text,jsonb),public.pulse_claim_reward(text)to authenticated;
create or replace function pulse_private.payment_order(p_id uuid,p_sku text)returns jsonb language plpgsql security definer set search_path=''as $$
declare o pulse_private.payment_orders; amount integer; count integer:=0;
begin
 if p_sku like 'reward_%' then raise exception 'Promotional rewards cannot be purchased';end if;
 perform pulse_private.require_active();
 if p_id is null or p_sku is null then raise exception 'Invalid order';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,91));
 select * into o from pulse_private.payment_orders where id=p_id;
 if found then
 if o.user_id<>auth.uid()or o.sku<>p_sku then raise exception 'Order mismatch';end if;return to_jsonb(o);end if;
 perform pulse_private.social_rate('payment_order',3,60);
 if p_sku in('coins_100','coins_200','coins_500','coins_1000')then count=substring(p_sku from 7)::integer;amount=count;
 else select usd_cents into amount from pulse_private.creator_products where sku=p_sku;end if;
 if amount is null then raise exception 'Unknown product';end if;
 insert into pulse_private.payment_orders(id,user_id,sku,usd_cents,coins)values(p_id,auth.uid(),p_sku,amount,count)returning * into o;
 return to_jsonb(o);
end $$;
create or replace function pulse_private.confirm_creator_purchase(p_user uuid,p_sku text,p_provider text,p_receipt text,p_usd_cents integer) returns uuid
language plpgsql security definer set search_path='' as $$
declare product pulse_private.creator_products; prior pulse_private.creator_purchases; purchase uuid;
begin
 if p_sku like 'reward_%' then raise exception 'Promotional rewards cannot be purchased';end if;
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
create or replace function pulse_private.creator_access() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 perform pulse_private.require_active();
 return jsonb_build_object('motion',pulse_private.motion_allowed(auth.uid()),
 'motion_free',exists(select 1 from pulse_private.motion_access where user_id=auth.uid() and source='owner'),
 'checkout_enabled',false,'currency','USD',
 'products',(select jsonb_agg(to_jsonb(p) order by usd_cents) from pulse_private.creator_products p where p.sku not like 'reward_%'),
 'purchases',coalesce((select jsonb_agg(q) from (
  select c.id,c.sku,c.starts_at,c.ends_at,p.view_cap,
   (select count(*) from pulse_private.boost_views v where v.purchase_id=c.id) as delivered_views
  from pulse_private.creator_purchases c join pulse_private.creator_products p on p.sku=c.sku
  where c.user_id=auth.uid() and c.revoked_at is null order by c.created_at desc limit 30)q),'[]'::jsonb));
end $$;
commit;
