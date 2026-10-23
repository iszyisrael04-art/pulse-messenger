begin;
create temporary table composer_fixture(k text primary key,id uuid default gen_random_uuid());
insert into composer_fixture(k) values('author'),('viewer'),('draft'),('video');
grant select on composer_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at) select id,'authenticated','authenticated','compose-test-'||id||'@example.invalid',now() from composer_fixture where k in('author','viewer');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from composer_fixture where k='author'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_social_write_options((select id from composer_fixture where k='draft'),'post','Draft caption','[]','private',true,false);
do $$begin
 if (public.pulse_social_post((select id from composer_fixture where k='draft'))->>'allow_download')::boolean then raise exception 'FAIL: download preference not saved';end if;
end $$;
select public.pulse_social_write_options((select id from composer_fixture where k='draft'),'post','Published caption','[]','public',false,false);
select public.pulse_social_write_options((select id from composer_fixture where k='draft'),'post','Retry caption','[]','public',false,true);
do $$begin
 if (public.pulse_social_post((select id from composer_fixture where k='draft'))->>'allow_download')::boolean then raise exception 'FAIL: retry overwrote published preference';end if;
end $$;
reset role;
insert into public.pulse_social_content(id,author_id,kind,body,media,state,audience,allow_download)
 select v.id,a.id,'reel','No downloads','[{"kind":"video","path":"fixture.mp4"}]'::jsonb,'published','public',false from composer_fixture v cross join composer_fixture a where v.k='video' and a.k='author';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from composer_fixture where k='viewer'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 if public.pulse_social_post((select id from composer_fixture where k='video')) is null then raise exception 'FAIL: playback visibility lost';end if;
 begin perform public.pulse_social_export_post((select id from composer_fixture where k='video'));raise exception 'FAIL: restricted video export';exception when others then if sqlerrm='FAIL: restricted video export' then raise;end if;end;
 begin perform public.pulse_social_write_options((select id from composer_fixture where k='video'),'reel','','[]','public',false,true);raise exception 'FAIL: foreign preference changed';exception when others then if sqlerrm='FAIL: foreign preference changed' then raise;end if;end;
 if public.pulse_social_export_post((select id from composer_fixture where k='draft')) is null then raise exception 'FAIL: text-only export lost';end if;
 if has_function_privilege('anon','public.pulse_social_export_post(uuid)','EXECUTE') then raise exception 'FAIL: anonymous export';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from composer_fixture where k='author'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin if public.pulse_social_export_post((select id from composer_fixture where k='video')) is null then raise exception 'FAIL: owner export';end if;end $$;
reset role;
rollback;
