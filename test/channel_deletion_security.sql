begin;
create temporary table deletion_fixture(k text primary key,id uuid default gen_random_uuid());
insert into deletion_fixture(k) values('staff'),('leader'),('channel_admin'),('fan'),('channel'),('post');
grant select on deletion_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_user_meta_data)
 select id,'authenticated','authenticated',id||'@example.invalid',now(),'{"admin":true}'
 from deletion_fixture where k in ('staff','leader','channel_admin','fan');
insert into pulse_private.admins(user_id) select id from deletion_fixture where k='staff';
insert into public.pulse_channels(id,owner_id,name)
 select c.id,u.id,'Deletion test' from deletion_fixture c,deletion_fixture u where c.k='channel' and u.k='leader';
insert into public.pulse_channel_admins(channel_id,user_id)
 select c.id,u.id from deletion_fixture c,deletion_fixture u where c.k='channel' and u.k='channel_admin';
insert into public.pulse_followers(channel_id,user_id)
 select c.id,u.id from deletion_fixture c,deletion_fixture u where c.k='channel' and u.k='fan';
insert into public.pulse_posts(id,channel_id,author_id,body)
 select p.id,c.id,u.id,'Fixture post' from deletion_fixture p,deletion_fixture c,deletion_fixture u
 where p.k='post' and c.k='channel' and u.k='leader';
set local role authenticated;
do $$
declare actor uuid;
begin
 for actor in select id from deletion_fixture where k in ('leader','channel_admin','fan') loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  begin
   perform public.pulse_channel_delete((select id from deletion_fixture where k='channel'));
   raise exception 'FAIL non-staff deleted channel';
  exception when insufficient_privilege then null; end;
  begin
   delete from public.pulse_channels where id=(select id from deletion_fixture where k='channel');
   raise exception 'FAIL direct delete permission';
  exception when insufficient_privilege then null; end;
 end loop;
end $$;
reset role;
do $$begin
 if not exists(select 1 from public.pulse_channels where id=(select id from deletion_fixture where k='channel')) then
  raise exception 'FAIL denied request removed channel'; end if;
 if has_function_privilege('anon','public.pulse_channel_delete(uuid)','execute') then
  raise exception 'FAIL anonymous delete endpoint'; end if;
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from deletion_fixture where k='staff'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_channel_delete((select id from deletion_fixture where k='channel'));
reset role;
do $$begin
 if exists(select 1 from public.pulse_channels where id=(select id from deletion_fixture where k='channel'))
 or exists(select 1 from public.pulse_posts where id=(select id from deletion_fixture where k='post'))
 or exists(select 1 from public.pulse_followers where channel_id=(select id from deletion_fixture where k='channel'))
 or exists(select 1 from public.pulse_channel_admins where channel_id=(select id from deletion_fixture where k='channel')) then
  raise exception 'FAIL deletion did not cascade'; end if;
 if not exists(select 1 from pulse_private.control_audit where staff_id=(select id from deletion_fixture where k='staff')
 and action='delete_channel' and detail->>'channel_id'=(select id::text from deletion_fixture where k='channel')) then
  raise exception 'FAIL deletion audit missing'; end if;
end $$;
-- Restricted staff cannot delete even with a stale authenticated token.
insert into public.pulse_channels(id,owner_id,name)
 select c.id,u.id,'Restricted staff test' from deletion_fixture c,deletion_fixture u where c.k='channel' and u.k='leader';
insert into pulse_private.account_limits(user_id,state,reason)
 select id,'banned','Fixture restriction' from deletion_fixture where k='staff';
set local role authenticated;
do $$begin
 begin
  perform public.pulse_channel_delete((select id from deletion_fixture where k='channel'));
  raise exception 'FAIL banned staff deleted channel';
 exception when others then if sqlerrm='FAIL banned staff deleted channel' then raise; end if; end;
end $$;
reset role;
do $$begin
 if not exists(select 1 from public.pulse_channels where id=(select id from deletion_fixture where k='channel')) then
  raise exception 'FAIL restricted staff removed channel'; end if;
end $$;
rollback;
