begin;
alter table public.pulse_messages add column media_kind text check(media_kind in ('image','video','audio','file'));
alter table public.pulse_messages add column media_mime text;
alter table public.pulse_messages add column duration_ms int check(duration_ms between 0 and 300000);
alter table public.pulse_messages add column waveform jsonb;
create function pulse_private.send_media_message(p_id uuid,p_chat uuid,p_body text,p_reply uuid,p_attachment text,
 p_kind text,p_mime text,p_duration int,p_waveform jsonb) returns uuid language plpgsql security definer set search_path='' as $$
 declare actual text; sample jsonb; result uuid;
 begin
 if not pulse_private.is_member(p_chat) then raise exception 'Chat unavailable'; end if;
 if exists(select 1 from public.pulse_messages where id=p_id and sender_id=auth.uid() and chat_id=p_chat) then return p_id; end if;
 if p_kind is null or p_kind not in ('image','video','audio','file') or p_attachment is null then raise exception 'Invalid media'; end if;
 if split_part(p_attachment,'/',1)<>p_chat::text or split_part(p_attachment,'/',2)<>auth.uid()::text then raise exception 'Invalid attachment'; end if;
 select metadata->>'mimetype' into actual from storage.objects where bucket_id='pulse-media' and name=p_attachment;
 if actual is null then raise exception 'Upload the file before sending'; end if;
 if p_mime is null or length(p_mime)>100 or p_mime<>actual then raise exception 'Media type mismatch'; end if;
 if (p_kind='image' and actual not in ('image/jpeg','image/png','image/webp','image/gif')) or
 (p_kind='video' and actual not in ('video/mp4','video/quicktime','video/webm')) or
 (p_kind='audio' and actual not in ('audio/mp4','audio/mpeg','audio/ogg','audio/wav','audio/x-wav','audio/aac')) then raise exception 'Unsupported media type'; end if;
 if p_waveform is not null then
 if p_kind<>'audio' or jsonb_typeof(p_waveform)<>'array' or jsonb_array_length(p_waveform)>160 then raise exception 'Invalid waveform'; end if;
 for sample in select value from jsonb_array_elements(p_waveform) loop
 if jsonb_typeof(sample)<>'number' or sample::text::numeric<0 or sample::text::numeric>1 then raise exception 'Invalid waveform sample'; end if;
 end loop;
 end if;
 if p_duration is not null and (p_kind<>'audio' or p_duration<0 or p_duration>300000) then raise exception 'Invalid voice note duration'; end if;
 result=pulse_private.send_message(p_id,p_chat,p_body,p_reply,p_attachment);
 update public.pulse_messages set media_kind=p_kind,media_mime=p_mime,duration_ms=p_duration,waveform=p_waveform where id=result;
 return result;
 end
$$;
create function public.pulse_send_media_message(p_id uuid,p_chat uuid,p_body text,p_reply uuid,p_attachment text,
 p_kind text,p_mime text,p_duration int,p_waveform jsonb) returns uuid language sql security invoker set search_path='' as $$
 select pulse_private.send_media_message(p_id,p_chat,p_body,p_reply,p_attachment,p_kind,p_mime,p_duration,p_waveform)
$$;
revoke all on function pulse_private.send_media_message(uuid,uuid,text,uuid,text,text,text,int,jsonb),
 public.pulse_send_media_message(uuid,uuid,text,uuid,text,text,text,int,jsonb) from public,anon;
grant execute on function pulse_private.send_media_message(uuid,uuid,text,uuid,text,text,text,int,jsonb),
 public.pulse_send_media_message(uuid,uuid,text,uuid,text,text,text,int,jsonb) to authenticated;
commit;
