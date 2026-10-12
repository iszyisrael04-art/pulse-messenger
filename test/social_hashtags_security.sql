begin;
create temporary table tag_fixture(k text primary key,id uuid default gen_random_uuid());
insert into tag_fixture(k) values('author'),('reader'),('post'),('draft'),('reel');
grant select on tag_fixture to authenticated;
insert into auth.users(id,aud,role,email,email_confirmed_at) select id,'authenticated','authenticated','pulse-tag-'||id||'@example.invalid',now() from tag_fixture where k in ('author','reader');
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from tag_fixture where k='author'),'role','authenticated')::text,true);
set local role authenticated;
select public.pulse_social_write((select id from tag_fixture where k='post'),'post','Hello #Gaming #gaming #Agent_Fury','[]','public',false);
select public.pulse_social_write((select id from tag_fixture where k='draft'),'post','#gaming draft','[]','public',true);
do $$ begin
 if not pulse_private.social_size_allowed(524288000) or pulse_private.social_size_allowed(524288001) then raise exception 'FAIL: free size boundary'; end if;
 if (public.pulse_social_upload_access(524288001)->>'allowed')::boolean then raise exception 'FAIL: free premium bypass'; end if;
 if pulse_private.social_tags('#Gaming #gaming')<>array['gaming'] then raise exception 'FAIL: duplicate hashtag'; end if;
 if jsonb_array_length(public.pulse_social_tag_feed('GAMING','all',null,null,20))<>1 then raise exception 'FAIL: draft leaked or case mismatch'; end if;
 if jsonb_array_length(public.pulse_social_tag_feed('game','all',null,null,20))<>0 then raise exception 'FAIL: substring match'; end if;
end $$;
reset role;
insert into public.pulse_premium(user_id,expires_at) values((select id from tag_fixture where k='author'),now()+interval '1 day');
set local role authenticated;
do $$ begin
 if not pulse_private.social_size_allowed(524288001) or pulse_private.social_size_allowed(2147483649) then raise exception 'FAIL: premium boundary'; end if;
end $$;
select public.pulse_social_account(true,null);
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from tag_fixture where k='reader'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if jsonb_array_length(public.pulse_social_tag_feed('gaming','all',null,null,20))<>0 then raise exception 'FAIL: private hashtag leak'; end if;
end $$;
select public.pulse_social_follow((select id from tag_fixture where k='author'),true);
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',(select id from tag_fixture where k='author'),'role','authenticated')::text,true);
set local role authenticated;
-- Enable public visibility, then caption edits must immediately re-index.
select public.pulse_social_account(false,null);
select public.pulse_social_edit((select id from tag_fixture where k='post'),'Now #NewTag',false);
do $$ begin
 if jsonb_array_length(public.pulse_social_tag_feed('gaming','all',null,null,20))<>0 or jsonb_array_length(public.pulse_social_tag_feed('newtag','all',null,null,20))<>1 then raise exception 'FAIL: stale tags after editing'; end if;
end $$;
select public.pulse_social_edit((select id from tag_fixture where k='post'),'',true);
do $$ begin
 if jsonb_array_length(public.pulse_social_tag_feed('newtag','all',null,null,20))<>0 then raise exception 'FAIL: deleted hashtag leak'; end if;
end $$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.pulse_social_tag_feed(text,text,timestamptz,uuid,int)','execute') then raise exception 'FAIL: anonymous search'; end if;
end $$;
rollback;
