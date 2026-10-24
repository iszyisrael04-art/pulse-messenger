begin;
alter table public.pulse_posts add column quoted_post_id uuid references public.pulse_posts on delete set null;
create index pulse_posts_quoted on public.pulse_posts(quoted_post_id) where quoted_post_id is not null;
create function pulse_private.channel_quote(p_channel uuid,p_post uuid,p_body text)returns void language plpgsql security definer set search_path=''as $$begin
 perform pulse_private.require_active();
 if not pulse_private.channel_admin(p_channel) then raise exception 'Channel administrator required';end if;
 if p_body is null or length(trim(p_body)) not between 1 and 4000 then raise exception 'Write a reply (1–4000 characters)';end if;
 if not exists(select 1 from public.pulse_posts where id=p_post and channel_id=p_channel and not pulse_private.social_blocked(author_id))then raise exception 'Announcement unavailable';end if;
 perform pulse_private.social_rate('channel_quote',20,60);
 insert into public.pulse_posts(channel_id,author_id,body,quoted_post_id)values(p_channel,auth.uid(),trim(p_body),p_post);
end $$;
create function public.pulse_channel_quote(p_channel uuid,p_post uuid,p_body text)returns void language sql security invoker set search_path=''as $$select pulse_private.channel_quote(p_channel,p_post,p_body)$$;
revoke all on function pulse_private.channel_quote(uuid,uuid,text),public.pulse_channel_quote(uuid,uuid,text)from public,anon,authenticated;
grant execute on function pulse_private.channel_quote(uuid,uuid,text),public.pulse_channel_quote(uuid,uuid,text)to authenticated;
create or replace function pulse_private.channel_history(p_channel uuid,p_query text,p_before timestamptz,p_cursor uuid,p_media boolean) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 perform pulse_private.require_active();
 if p_query is null or length(p_query)>100 or p_media is null or (p_before is null)<>(p_cursor is null) then raise exception 'Invalid search';end if;
 if not exists(select 1 from public.pulse_channels where id=p_channel and not pulse_private.social_blocked(owner_id)) then raise exception 'Channel unavailable';end if;
 return coalesce((select jsonb_agg(to_jsonb(rows) order by created_at desc,id desc) from(
 select p.*,(select left(q.body,500) from public.pulse_posts q where q.id=p.quoted_post_id and q.channel_id=p.channel_id and not pulse_private.social_blocked(q.author_id)) quoted_body from public.pulse_posts p where p.channel_id=p_channel and not pulse_private.social_blocked(p.author_id)
 and (not p_media or p.attachment_path is not null)
 and (trim(p_query)='' or to_tsvector('simple',p.body) @@ websearch_to_tsquery('simple',trim(p_query)))
 and (p_before is null or (p.created_at,p.id)<(p_before,p_cursor))
 order by p.created_at desc,p.id desc limit 30)rows),'[]');
end $$;
commit;
