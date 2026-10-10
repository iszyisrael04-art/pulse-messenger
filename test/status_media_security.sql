begin;
create temporary table pulse_status_test(k text primary key,id uuid default gen_random_uuid());
insert into pulse_status_test(k) values('owner'),('viewer'),('outsider'),('chat'),('status');
grant select,update on pulse_status_test to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at)
select id,'authenticated','authenticated','pulse-status-'||id::text||'@example.invalid',now()
from pulse_status_test where k in ('owner','viewer','outsider');
insert into storage.objects(bucket_id,name,metadata)
select 'pulse-status-media',id::text||'/fixture.mp4','{"mimetype":"video/mp4","size":100}'::jsonb from pulse_status_test where k='owner';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_status_test where k='owner'),'role','authenticated')::text,true);
set local role authenticated;
update pulse_status_test set id=public.pulse_start_chat(array[(select id from pulse_status_test where k='viewer')],'Status fixture',false) where k='chat';
select public.pulse_post_media_status((select id from pulse_status_test where k='status'),'',(select id::text||'/fixture.mp4' from pulse_status_test where k='owner'),'video');
select public.pulse_post_media_status((select id from pulse_status_test where k='status'),'',(select id::text||'/fixture.mp4' from pulse_status_test where k='owner'),'video');
do $$ begin
 if (select count(*) from public.pulse_statuses where id=(select id from pulse_status_test where k='status'))<>1 then raise exception 'FAIL: status duplication'; end if;
 begin perform public.pulse_post_media_status(gen_random_uuid(),'',(select id::text||'/fixture.mp4' from pulse_status_test where k='owner'),'image'); raise exception 'FAIL: mismatched MIME accepted'; exception when others then if sqlerrm='FAIL: mismatched MIME accepted' then raise; end if; end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_status_test where k='outsider'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.pulse_statuses where id=(select id from pulse_status_test where k='status')) then raise exception 'FAIL: outsider status visible'; end if;
 if pulse_private.can_read_status_media((select id::text||'/fixture.mp4' from pulse_status_test where k='owner')) then raise exception 'FAIL: outsider storage access'; end if;
 if exists(select 1 from storage.objects where bucket_id='pulse-status-media' and name=(select id::text||'/fixture.mp4' from pulse_status_test where k='owner')) then raise exception 'FAIL: outsider storage policy'; end if;
 begin perform public.pulse_post_media_status(gen_random_uuid(),'Forged',(select id::text||'/fixture.mp4' from pulse_status_test where k='owner'),'video'); raise exception 'FAIL: forged owner accepted'; exception when others then if sqlerrm='FAIL: forged owner accepted' then raise; end if; end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_status_test where k='viewer'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if not exists(select 1 from public.pulse_statuses where id=(select id from pulse_status_test where k='status')) then raise exception 'FAIL: shared contact cannot see status'; end if;
 if not pulse_private.can_read_status_media((select id::text||'/fixture.mp4' from pulse_status_test where k='owner')) then raise exception 'FAIL: shared contact cannot see media'; end if;
 begin perform public.pulse_delete_status((select id from pulse_status_test where k='status')); raise exception 'FAIL: viewer deleted status'; exception when others then if sqlerrm='FAIL: viewer deleted status' then raise; end if; end;
end $$;
reset role;
insert into public.pulse_blocks(user_id,blocked_id) select a.id,b.id from pulse_status_test a,pulse_status_test b where a.k='owner' and b.k='viewer';
set local role authenticated;
do $$ begin
 if pulse_private.can_read_status_media((select id::text||'/fixture.mp4' from pulse_status_test where k='owner')) then raise exception 'FAIL: blocked contact media'; end if;
end $$;
reset role;
delete from public.pulse_blocks where user_id=(select id from pulse_status_test where k='owner');
update public.pulse_statuses set expires_at=now()-interval '1 second' where id=(select id from pulse_status_test where k='status');
set local role authenticated;
do $$ begin
 if exists(select 1 from public.pulse_statuses where id=(select id from pulse_status_test where k='status')) then raise exception 'FAIL: expired status visible'; end if;
 if pulse_private.can_read_status_media((select id::text||'/fixture.mp4' from pulse_status_test where k='owner')) then raise exception 'FAIL: expired media accessible'; end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_status_test where k='owner'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_delete_status((select id from pulse_status_test where k='status'));
reset role;
do $$ begin
 if exists(select 1 from public.pulse_statuses where id=(select id from pulse_status_test where k='status')) then raise exception 'FAIL: owner deletion'; end if;
end $$;
select 'PASS: media type, retry safety, ownership, contact access, blocking, expiration and deletion' as result;
rollback;
