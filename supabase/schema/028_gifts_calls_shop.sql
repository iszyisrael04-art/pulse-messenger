-- Additive release schema. Existing messages, accounts and receipts are retained.
begin;
alter table public.pulse_call_members add column received_at timestamptz;
create function pulse_private.call_received(p_call uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform pulse_private.require_active();
 perform pulse_private.cleanup_call(p_call);
 update public.pulse_call_members m set received_at=coalesce(m.received_at,clock_timestamp())
 from public.pulse_calls c where c.id=p_call and m.call_id=c.id and m.user_id=auth.uid()
 and m.state='ringing' and c.status<>'ended' and c.ring_deadline>now()
 and pulse_private.is_member(c.chat_id)
 and not pulse_private.social_blocked(c.caller_id);
 return found;
end $$;
create function public.pulse_call_received(p_call uuid) returns boolean language sql security invoker set search_path='' as $$select pulse_private.call_received(p_call)$$;
revoke all on function pulse_private.call_received(uuid),public.pulse_call_received(uuid) from public,anon;
grant execute on function pulse_private.call_received(uuid),public.pulse_call_received(uuid) to authenticated;

create table pulse_private.gift_catalog(sku text primary key,title text not null,emoji text not null,coins integer not null check(coins>0),p_coins integer not null check(p_coins>0 and p_coins<=coins),enabled boolean not null default true);
insert into pulse_private.gift_catalog values
 ('rose','Rose','🌹',5,2,true),('heart','Heart','💖',10,4,true),('coffee','Coffee','☕',25,10,true),('star','Star','⭐',50,20,true),('fire','Fire','🔥',100,40,true),('crown','Crown','👑',250,100,true),('diamond','Diamond','💎',500,200,true),('rocket','Rocket','🚀',1000,400,true),('galaxy','Galaxy','🌌',2500,1000,true),('lion','Lion','🦁',5000,2000,true);
create table pulse_private.wallets(user_id uuid primary key references public.pulse_profiles on delete cascade,coins bigint not null default 0 check(coins>=0),p_coins bigint not null default 0 check(p_coins>=0));
create table pulse_private.coin_receipts(provider text not null,receipt text not null,user_id uuid not null references public.pulse_profiles on delete cascade,coins integer not null check(coins>0),usd_cents integer not null check(usd_cents>0),created_at timestamptz not null default now(),primary key(provider,receipt));
create table pulse_private.gift_events(id uuid primary key,sender_id uuid not null references public.pulse_profiles on delete cascade,recipient_id uuid not null references public.pulse_profiles on delete cascade,session_id uuid not null references public.pulse_live_sessions on delete cascade,sku text not null references pulse_private.gift_catalog,quantity integer not null check(quantity between 1 and 100),coins bigint not null check(coins>0),p_coins bigint not null check(p_coins>0),created_at timestamptz not null default clock_timestamp());
create index gift_events_session on pulse_private.gift_events(session_id,created_at desc);
create index gift_events_sender on pulse_private.gift_events(sender_id,created_at desc);
create index gift_events_recipient on pulse_private.gift_events(recipient_id,created_at desc);
create table pulse_private.live_battles(id uuid primary key default gen_random_uuid(),session_id uuid not null references public.pulse_live_sessions on delete cascade,host_id uuid not null references public.pulse_profiles on delete cascade,opponent_id uuid not null references public.pulse_profiles check(host_id<>opponent_id),state text not null default 'invited' check(state in('invited','active','ended','declined')),created_at timestamptz not null default clock_timestamp(),starts_at timestamptz,ends_at timestamptz);
create index live_battles_session on pulse_private.live_battles(session_id,created_at desc);
create table pulse_private.cashout_policy(singleton boolean primary key default true check(singleton),enabled boolean not null default false,usd_cents_per_pcoin integer not null default 3 check(usd_cents_per_pcoin>0),minimum_pcoins integer not null default 100 check(minimum_pcoins>0));
insert into pulse_private.cashout_policy(singleton) values(true);
-- No cashout/payout route is enabled until a verified provider adapter is installed.
-- Normal coins have no withdrawal endpoint; P-coins can only be earned from gifts.
do $$declare t text;begin
 foreach t in array array['gift_catalog','wallets','coin_receipts','gift_events','live_battles','cashout_policy'] loop
 execute format('alter table pulse_private.%I enable row level security',t);
 execute format('revoke all on pulse_private.%I from public,anon,authenticated',t);
 execute format('create policy deny_clients on pulse_private.%I for all to anon,authenticated using(false) with check(false)',t);
 end loop;
end $$;

create function pulse_private.wallet() returns jsonb language plpgsql security definer set search_path='' as $$
declare w pulse_private.wallets;
begin
 perform pulse_private.require_active();
 select * into w from pulse_private.wallets where user_id=auth.uid();
 return jsonb_build_object('coins',coalesce(w.coins,0),'p_coins',coalesce(w.p_coins,0),'cashout_enabled',false,'pcoin_usd_cents',3,'cash_value_usd_cents',coalesce(w.p_coins,0)*3,
 'cashout_message','P-coins are creator earnings. 100 P-coins are valued at $3. Bank withdrawals are unavailable until the payout service and verification are configured.',
 'gifts',(select jsonb_agg(to_jsonb(g) order by coins) from pulse_private.gift_catalog g where enabled),
 'coin_packs',jsonb_build_array(jsonb_build_object('sku','coins_50','coins',50,'usd_cents',100),jsonb_build_object('sku','coins_100','coins',100,'usd_cents',200),jsonb_build_object('sku','coins_500','coins',500,'usd_cents',1000),jsonb_build_object('sku','coins_1000','coins',1000,'usd_cents',2000)),
 'transactions',coalesce((select jsonb_agg(x) from(select id,sku,quantity,coins,p_coins,created_at,sender_id=auth.uid() outgoing from pulse_private.gift_events where sender_id=auth.uid() or recipient_id=auth.uid() order by created_at desc limit 50)x),'[]'));
end $$;

create function pulse_private.credit_coins(p_user uuid,p_provider text,p_receipt text,p_coins integer,p_usd_cents integer) returns boolean language plpgsql security definer set search_path='' as $$
declare prior pulse_private.coin_receipts;
begin
 if coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role',current_setting('request.jwt.claim.role',true),'')<>'service_role' then raise exception 'Verified provider required';end if;
 if p_provider<>'squad-live' or length(p_receipt) not between 1 and 300 or p_user is null or p_coins not in(50,100,500,1000) or p_usd_cents<>p_coins*2 then raise exception 'Invalid coin purchase';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_provider||':'||p_receipt,88));
 select * into prior from pulse_private.coin_receipts where provider=p_provider and receipt=p_receipt;
 if found then
 if prior.user_id<>p_user or prior.coins<>p_coins or prior.usd_cents<>p_usd_cents then raise exception 'Receipt mismatch';end if;return false;end if;
 insert into pulse_private.coin_receipts values(p_provider,p_receipt,p_user,p_coins,p_usd_cents,now());
 insert into pulse_private.wallets(user_id,coins)values(p_user,p_coins) on conflict(user_id)do update set coins=pulse_private.wallets.coins+excluded.coins;
 return true;
