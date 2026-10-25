-- Free for all accounts; no animated-avatar entitlement is used.
begin;
create or replace function pulse_private.social_account(p_private boolean,p_cover text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform pulse_private.require_active();
 perform pulse_private.social_rate('account',30,3600);
 if p_private is null then raise exception 'Invalid privacy'; end if;
 if p_cover is not null and (split_part(p_cover,'/',1)<>auth.uid()::text or split_part(p_cover,'/',2)<>'cover' or not exists(select 1 from storage.objects where bucket_id='pulse-social' and name=p_cover and metadata->>'mimetype' in ('image/jpeg','image/png','image/webp','video/mp4') and (metadata->>'size')::bigint<=10485760)) then raise exception 'Invalid profile banner'; end if;
 insert into public.pulse_social_accounts(user_id,is_private,cover_path) values(auth.uid(),p_private,p_cover)
 on conflict(user_id) do update set is_private=excluded.is_private,cover_path=excluded.cover_path;
end
$$;

commit;
