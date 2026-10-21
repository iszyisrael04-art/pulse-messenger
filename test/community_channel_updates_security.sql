begin;
create temporary table upgrade_fixture(k text primary key,id uuid default gen_random_uuid());
insert into upgrade_fixture(k) values('staff'),('owner'),('fan'),('outsider'),('group'),('channel'),('post');
grant select,update on upgrade_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_user_meta_data) select id,'authenticated','authenticated','upgrade-'||id||'@example.invalid',now(),'{"admin":true}' from upgrade_fixture where k in('staff','owner','fan','outsider');
insert into pulse_private.admins(user_id) select id from upgrade_fixture where k='staff';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from upgrade_fixture where k='owner'),'role','authenticated')::text,true);
set local role authenticated;
update upgrade_fixture set id=(public.pulse_communities('create',null,null,jsonb_build_object('name','Verified fixture','handle','verify_'||left(id::text,8)))#>>'{}')::uuid where k='group';
update upgrade_fixture set id=public.pulse_create_channel('Update fixture','Test') where k='channel';
do $$ begin
 begin perform public.pulse_community_verification('set',(select id from upgrade_fixture where k='group'),true);raise exception 'FAIL: owner self verified community';exception when others then if sqlerrm='FAIL: owner self verified community' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from upgrade_fixture where k='staff'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_community_verification('set',(select id from upgrade_fixture where k='group'),true);
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from upgrade_fixture where k='fan'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if (public.pulse_communities('list',(select id from upgrade_fixture where k='group'))->0->>'verified')::boolean is not true then raise exception 'FAIL: community badge missing';end if;
end $$;
select public.pulse_follow_channel((select id from upgrade_fixture where k='channel'),true);
select public.pulse_channel_updates();
reset role;
-- Advance the baseline backward only for this transaction, so WASM clocks are deterministic.
update pulse_private.channel_reads set seen_until=clock_timestamp()-interval '1 minute' where user_id=(select id from upgrade_fixture where k='fan');
insert into public.pulse_posts(id,channel_id,author_id,body,created_at) select p.id,c.id,o.id,'Admin announcement',clock_timestamp() from upgrade_fixture p,upgrade_fixture c,upgrade_fixture o where p.k='post' and c.k='channel' and o.k='owner';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from upgrade_fixture where k='fan'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if (public.pulse_channel_updates()->>'total')::int<>1 then raise exception 'FAIL: followed announcement unread';end if;
end $$;
select public.pulse_channel_updates('read',(select id from upgrade_fixture where k='channel'),(select id from upgrade_fixture where k='post'));
do $$ begin if (public.pulse_channel_updates()->>'total')::int<>0 then raise exception 'FAIL: read count not cleared';end if;end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from upgrade_fixture where k='outsider'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if (public.pulse_channel_updates()->>'total')::int<>0 then raise exception 'FAIL: outsider channel notification';end if;
 begin perform public.pulse_channel_updates('read',(select id from upgrade_fixture where k='channel'));raise exception 'FAIL: outsider marked read';exception when others then if sqlerrm='FAIL: outsider marked read' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from upgrade_fixture where k='fan'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_follow_channel((select id from upgrade_fixture where k='channel'),false);
select public.pulse_follow_channel((select id from upgrade_fixture where k='channel'),true);
do $$ begin if (public.pulse_channel_updates()->>'total')::int<>0 then raise exception 'FAIL: old post replay on refollow';end if;end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from upgrade_fixture where k='staff'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_community_verification('set',(select id from upgrade_fixture where k='group'),false);
reset role;
rollback;
