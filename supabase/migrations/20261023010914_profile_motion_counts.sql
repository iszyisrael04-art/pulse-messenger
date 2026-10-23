-- Five-second video avatar playback/export is bounded by native clients.
-- Database/storage retain ownership, size, MIME and Premium checks.
create or replace function pulse_private.avatar_upload_allowed(p_name text,p_mime text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and split_part(p_name,'/',1)=auth.uid()::text
 and ((p_mime in ('image/jpeg','image/png','image/webp') and lower(p_name) !~ '\.(gif|mp4)$')
 or (p_mime='image/gif' and lower(p_name) like '%.gif' and exists(select 1 from public.pulse_premium where user_id=auth.uid() and expires_at>now()))
 or (p_mime='video/mp4' and lower(p_name) like '%.mp4' and exists(select 1 from public.pulse_premium where user_id=auth.uid() and expires_at>now())))
$$;
revoke all on function pulse_private.avatar_upload_allowed(text,text) from public,anon;
grant execute on function pulse_private.avatar_upload_allowed(text,text) to authenticated;
update storage.buckets set allowed_mime_types=array['image/jpeg','image/png','image/webp','image/gif','video/mp4'],file_size_limit=15728640 where id='pulse-avatars';
create or replace function pulse_private.social_profile(p_user uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if pulse_private.social_blocked(p_user) then raise exception 'Profile unavailable'; end if;
 select jsonb_build_object('id',p.id,'username',p.username,'display_name',p.display_name,'bio',p.bio,'avatar_path',p.avatar_path,
 'cover_path',a.cover_path,'is_private',coalesce(a.is_private,false),'verified',coalesce(a.verified,false),
 'premium',exists(select 1 from public.pulse_premium where user_id=p.id and expires_at>now()),
 'follow_state',coalesce((select state from public.pulse_social_follows where follower_id=auth.uid() and creator_id=p.id),'none'),
 'followers',(select count(*) from public.pulse_social_follows where creator_id=p.id and state='accepted'),
 'following',(select count(*) from public.pulse_social_follows where follower_id=p.id and state='accepted'),
 'likes',(select count(*) from public.pulse_social_likes l join public.pulse_social_content c on c.id=l.post_id where c.author_id=p.id and c.state='published'),
 'analytics',case when p.id=auth.uid() then jsonb_build_object(
 'posts',(select count(*) from public.pulse_social_content where author_id=p.id and state='published' and kind='post'),
 'reels',(select count(*) from public.pulse_social_content where author_id=p.id and state='published' and kind='reel'),
 'views',(select count(*) from public.pulse_social_views v join public.pulse_social_content c on c.id=v.post_id where c.author_id=p.id and c.state='published'),
 'likes',(select count(*) from public.pulse_social_likes l join public.pulse_social_content c on c.id=l.post_id where c.author_id=p.id and c.state='published'),
 'comments',(select count(*) from public.pulse_social_comments m join public.pulse_social_content c on c.id=m.post_id where c.author_id=p.id and c.state='published' and m.deleted_at is null)) else null end)
 into result from public.pulse_profiles p left join public.pulse_social_accounts a on a.user_id=p.id where p.id=p_user;
 return result;
end
$$;

revoke all on function pulse_private.social_profile(uuid) from public,anon;
grant execute on function pulse_private.social_profile(uuid) to authenticated;
notify pgrst,'reload schema';