end $$;

create function pulse_private.live_gifts(p_action text,p_session uuid,p_recipient uuid,p_sku text,p_quantity integer,p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.pulse_live_sessions; g pulse_private.gift_catalog; prior pulse_private.gift_events; spend bigint; earned bigint; u uuid;
begin
 perform pulse_private.require_active();
 select * into s from public.pulse_live_sessions where id=p_session for update;
 if s.id is null or pulse_private.social_blocked(s.host_id) then raise exception 'LIVE unavailable';end if;
 if p_action='info' then
 return jsonb_build_object('gifts',(select jsonb_agg(to_jsonb(c)order by coins)from pulse_private.gift_catalog c where enabled),'recent',coalesce((select jsonb_agg(x)from(select e.id,e.recipient_id,e.sku,e.quantity,e.created_at,p.display_name from pulse_private.gift_events e join public.pulse_profiles p on p.id=e.sender_id where e.session_id=p_session and not pulse_private.social_blocked(e.sender_id) order by e.created_at desc limit 12)x),'[]'));
 end if;
 if p_action<>'send' then raise exception 'Invalid gift action';end if;
 if p_id is null or p_quantity is null or p_quantity not between 1 and 100 then raise exception 'Invalid gift quantity';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,89));
 select * into prior from pulse_private.gift_events where id=p_id;
 if found then
 if prior.sender_id<>auth.uid() or prior.recipient_id<>p_recipient or prior.session_id<>p_session or prior.sku<>p_sku or prior.quantity<>p_quantity then raise exception 'Gift retry mismatch';end if;
 return jsonb_build_object('sent',true,'id',prior.id);end if;
 if s.status<>'live' or s.expires_at<=now() then raise exception 'LIVE ended';end if;
 if p_recipient is null or p_recipient=auth.uid() or pulse_private.social_blocked(p_recipient) then raise exception 'Cannot send this gift';end if;
 if p_recipient<>s.host_id and not exists(select 1 from pulse_private.live_guests where session_id=p_session and user_id=p_recipient and state='approved') then raise exception 'Choose a host or approved guest';end if;
 if exists(select 1 from pulse_private.account_limits where user_id=p_recipient and(state='banned' or state='suspended' and until_at>now())) then raise exception 'Recipient unavailable';end if;
 select * into g from pulse_private.gift_catalog where sku=p_sku and enabled;
 if g.sku is null then raise exception 'Gift unavailable';end if;
 spend=g.coins::bigint*p_quantity;earned=g.p_coins::bigint*p_quantity;
 perform pulse_private.social_rate('send_gift',30,60);
 -- Stable wallet lock order prevents reciprocal gift deadlocks.
 for u in select unnest(array[auth.uid(),p_recipient]) order by 1 loop
 insert into pulse_private.wallets(user_id)values(u)on conflict do nothing;
 perform 1 from pulse_private.wallets where user_id=u for update;
 end loop;
 update pulse_private.wallets set coins=coins-spend where user_id=auth.uid() and coins>=spend;
 if not found then raise exception 'Not enough normal coins';end if;
 update pulse_private.wallets set p_coins=p_coins+earned where user_id=p_recipient;
 insert into pulse_private.gift_events values(p_id,auth.uid(),p_recipient,p_session,p_sku,p_quantity,spend,earned,clock_timestamp());
 return jsonb_build_object('sent',true,'id',p_id,'coins_spent',spend,'p_coins_earned',earned);
