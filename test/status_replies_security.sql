begin;
create temporary table status_fixture(k text primary key,id uuid default gen_random_uuid());
insert into status_fixture(k) values('owner'),('viewer'),('stranger'),('group'),('status'),('reply'),('expired'),('post');
grant select,update on status_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at) select id,'authenticated','authenticated','status-'||id||'@example.invalid',now() from status_fixture where k in('owner','viewer','stranger');
insert into public.pulse_chats(id,kind,name,owner_id) select g.id,'group','Status fixture',o.id from status_fixture g,status_fixture o where g.k='group' and o.k='owner';
insert into public.pulse_members(chat_id,user_id) select g.id,u.id from status_fixture g,status_fixture u where g.k='group' and u.k in('owner','viewer');
insert into public.pulse_statuses(id,user_id,body,expires_at) select s.id,o.id,'Fixture status',case when s.k='expired' then now()-interval '1 second' else now()+interval '1 hour' end from status_fixture s,status_fixture o where s.k in('status','expired') and o.k='owner';
do $$begin
 if (select file_size_limit from storage.buckets where id='pulse-avatars')<>15728640 then raise exception 'FAIL: avatar limit';end if;
 if has_function_privilege('anon','public.pulse_reply_status(uuid,uuid,text)','execute') then raise exception 'FAIL: anonymous reply';end if;
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from status_fixture where k='stranger'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 begin perform public.pulse_reply_status(gen_random_uuid(),(select id from status_fixture where k='status'),'Hello');raise exception 'FAIL: stranger replied';exception when others then if sqlerrm='FAIL: stranger replied' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from status_fixture where k='viewer'),'role','authenticated')::text,true);
set local role authenticated;
do $$declare chat uuid;again uuid;begin
 chat=public.pulse_reply_status((select id from status_fixture where k='reply'),(select id from status_fixture where k='status'),'Great update');
 again=public.pulse_reply_status((select id from status_fixture where k='reply'),(select id from status_fixture where k='status'),'Retry');
 if chat<>again or (select count(*) from public.pulse_messages where id=(select id from status_fixture where k='reply'))<>1 then raise exception 'FAIL: duplicate status reply';end if;
 if not exists(select 1 from public.pulse_messages where id=(select id from status_fixture where k='reply') and status_id=(select id from status_fixture where k='status') and body='Great update') then raise exception 'FAIL: status link';end if;
 if not exists(select 1 from public.pulse_chat_requests where chat_id=chat and state='pending' and recipient_id=(select id from status_fixture where k='owner')) then raise exception 'FAIL: reply bypassed message request';end if;
 begin perform public.pulse_reply_status(gen_random_uuid(),(select id from status_fixture where k='expired'),'Expired');raise exception 'FAIL: expired reply';exception when others then if sqlerrm='FAIL: expired reply' then raise;end if;end;
end $$;
reset role;
-- Original status author cannot bypass pending request by replying to the sender's status.
insert into public.pulse_statuses(user_id,body) select id,'Viewer status' from status_fixture where k='viewer';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from status_fixture where k='owner'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 begin perform public.pulse_reply_status(gen_random_uuid(),(select id from public.pulse_statuses where user_id=(select id from status_fixture where k='viewer') limit 1),'Back');raise exception 'FAIL: request consent bypass';exception when others then if sqlerrm='FAIL: request consent bypass' then raise;end if;end;
end $$;
reset role;
insert into public.pulse_blocks(user_id,blocked_id) select o.id,v.id from status_fixture o,status_fixture v where o.k='owner' and v.k='viewer';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from status_fixture where k='viewer'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 begin perform public.pulse_reply_status(gen_random_uuid(),(select id from status_fixture where k='status'),'Blocked');raise exception 'FAIL: blocked reply';exception when others then if sqlerrm='FAIL: blocked reply' then raise;end if;end;
end $$;
reset role;
-- Removing a status leaves the private message intact and its link unavailable.
delete from public.pulse_statuses where id=(select id from status_fixture where k='status');
do $$begin if not exists(select 1 from public.pulse_messages where id=(select id from status_fixture where k='reply')) then raise exception 'FAIL: expired status removed message';end if;end $$;
insert into storage.objects(bucket_id,name,metadata) select 'pulse-social',u.id::text||'/'||p.id::text||'/'||n||'.jpg','{"mimetype":"image/jpeg","size":1024}' from status_fixture u,status_fixture p,generate_series(1,12) n where u.k='viewer' and p.k='post';
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from status_fixture where k='viewer'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_social_write((select id from status_fixture where k='post'),'post','Twelve pictures',(select jsonb_agg(jsonb_build_object('kind','image','path',auth.uid()::text||'/'||p.id::text||'/'||n||'.jpg','mime','image/jpeg')) from status_fixture p,generate_series(1,12) n where p.k='post'),'public',false);
do $$begin if (select jsonb_array_length(media) from public.pulse_social_content where id=(select id from status_fixture where k='post'))<>12 then raise exception 'FAIL: old eight-picture cap';end if;end $$;
reset role;
rollback;
