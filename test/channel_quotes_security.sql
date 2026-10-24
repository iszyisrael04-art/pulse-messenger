begin;
create temporary table quote_fixture(k text primary key,id uuid default gen_random_uuid());
insert into quote_fixture(k)values('owner'),('fan'),('channel'),('other'),('post');
grant select,update on quote_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at)select id,'authenticated','authenticated','quote-'||id||'@example.invalid',now()from quote_fixture where k in('owner','fan');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from quote_fixture where k='owner'),'role','authenticated')::text,true);
set local role authenticated;
update quote_fixture set id=public.pulse_create_channel('Quote fixture','')where k='channel';
update quote_fixture set id=public.pulse_create_channel('Other fixture','')where k='other';
select public.pulse_channel_post((select id from quote_fixture where k='channel'),'Original announcement');
update quote_fixture set id=(select id from public.pulse_posts where channel_id=(select id from quote_fixture where k='channel')limit 1)where k='post';
select public.pulse_channel_quote((select id from quote_fixture where k='channel'),(select id from quote_fixture where k='post'),'Quoted reply');
do $$declare h jsonb;begin
 h=public.pulse_channel_history((select id from quote_fixture where k='channel'));
 if not exists(select 1 from jsonb_array_elements(h) x where x->>'quoted_body'='Original announcement')then raise exception 'FAIL quote missing';end if;
 begin perform public.pulse_channel_quote((select id from quote_fixture where k='other'),(select id from quote_fixture where k='post'),'Cross-channel');raise exception 'FAIL cross-channel quote';exception when others then if sqlerrm='FAIL cross-channel quote'then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from quote_fixture where k='fan'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 begin perform public.pulse_channel_quote((select id from quote_fixture where k='channel'),(select id from quote_fixture where k='post'),'Unauthorized');raise exception 'FAIL fan posted';exception when others then if sqlerrm='FAIL fan posted'then raise;end if;end;
end $$;
reset role;
rollback;
