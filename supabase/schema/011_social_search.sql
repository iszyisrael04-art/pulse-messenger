begin;
alter table public.pulse_social_content add column if not exists search_document tsvector generated always as (to_tsvector('simple'::regconfig,body)) stored;
create index if not exists pulse_social_search_document on public.pulse_social_content using gin(search_document) where state='published' and not hidden;
create index if not exists pulse_social_recent_views on public.pulse_social_views(created_at desc,post_id);
create or replace function pulse_private.social_search(p_query text,p_kind text,p_before timestamptz,p_cursor uuid,p_limit int) returns jsonb language plpgsql stable security definer set search_path='' as $$
 declare query tsquery;
 begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_query is null or length(trim(p_query)) not between 1 and 100 or p_kind is null or p_kind not in ('all','video','post','reel') or p_limit is null or p_limit not between 1 and 20 or (p_before is null)<>(p_cursor is null) then raise exception 'Invalid search'; end if;
 query=websearch_to_tsquery('simple',p_query);
 return coalesce((select jsonb_agg(pulse_private.social_card(q.id) order by q.created_at desc,q.id desc) from (
 select c.id,c.created_at from public.pulse_social_content c where c.state='published' and not c.hidden and pulse_private.social_read(c.id)
 and (c.search_document @@ query or c.hashtags @> array[lower(trim(both '#' from trim(p_query)))])
 and (p_kind='all' or p_kind in ('post','reel') and c.kind=p_kind or p_kind='video' and c.media->0->>'kind'='video')
 and (p_before is null or (c.created_at,c.id)<(p_before,p_cursor)) order by c.created_at desc,c.id desc limit p_limit
 ) q),'[]'::jsonb);
 end
$$;
create or replace function public.pulse_social_search(p_query text,p_kind text,p_before timestamptz,p_cursor uuid,p_limit int) returns jsonb language sql stable security invoker set search_path='' as $$ select pulse_private.social_search(p_query,p_kind,p_before,p_cursor,p_limit) $$;
create or replace function pulse_private.social_search_people(p_query text) returns jsonb language plpgsql stable security definer set search_path='' as $$
 begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_query is null or length(trim(p_query)) not between 1 and 100 then raise exception 'Invalid search'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'username',p.username,'display_name',p.display_name,'avatar_path',p.avatar_path)) from (
 select p.id,p.username,p.display_name,p.avatar_path from public.pulse_profiles p where not pulse_private.social_blocked(p.id)
 and (strpos(lower(coalesce(p.username,'')),lower(trim(both '@' from trim(p_query))))>0 or strpos(lower(p.display_name),lower(trim(p_query)))>0)
 order by p.username,p.id limit 20) p),'[]'::jsonb);
 end
$$;
create or replace function public.pulse_social_search_people(p_query text) returns jsonb language sql stable security invoker set search_path='' as $$ select pulse_private.social_search_people(p_query) $$;
create or replace function pulse_private.social_suggestions(p_query text) returns jsonb language plpgsql stable security definer set search_path='' as $$
 declare term text; tags jsonb; people jsonb; captions jsonb;
 begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 term=lower(trim(both '#@' from trim(p_query)));
 if term is null or length(term) not between 2 and 100 then return '[]'::jsonb; end if;
 select coalesce(jsonb_agg(jsonb_build_object('text','#'||tag,'kind','hashtag')),'[]'::jsonb) into tags from (
 select distinct tag from public.pulse_social_content c cross join lateral unnest(c.hashtags) tag
 where c.state='published' and not c.hidden and pulse_private.social_read(c.id) and starts_with(tag,term) order by tag limit 5
 ) t;
 select coalesce(jsonb_agg(jsonb_build_object('text','@'||p.username,'kind','profile')),'[]'::jsonb) into people from (
 select p.username from public.pulse_profiles p where not pulse_private.social_blocked(p.id) and starts_with(lower(coalesce(p.username,'')),term) order by p.username limit 3) p;
 select coalesce(jsonb_agg(jsonb_build_object('text',body,'kind','video')),'[]'::jsonb) into captions from (
 select distinct left(c.body,80) body from public.pulse_social_content c where c.state='published' and not c.hidden and c.media->0->>'kind'='video' and pulse_private.social_read(c.id) and strpos(lower(c.body),term)>0 limit 3) c;
 return tags||people||captions;
 end
$$;
create or replace function public.pulse_social_suggestions(p_query text) returns jsonb language sql stable security invoker set search_path='' as $$ select pulse_private.social_suggestions(p_query) $$;
create or replace function pulse_private.social_trending() returns jsonb language plpgsql stable security definer set search_path='' as $$
 begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 return coalesce((select jsonb_agg(pulse_private.social_card(q.id) order by q.score desc,q.created_at desc,q.id desc) from (
 select c.id,c.created_at,count(v.user_id) score from public.pulse_social_content c join public.pulse_social_views v on v.post_id=c.id and v.created_at>now()-interval '7 days'
 where c.state='published' and not c.hidden and c.media->0->>'kind'='video' and pulse_private.social_read(c.id)
 group by c.id,c.created_at order by count(v.user_id) desc,c.created_at desc,c.id desc limit 20
 ) q),'[]'::jsonb);
 end
$$;
create or replace function public.pulse_social_trending() returns jsonb language sql stable security invoker set search_path='' as $$ select pulse_private.social_trending() $$;
revoke all on function pulse_private.social_search(text,text,timestamptz,uuid,int),public.pulse_social_search(text,text,timestamptz,uuid,int),pulse_private.social_search_people(text),public.pulse_social_search_people(text),pulse_private.social_suggestions(text),public.pulse_social_suggestions(text),pulse_private.social_trending(),public.pulse_social_trending() from public,anon;
grant execute on function pulse_private.social_search(text,text,timestamptz,uuid,int),public.pulse_social_search(text,text,timestamptz,uuid,int),pulse_private.social_search_people(text),public.pulse_social_search_people(text),pulse_private.social_suggestions(text),public.pulse_social_suggestions(text),pulse_private.social_trending(),public.pulse_social_trending() to authenticated;
commit;
