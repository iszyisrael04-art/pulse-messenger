begin;
alter table public.pulse_social_content add column allow_download boolean not null default true;
create function pulse_private.social_write_options(p_id uuid,p_kind text,p_body text,p_media jsonb,p_audience text,p_draft boolean,p_allow_download boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare existing public.pulse_social_content; result uuid;
begin
 perform pulse_private.require_active();
 if p_allow_download is null then raise exception 'Choose a download preference';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,13));
 select * into existing from public.pulse_social_content where id=p_id;
 result=pulse_private.social_write(p_id,p_kind,p_body,p_media,p_audience,p_draft);
 -- An uncertain-response retry preserves the already-published preference.
 if existing.id is null or existing.state='draft' then
 update public.pulse_social_content set allow_download=p_allow_download where id=result and author_id=auth.uid();
 end if;
 return result;
end $$;
create function public.pulse_social_write_options(p_id uuid,p_kind text,p_body text,p_media jsonb,p_audience text,p_draft boolean,p_allow_download boolean) returns uuid
language sql security invoker set search_path='' as $$select pulse_private.social_write_options(p_id,p_kind,p_body,p_media,p_audience,p_draft,p_allow_download)$$;
revoke all on function pulse_private.social_write_options(uuid,text,text,jsonb,text,boolean,boolean),public.pulse_social_write_options(uuid,text,text,jsonb,text,boolean,boolean) from public,anon;
grant execute on function pulse_private.social_write_options(uuid,text,text,jsonb,text,boolean,boolean),public.pulse_social_write_options(uuid,text,text,jsonb,text,boolean,boolean) to authenticated;
create function pulse_private.social_export_post(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 perform pulse_private.require_active();
 result=pulse_private.social_card(p_id);
 if result is null then raise exception 'Post unavailable';end if;
 if result->>'author_id'<>auth.uid()::text and not (result->>'allow_download')::boolean
 and exists(select 1 from jsonb_array_elements(result->'media') m where m->>'kind'='video')
 then raise exception 'The creator has disabled video downloads and external video sharing';end if;
 return result;
end $$;
create function public.pulse_social_export_post(p_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$select pulse_private.social_export_post(p_id)$$;
revoke all on function pulse_private.social_export_post(uuid),public.pulse_social_export_post(uuid) from public,anon;
grant execute on function pulse_private.social_export_post(uuid),public.pulse_social_export_post(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
