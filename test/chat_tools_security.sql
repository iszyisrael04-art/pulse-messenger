begin;
create temporary table tool_fixture(k text primary key,id uuid default gen_random_uuid());
insert into tool_fixture(k) values('a'),('b'),('c'),('chat'),('reply'),('message'),('second');
grant select,update on tool_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at) select id,'authenticated','authenticated','pulse-tools-'||id||'@example.invalid',now() from tool_fixture where k in ('a','b','c');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from tool_fixture where k='a'),'role','authenticated')::text,true);
set local role authenticated;
update tool_fixture set id=public.pulse_start_chat(array[(select id from tool_fixture where k='b')],'Tools fixture',false) where k='chat';
select public.pulse_user_tools('note_save',p_chat=>(select id from tool_fixture where k='chat'),p_text=>'My private plan');
do $$begin
 if public.pulse_user_tools('note_get',p_chat=>(select id from tool_fixture where k='chat'))->>'body' is distinct from 'My private plan' then raise exception 'FAIL: own note';end if;
 begin perform public.pulse_user_tools('quick_save',p_label=>'Test',p_text=>'Free bypass');raise exception 'FAIL: free quick reply';exception when others then if sqlerrm='FAIL: free quick reply' then raise;end if;end;
 begin perform public.pulse_user_tools('style_save',p_chat=>(select id from tool_fixture where k='chat'),p_label=>'aurora');raise exception 'FAIL: free style';exception when others then if sqlerrm='FAIL: free style' then raise;end if;end;
end$$;
reset role;
insert into public.pulse_premium(user_id,expires_at) select id,now()+interval '1 day' from tool_fixture where k in ('a','b');
set local role authenticated;
select public.pulse_user_tools('quick_save',p_id=>(select id from tool_fixture where k='reply'),p_label=>'Greeting',p_text=>'Hello from my library');
select public.pulse_user_tools('style_save',p_chat=>(select id from tool_fixture where k='chat'),p_label=>'aurora');
select public.pulse_send_message((select id from tool_fixture where k='message'),(select id from tool_fixture where k='chat'),'Unread fixture',null,null);
select public.pulse_send_message((select id from tool_fixture where k='second'),(select id from tool_fixture where k='chat'),'Hide fixture',null,null);
do $$begin
 if public.pulse_user_tools('quick_use',p_id=>(select id from tool_fixture where k='reply'))->>'body' is distinct from 'Hello from my library' then raise exception 'FAIL: paid reply';end if;
 if public.pulse_user_tools('style_get',p_chat=>(select id from tool_fixture where k='chat'))->>'style' is distinct from 'aurora' then raise exception 'FAIL: paid style';end if;
 if public.pulse_unread_preview((select id from tool_fixture where k='message')) is not null then raise exception 'FAIL: own notification';end if;
end$$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from tool_fixture where k='b'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 if public.pulse_user_tools('note_get',p_chat=>(select id from tool_fixture where k='chat'))->>'body' is distinct from '' then raise exception 'FAIL: peer note leaked';end if;
 if jsonb_array_length(public.pulse_user_tools('quick_list')->'items')<>0 then raise exception 'FAIL: peer quick replies leaked';end if;
 begin perform public.pulse_user_tools('quick_use',p_id=>(select id from tool_fixture where k='reply'));raise exception 'FAIL: peer used reply';exception when others then if sqlerrm='FAIL: peer used reply' then raise;end if;end;
 begin perform public.pulse_user_tools('quick_save',p_id=>(select id from tool_fixture where k='reply'),p_label=>'Hijack',p_text=>'Changed');raise exception 'FAIL: peer overwrote reply';exception when others then if sqlerrm='FAIL: peer overwrote reply' then raise;end if;end;
 if (public.pulse_unread_preview((select id from tool_fixture where k='message'))->>'unread_count')::int is distinct from 2 then raise exception 'FAIL: unread notification count';end if;
end$$;
select public.pulse_message_pref((select id from tool_fixture where k='second'),true,false);
do $$begin
 if public.pulse_unread_preview((select id from tool_fixture where k='second')) is not null then raise exception 'FAIL: hidden message notification';end if;
 if (public.pulse_unread_counts()->>(select id::text from tool_fixture where k='chat'))::int is distinct from 1 then raise exception 'FAIL: hidden unread count';end if;
end$$;
select public.pulse_block_user((select id from tool_fixture where k='a'),true);
do $$begin
 if public.pulse_unread_preview((select id from tool_fixture where k='message')) is not null then raise exception 'FAIL: blocked notification';end if;
 if public.pulse_unread_counts() ? (select id::text from tool_fixture where k='chat') then raise exception 'FAIL: blocked unread count';end if;
end$$;
select public.pulse_block_user((select id from tool_fixture where k='a'),false);
select public.pulse_mark_read((select id from tool_fixture where k='chat'));
do $$begin
 if public.pulse_unread_preview((select id from tool_fixture where k='message')) is not null then raise exception 'FAIL: read notification';end if;
end$$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from tool_fixture where k='c'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 begin perform public.pulse_user_tools('note_get',p_chat=>(select id from tool_fixture where k='chat'));raise exception 'FAIL: outsider note access';exception when others then if sqlerrm='FAIL: outsider note access' then raise;end if;end;
 if public.pulse_unread_preview((select id from tool_fixture where k='message')) is not null then raise exception 'FAIL: outsider notification';end if;
end$$;
reset role;
update public.pulse_premium set expires_at=now()-interval '1 second' where user_id=(select id from tool_fixture where k='a');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from tool_fixture where k='a'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 if public.pulse_user_tools('style_get',p_chat=>(select id from tool_fixture where k='chat'))->>'style' is distinct from 'classic' then raise exception 'FAIL: expired style';end if;
 begin perform public.pulse_user_tools('quick_use',p_id=>(select id from tool_fixture where k='reply'));raise exception 'FAIL: expired quick use';exception when others then if sqlerrm='FAIL: expired quick use' then raise;end if;end;
end$$;
reset role;
do $$begin
 if has_function_privilege('anon','public.pulse_user_tools(text,uuid,uuid,text,text)','execute') or has_function_privilege('anon','public.pulse_unread_preview(uuid)','execute') then raise exception 'FAIL: anon access';end if;
 if has_table_privilege('authenticated','pulse_private.chat_notes','select') then raise exception 'FAIL: raw private note grant';end if;
end$$;
rollback;