end $$;

create function pulse_private.live_battle(p_action text,p_session uuid,p_opponent uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.pulse_live_sessions;b pulse_private.live_battles; hs bigint; os bigint;
begin
 perform pulse_private.require_active();
 select * into s from public.pulse_live_sessions where id=p_session for update;
 if s.id is null or pulse_private.social_blocked(s.host_id) then raise exception 'LIVE unavailable';end if;
 select * into b from pulse_private.live_battles where session_id=p_session order by created_at desc,id desc limit 1 for update;
 if b.state='active' and (b.ends_at<=now() or s.status<>'live' or s.expires_at<=now() or not exists(select 1 from pulse_private.live_guests where session_id=p_session and user_id=b.opponent_id and state='approved')) or b.state='invited' and (b.created_at<now()-interval '60 seconds' or s.status<>'live') then
 update pulse_private.live_battles set state='ended',ends_at=least(coalesce(ends_at,now()),clock_timestamp()) where id=b.id returning * into b;end if;
 if p_action='invite' then
 if s.host_id<>auth.uid() or s.status<>'live' or s.expires_at<=now() then raise exception 'Active host required';end if;
 if b.state in('invited','active') then raise exception 'A battle is already open';end if;
 if p_opponent=auth.uid() or p_opponent is null or pulse_private.social_blocked(p_opponent) or not exists(select 1 from pulse_private.live_guests where session_id=p_session and user_id=p_opponent and state='approved')then raise exception 'Choose an approved guest';end if;
 insert into pulse_private.live_battles(session_id,host_id,opponent_id)values(p_session,auth.uid(),p_opponent)returning * into b;
 elsif p_action in('accept','decline') then
 if b.state<>'invited' or b.opponent_id<>auth.uid() or s.status<>'live' or s.expires_at<=now() then raise exception 'Invitation unavailable';end if;
 if not exists(select 1 from pulse_private.live_guests where session_id=p_session and user_id=auth.uid() and state='approved')then raise exception 'Join the stage first';end if;
 update pulse_private.live_battles set state=case when p_action='accept' then 'active' else 'declined' end,starts_at=case when p_action='accept' then clock_timestamp()end,ends_at=case when p_action='accept' then clock_timestamp()+interval '3 minutes'end where id=b.id returning * into b;
 elsif p_action='end' then
 if auth.uid() not in(b.host_id,b.opponent_id) then raise exception 'Battle participant required';end if;
 update pulse_private.live_battles set state='ended',ends_at=least(coalesce(ends_at,now()),clock_timestamp())where id=b.id returning * into b;
 elsif p_action<>'info' then raise exception 'Invalid battle action';end if;
 if b.id is null then return '{}'::jsonb;end if;
 select coalesce(sum(coins)filter(where recipient_id=b.host_id),0),coalesce(sum(coins)filter(where recipient_id=b.opponent_id),0) into hs,os from pulse_private.gift_events where session_id=p_session and created_at>=b.starts_at and created_at<=b.ends_at;
 return to_jsonb(b)||jsonb_build_object('host_score',hs,'opponent_score',os,'remaining',greatest(0,extract(epoch from b.ends_at-now())::integer),'winner',case when b.state='ended' and hs<>os then case when hs>os then b.host_id else b.opponent_id end else null end);
end $$;

create function public.pulse_wallet()returns jsonb language sql security invoker set search_path=''as $$select pulse_private.wallet()$$;
create function public.pulse_live_gifts(p_action text,p_session uuid,p_recipient uuid default null,p_sku text default null,p_quantity integer default 1,p_id uuid default null)returns jsonb language sql security invoker set search_path=''as $$select pulse_private.live_gifts(p_action,p_session,p_recipient,p_sku,p_quantity,p_id)$$;
create function public.pulse_live_battle(p_action text,p_session uuid,p_opponent uuid default null)returns jsonb language sql security invoker set search_path=''as $$select pulse_private.live_battle(p_action,p_session,p_opponent)$$;
create function public.pulse_credit_coins(p_user uuid,p_provider text,p_receipt text,p_coins integer,p_usd_cents integer)returns boolean language sql security invoker set search_path=''as $$select pulse_private.credit_coins(p_user,p_provider,p_receipt,p_coins,p_usd_cents)$$;
revoke all on function pulse_private.wallet(),public.pulse_wallet(),pulse_private.live_gifts(text,uuid,uuid,text,integer,uuid),public.pulse_live_gifts(text,uuid,uuid,text,integer,uuid),pulse_private.live_battle(text,uuid,uuid),public.pulse_live_battle(text,uuid,uuid),pulse_private.credit_coins(uuid,text,text,integer,integer),public.pulse_credit_coins(uuid,text,text,integer,integer)from public,anon,authenticated;
grant execute on function pulse_private.wallet(),public.pulse_wallet(),pulse_private.live_gifts(text,uuid,uuid,text,integer,uuid),public.pulse_live_gifts(text,uuid,uuid,text,integer,uuid),pulse_private.live_battle(text,uuid,uuid),public.pulse_live_battle(text,uuid,uuid)to authenticated;
grant execute on function pulse_private.credit_coins(uuid,text,text,integer,integer),public.pulse_credit_coins(uuid,text,text,integer,integer)to service_role;

-- Durable call invitations are separate from private message push payloads.
create table pulse_private.call_push_outbox(call_id uuid not null references public.pulse_calls on delete cascade,recipient_id uuid not null references public.pulse_profiles on delete cascade,attempts integer not null default 0,available_at timestamptz not null default now(),done boolean not null default false,primary key(call_id,recipient_id));
alter table pulse_private.call_push_outbox enable row level security;
revoke all on pulse_private.call_push_outbox from public,anon,authenticated;
create policy deny_clients on pulse_private.call_push_outbox for all to anon,authenticated using(false)with check(false);
create function pulse_private.queue_call_push()returns trigger language plpgsql security definer set search_path=''as $$begin
 if new.state='ringing'then insert into pulse_private.call_push_outbox(call_id,recipient_id)values(new.call_id,new.user_id)on conflict do nothing;end if;return new;end $$;
revoke all on function pulse_private.queue_call_push()from public,anon,authenticated;
create trigger pulse_queue_call_push after insert on public.pulse_call_members for each row execute function pulse_private.queue_call_push();
create function pulse_private.call_push_jobs()returns jsonb language plpgsql security definer set search_path=''as $$declare result jsonb;begin
 with next as(select o.call_id,o.recipient_id from pulse_private.call_push_outbox o where not done and attempts<3 and available_at<=now() order by available_at for update skip locked limit 20), leased as(update pulse_private.call_push_outbox o set attempts=attempts+1,available_at=now()+interval '10 seconds'from next n where o.call_id=n.call_id and o.recipient_id=n.recipient_id returning o.*)
 select coalesce(jsonb_agg(jsonb_build_object('call_id',o.call_id,'recipient_id',o.recipient_id,'kind',c.kind,'expires_at',c.ring_deadline,'tokens',(select coalesce(jsonb_agg(d.token),'[]')from pulse_private.push_devices d where d.user_id=o.recipient_id))),'[]')into result
 from leased o join public.pulse_calls c on c.id=o.call_id join public.pulse_call_members m on m.call_id=c.id and m.user_id=o.recipient_id
 where c.status='ringing' and c.ring_deadline>now() and m.state='ringing'and m.received_at is null
 and exists(select 1 from public.pulse_members where chat_id=c.chat_id and user_id=o.recipient_id)
 and not exists(select 1 from public.pulse_blocks where(user_id=c.caller_id and blocked_id=o.recipient_id)or(user_id=o.recipient_id and blocked_id=c.caller_id))
 and not exists(select 1 from pulse_private.account_limits where user_id in(c.caller_id,o.recipient_id)and(state='banned'or state='suspended'and until_at>now()));
 return result;end $$;
create function pulse_private.call_push_finish(p_call uuid,p_user uuid,p_done boolean)returns void language sql security definer set search_path=''as $$update pulse_private.call_push_outbox set done=p_done where call_id=p_call and recipient_id=p_user$$;
create function public.pulse_call_push_jobs()returns jsonb language sql security invoker set search_path=''as $$select pulse_private.call_push_jobs()$$;
create function public.pulse_call_push_finish(p_call uuid,p_user uuid,p_done boolean)returns void language sql security invoker set search_path=''as $$select pulse_private.call_push_finish(p_call,p_user,p_done)$$;
revoke all on function pulse_private.call_push_jobs(),public.pulse_call_push_jobs(),pulse_private.call_push_finish(uuid,uuid,boolean),public.pulse_call_push_finish(uuid,uuid,boolean)from public,anon,authenticated;
grant execute on function pulse_private.call_push_jobs(),public.pulse_call_push_jobs(),pulse_private.call_push_finish(uuid,uuid,boolean),public.pulse_call_push_finish(uuid,uuid,boolean)to service_role;
commit;
