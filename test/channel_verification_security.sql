-- Disposable records; all changes roll back, including audit/mail side effects.
begin;
create temporary table channel_verify_fixture(k text primary key,id uuid default gen_random_uuid());
insert into channel_verify_fixture(k) values('staff'),('owner'),('channel');
grant select on channel_verify_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_user_meta_data)
select id,'authenticated','authenticated','verify-'||id||'@example.invalid',now(),'{"admin":true}'
from channel_verify_fixture where k in('staff','owner');
insert into pulse_private.admins(user_id) select id from channel_verify_fixture where k='staff';
insert into public.pulse_channels(id,owner_id,name)
select c.id,o.id,'Channel verification fixture' from channel_verify_fixture c,channel_verify_fixture o where c.k='channel' and o.k='owner';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from channel_verify_fixture where k='owner'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 begin
  perform public.pulse_admin_action('verify_channel',jsonb_build_object('id',(select id from channel_verify_fixture where k='channel'),'verified',true));
  raise exception 'FAIL: channel owner self verified';
 exception when others then if sqlerrm='FAIL: channel owner self verified' then raise;end if;end;
 if exists(select 1 from public.pulse_channels where id=(select id from channel_verify_fixture where k='channel') and verified) then raise exception 'FAIL: forged verification';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from channel_verify_fixture where k='staff'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_admin_action('verify_channel',jsonb_build_object('id',(select id from channel_verify_fixture where k='channel'),'verified',true));
do $$ begin
 if not exists(select 1 from public.pulse_channels where id=(select id from channel_verify_fixture where k='channel') and verified) then raise exception 'FAIL: staff verification';end if;
end $$;
select public.pulse_admin_action('verify_channel',jsonb_build_object('id',(select id from channel_verify_fixture where k='channel'),'verified',false));
do $$ begin
 if exists(select 1 from public.pulse_channels where id=(select id from channel_verify_fixture where k='channel') and verified) then raise exception 'FAIL: staff unverification';end if;
end $$;
reset role;
rollback;
