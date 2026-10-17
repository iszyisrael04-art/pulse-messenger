begin;
create function pulse_private.mail_worker(p_action text,p_id uuid,p_ok boolean) returns jsonb language plpgsql security definer set search_path='' as $$ declare result jsonb;begin
 if coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb->>'role' is distinct from 'service_role' then raise exception 'Service role required';end if;
 if p_action='claim' then
 with jobs as(select id from pulse_private.email_jobs where state='pending' order by created_at for update skip locked limit 10),claimed as(update pulse_private.email_jobs j set state='sending' from jobs where j.id=jobs.id returning j.*) select coalesce(jsonb_agg(claimed),'[]') into result from claimed;return result;
 elsif p_action='finish' then update pulse_private.email_jobs set state=case when p_ok then 'sent' else 'failed' end where id=p_id and state='sending';return 'true';end if;
 raise exception 'Unknown mail worker action';end $$;
create function public.pulse_mail_worker(p_action text,p_id uuid default null,p_ok boolean default null) returns jsonb language sql security invoker set search_path='' as $$ select pulse_private.mail_worker(p_action,p_id,p_ok) $$;
revoke all on function pulse_private.mail_worker(text,uuid,boolean),public.pulse_mail_worker(text,uuid,boolean) from public,anon,authenticated;
grant execute on function pulse_private.mail_worker(text,uuid,boolean),public.pulse_mail_worker(text,uuid,boolean) to service_role;
commit;
