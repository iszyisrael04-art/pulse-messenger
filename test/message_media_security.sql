begin;
create temporary table pulse_media_test(k text primary key,id uuid default gen_random_uuid());
insert into pulse_media_test(k) values('owner'),('peer'),('outsider'),('chat'),('message');
grant select,update on pulse_media_test to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at)
select id,'authenticated','authenticated','pulse-media-'||id::text||'@example.invalid',now() from pulse_media_test where k in ('owner','peer','outsider');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_media_test where k='owner'),'role','authenticated')::text,true);
set local role authenticated;
update pulse_media_test set id=public.pulse_start_chat(array[(select id from pulse_media_test where k='peer')],'Media fixture',false) where k='chat';
reset role;
insert into storage.objects(bucket_id,name,metadata) select 'pulse-media',c.id::text||'/'||u.id::text||'/voice.m4a','{"mimetype":"audio/mp4","size":100}'::jsonb from pulse_media_test c,pulse_media_test u where c.k='chat' and u.k='owner';
set local role authenticated;
select public.pulse_send_media_message((select id from pulse_media_test where k='message'),(select id from pulse_media_test where k='chat'),'',null,
 (select c.id::text||'/'||u.id::text||'/voice.m4a' from pulse_media_test c,pulse_media_test u where c.k='chat' and u.k='owner'),'audio','audio/mp4',1500,'[0.1,0.8]'::jsonb);
select public.pulse_send_media_message((select id from pulse_media_test where k='message'),(select id from pulse_media_test where k='chat'),'',null,
 (select c.id::text||'/'||u.id::text||'/voice.m4a' from pulse_media_test c,pulse_media_test u where c.k='chat' and u.k='owner'),'audio','audio/mp4',1500,'[0.1,0.8]'::jsonb);
do $$ declare path text; chat uuid; begin
 select id into chat from pulse_media_test where k='chat';
 select chat::text||'/'||id::text||'/voice.m4a' into path from pulse_media_test where k='owner';
 if (select count(*) from public.pulse_messages where id=(select id from pulse_media_test where k='message'))<>1 then raise exception 'FAIL: duplicate media retry'; end if;
 if (select waveform from public.pulse_messages where id=(select id from pulse_media_test where k='message'))<>'[0.1,0.8]'::jsonb then raise exception 'FAIL: waveform'; end if;
 begin perform public.pulse_send_media_message(gen_random_uuid(),chat,'',null,path,'image','audio/mp4',null,null); raise exception 'FAIL: image MIME'; exception when others then if sqlerrm='FAIL: image MIME' then raise; end if; end;
 begin perform public.pulse_send_media_message(gen_random_uuid(),chat,'',null,path,'audio','audio/mp4',1500,'[2]'::jsonb); raise exception 'FAIL: waveform range'; exception when others then if sqlerrm='FAIL: waveform range' then raise; end if; end;
 begin perform public.pulse_send_media_message(gen_random_uuid(),chat,'',null,path,'audio','audio/mp4',300001,null); raise exception 'FAIL: duration limit'; exception when others then if sqlerrm='FAIL: duration limit' then raise; end if; end;
 begin perform public.pulse_send_media_message(gen_random_uuid(),chat,'',null,path,'audio','audio/ogg',1500,null); raise exception 'FAIL: MIME mismatch'; exception when others then if sqlerrm='FAIL: MIME mismatch' then raise; end if; end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_media_test where k='peer'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if not exists(select 1 from public.pulse_messages where id=(select id from pulse_media_test where k='message') and media_kind='audio') then raise exception 'FAIL: peer read'; end if;
 begin perform public.pulse_send_media_message(gen_random_uuid(),(select id from pulse_media_test where k='chat'),'',null,(select c.id::text||'/'||u.id::text||'/voice.m4a' from pulse_media_test c,pulse_media_test u where c.k='chat' and u.k='owner'),'audio','audio/mp4',1500,null); raise exception 'FAIL: foreign upload'; exception when others then if sqlerrm='FAIL: foreign upload' then raise; end if; end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from pulse_media_test where k='outsider'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if exists(select 1 from public.pulse_messages where id=(select id from pulse_media_test where k='message')) then raise exception 'FAIL: outsider read'; end if;
 begin perform public.pulse_send_media_message(gen_random_uuid(),(select id from pulse_media_test where k='chat'),'',null,'forged','audio','audio/mp4',1500,null); raise exception 'FAIL: outsider send'; exception when others then if sqlerrm='FAIL: outsider send' then raise; end if; end;
end $$;
reset role;
select 'PASS: media authorization, retry safety, storage ownership, MIME, duration and waveform validation' as result;
rollback;
