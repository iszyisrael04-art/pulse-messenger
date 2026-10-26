begin;
create temporary table moderation_fixture(k text primary key,id uuid default gen_random_uuid());
insert into moderation_fixture(k) values('staff'),('leader'),('admin'),('fan'),('channel'),('post'),('other');
grant select on moderation_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at,raw_user_meta_data)
 select id,'authenticated','authenticated',id||'@example.invalid',now(),'{"admin":true}'
 from moderation_fixture where k in ('staff','leader','admin','fan');
insert into pulse_private.admins select id from moderation_fixture where k='staff';
insert into public.pulse_channels(id,owner_id,name)
 select c.id,u.id,'Moderation fixture' from moderation_fixture c,moderation_fixture u
 where c.k in ('channel','other') and u.k='leader';
insert into public.pulse_channel_admins(channel_id,user_id)
 select c.id,u.id from moderation_fixture c,moderation_fixture u where c.k='channel' and u.k='admin';
insert into public.pulse_posts(id,channel_id,author_id,body)
 select p.id,c.id,u.id,'Preserve history' from moderation_fixture p,moderation_fixture c,moderation_fixture u
 where p.k='post' and c.k='channel' and u.k='leader';
insert into public.pulse_followers(channel_id,user_id)
 select c.id,u.id from moderation_fixture c,moderation_fixture u where c.k='channel' and u.k='fan';

-- Followers and channel leaders cannot grant themselves platform moderation.
set local role authenticated;
do $$declare actor uuid; action text;begin
 for actor in select id from moderation_fixture where k in ('leader','admin','fan') loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  foreach action in array array['list','ban','suspend','release'] loop
   begin
    perform public.pulse_channel_moderation(action,(select id from moderation_fixture where k='channel'),'{"reason":"Fixture reason","days":2}');
    raise exception 'FAIL non-staff moderation';
   exception when insufficient_privilege then null;end;
  end loop;
 end loop;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from moderation_fixture where k='fan'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 begin
  perform public.pulse_channel_delete((select id from moderation_fixture where k='channel'));
  raise exception 'FAIL fan deleted channel';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
-- Staff who do not manage the channel cannot use its deletion endpoint.
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from moderation_fixture where k='staff'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 begin
  perform public.pulse_channel_delete((select id from moderation_fixture where k='channel'));
  raise exception 'FAIL unrelated staff deleted channel';
 exception when insufficient_privilege then null;end;
end $$;
select public.pulse_channel_moderation('suspend',(select id from moderation_fixture where k='channel'),'{"reason":"Fixture suspension","days":2}');
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from moderation_fixture where k='leader'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 if exists(select 1 from public.pulse_channels where id=(select id from moderation_fixture where k='channel'))
 or exists(select 1 from public.pulse_posts where id=(select id from moderation_fixture where k='post')) then
  raise exception 'FAIL suspended content visible';end if;
 begin
  perform public.pulse_channel_post((select id from moderation_fixture where k='channel'),'Evade suspension');
  raise exception 'FAIL suspended post';
 exception when insufficient_privilege then null;end;
 begin
  perform public.pulse_channel_summary((select id from moderation_fixture where k='channel'));
  raise exception 'FAIL summary bypass';
 exception when others then if sqlerrm<>'Channel unavailable' then raise;end if;end;
 begin
  perform public.pulse_channel_update((select id from moderation_fixture where k='channel'),'Evade','',null);
  raise exception 'FAIL suspended edit';
 exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from moderation_fixture where k='fan'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 begin
  perform public.pulse_follow_channel((select id from moderation_fixture where k='channel'),true);
  raise exception 'FAIL suspended follow';
 exception when insufficient_privilege then null;end;
 begin
  perform public.pulse_post_react((select id from moderation_fixture where k='post'),'like');
  raise exception 'FAIL suspended reaction';
 exception when insufficient_privilege then null;end;
 begin
  perform public.pulse_channel_responses((select id from moderation_fixture where k='post'),'list');
  raise exception 'FAIL suspended responses';
 exception when others then if sqlerrm<>'Channel unavailable' then raise;end if;end;
end $$;
reset role;
-- Suspension expires automatically and keeps all content.
update pulse_private.channel_limits set until_at=now()-interval '1 second' where channel_id=(select id from moderation_fixture where k='channel');
set local role authenticated;
do $$begin
 if not exists(select 1 from public.pulse_posts where id=(select id from moderation_fixture where k='post')) then raise exception 'FAIL expiry did not restore history';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from moderation_fixture where k='staff'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_channel_moderation('ban',(select id from moderation_fixture where k='channel'),'{"reason":"Fixture ban"}');
select public.pulse_channel_moderation('release',(select id from moderation_fixture where k='channel'));
reset role;
-- An appointed administrator can delete their own channel, but not another channel.
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from moderation_fixture where k='admin'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 begin
  perform public.pulse_channel_delete((select id from moderation_fixture where k='other'));
  raise exception 'FAIL admin deleted unrelated channel';
 exception when insufficient_privilege then null;end;
end $$;
select public.pulse_channel_delete((select id from moderation_fixture where k='channel'));
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from moderation_fixture where k='leader'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_channel_delete((select id from moderation_fixture where k='other'));
reset role;
do $$begin
 if exists(select 1 from public.pulse_channels where id in(select id from moderation_fixture where k in ('channel','other')))
 or exists(select 1 from public.pulse_posts where id=(select id from moderation_fixture where k='post'))
 or exists(select 1 from public.pulse_followers where channel_id=(select id from moderation_fixture where k='channel')) then raise exception 'FAIL delete cascade';end if;
 if (select count(*) from pulse_private.control_audit where action='delete_channel' and staff_id in(select id from moderation_fixture where k in('admin','leader')))<>2 then raise exception 'FAIL deletion audit';end if;
 if has_function_privilege('anon','public.pulse_channel_moderation(text,uuid,jsonb)','execute') then raise exception 'FAIL anonymous moderation';end if;
end $$;
rollback;
