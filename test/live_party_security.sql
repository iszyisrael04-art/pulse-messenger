begin;
create temporary table party_fixture(k text primary key,id uuid default gen_random_uuid());
insert into party_fixture(k) values('host'),('outsider'),('channel'),('live');
insert into party_fixture(k) select 'guest'||i from generate_series(1,9)i;
grant select,update on party_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at) select id,'authenticated','authenticated','party-'||id||'@example.invalid',now() from party_fixture where k='host' or k='outsider' or k like 'guest%';
update pulse_private.live_policy set min_followers=0;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from party_fixture where k='host'),'role','authenticated')::text,true);
set local role authenticated;
update party_fixture set id=public.pulse_create_channel('Party fixture','Test') where k='channel';
update party_fixture set id=public.pulse_live_start((select id from party_fixture where k='channel'),'Party') where k='live';
reset role;
insert into public.pulse_followers select c.id,g.id from party_fixture c,party_fixture g where c.k='channel' and g.k like 'guest%';
-- Request nine seats with nine authenticated followers.
do $$ declare guest record;begin
 for guest in select id from party_fixture where k like 'guest%' loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',guest.id,'role','authenticated')::text,true);
  perform public.pulse_live_party('request',(select id from party_fixture where k='live'),null,'audio');
 end loop;
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from party_fixture where k='guest1'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if (public.pulse_live_party('access',(select id from party_fixture where k='live'))->>'publish')::boolean then raise exception 'FAIL: pending guest publish';end if;
 begin perform public.pulse_live_party('approve',(select id from party_fixture where k='live'),auth.uid());raise exception 'FAIL: self approved';exception when others then if sqlerrm='FAIL: self approved' then raise;end if;end;
 if jsonb_array_length(public.pulse_live_party('info',(select id from party_fixture where k='live'))->'requests')<>0 then raise exception 'FAIL: private request list leak';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from party_fixture where k='host'),'role','authenticated')::text,true);
set local role authenticated;
do $$ declare guest record;begin
 for guest in select id from party_fixture where k in('guest1','guest2','guest3','guest4','guest5','guest6','guest7','guest8') loop perform public.pulse_live_party('approve',(select id from party_fixture where k='live'),guest.id);end loop;
 begin perform public.pulse_live_party('approve',(select id from party_fixture where k='live'),(select id from party_fixture where k='guest9'));raise exception 'FAIL: exceeded eight guests';exception when others then if sqlerrm='FAIL: exceeded eight guests' then raise;end if;end;
 if jsonb_array_length(public.pulse_live_party('info',(select id from party_fixture where k='live'))->'members')<>8 then raise exception 'FAIL: stage member count';end if;
end $$;
select public.pulse_live_party('remove',(select id from party_fixture where k='live'),(select id from party_fixture where k='guest8'));
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from party_fixture where k='guest8'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin if (public.pulse_live_party('access',(select id from party_fixture where k='live'))->>'publish')::boolean then raise exception 'FAIL: removed guest publish';end if;end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from party_fixture where k='guest1'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if (public.pulse_live_party('access',(select id from party_fixture where k='live'))->>'publish')::boolean is not true then raise exception 'FAIL: approved guest denied';end if;
end $$;
select public.pulse_live_party('leave',(select id from party_fixture where k='live'));
do $$ begin if (public.pulse_live_party('access',(select id from party_fixture where k='live'))->>'publish')::boolean then raise exception 'FAIL: departed guest publish';end if;end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from party_fixture where k='outsider'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 begin perform public.pulse_live_party('request',(select id from party_fixture where k='live'));raise exception 'FAIL: nonfollower requested';exception when others then if sqlerrm='FAIL: nonfollower requested' then raise;end if;end;
end $$;
reset role;
rollback;
