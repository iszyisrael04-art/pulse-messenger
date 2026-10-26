begin;
-- Channels are deleted exclusively through an active Pulse staff account.
revoke delete on public.pulse_channels from public,anon,authenticated;
create policy channels_no_direct_delete on public.pulse_channels
 as restrictive for delete to authenticated using (false);

create function pulse_private.channel_delete(p_channel uuid) returns void
 language plpgsql security definer set search_path='' as $$
declare channel_name text; channel_owner uuid;
begin
 perform pulse_private.require_active();
 if not pulse_private.is_admin() then
  raise exception 'Only Pulse administrators can delete channels' using errcode='42501';
 end if;
 select name,owner_id into channel_name,channel_owner
 from public.pulse_channels where id=p_channel for update;
 if not found then raise exception 'Channel no longer exists' using errcode='P0002'; end if;
 insert into pulse_private.control_audit(staff_id,subject_id,action,detail)
 values(auth.uid(),channel_owner,'delete_channel',
 jsonb_build_object('channel_id',p_channel,'name',channel_name));
 delete from public.pulse_channels where id=p_channel;
end $$;
create function public.pulse_channel_delete(p_channel uuid) returns void
 language sql security invoker set search_path='' as $$
 select pulse_private.require_active();
 select pulse_private.channel_delete(p_channel)
$$;
revoke all on function pulse_private.channel_delete(uuid),public.pulse_channel_delete(uuid)
 from public,anon,authenticated;
grant execute on function pulse_private.channel_delete(uuid),public.pulse_channel_delete(uuid)
 to authenticated;
commit;
