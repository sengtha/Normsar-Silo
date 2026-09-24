-- Caller checks for three RPCs (security fix). Run this in the SQL Editor of
-- every EXISTING Silo. Fresh deployments already include it, both through
-- normsar_silo_schema.sql and the docker init mount. Safe to re-run.
--
-- Functions in public are executable by anon and authenticated unless
-- revoked, and PostgREST exposes the public schema — anything here can be
-- called straight from the API with the Silo's public anon key.
--
-- 1. match_doc_segments() returns the text of documents fed to Normsar AI for
--    a given room. It is SECURITY DEFINER and never checked the caller, so
--    anyone holding the anon key — no sign-in needed — could read documents
--    from any room, private ones included, given the room id. Its only caller
--    is the normsar-ai edge function, which uses the service role, so it is
--    now restricted to the service role.
--
-- 2. get_unique_room_tags() returned the tags of any room's messages, also
--    unchecked. It now applies the chat_messages read rule itself: a public
--    room, or one you're an active participant in. (Running it as the caller
--    instead would also hide public-room tags from signed-in non-members,
--    because the chat_rooms policies don't show them public rooms.)
--
-- 3. get_user_room_unread_counts(p_user_id) answered for any user, revealing
--    which rooms — private rooms and DMs included — someone belongs to. It now
--    only answers for the caller; the app only ever asks for the signed-in user.
--
-- Each step is skipped if its object doesn't exist on this Silo yet (e.g. a
-- Silo that never ran Fix_room_read_states.sql).

do $$
begin
  if to_regprocedure('public.match_doc_segments(public.vector, double precision, integer, uuid)') is not null then
    revoke execute on function public.match_doc_segments(public.vector, double precision, integer, uuid) from public;
    revoke execute on function public.match_doc_segments(public.vector, double precision, integer, uuid) from anon;
    revoke execute on function public.match_doc_segments(public.vector, double precision, integer, uuid) from authenticated;
    grant  execute on function public.match_doc_segments(public.vector, double precision, integer, uuid) to service_role;
  end if;

  if to_regprocedure('public.get_unique_room_tags(uuid)') is not null then
    execute $fn$
      create or replace function public.get_unique_room_tags(p_room_id uuid)
      returns table(tag text)
      language plpgsql
      security definer
      set search_path to 'public', 'pg_temp'
      as $body$
      begin
        -- Same rule as the chat_messages read policy: a public room, or one you're
        -- an active participant in. Any other room returns no tags.
        if not exists (select 1 from public.chat_rooms r where r.id = p_room_id and r.is_public = true)
           and not exists (select 1 from public.room_participants rp
                           where rp.room_id = p_room_id and rp.user_id = auth.uid() and rp.status = 'active')
        then
          return;
        end if;
      
        return query
        select distinct unnest(m.tags) as tag
        from public.chat_messages m
        where m.room_id = p_room_id
          and m.tags is not null
          and array_length(m.tags, 1) > 0;
      end;
      $body$;
    $fn$;
  end if;

  if to_regclass('public.room_read_states') is not null then
    execute $fn$
      create or replace function public.get_user_room_unread_counts(p_user_id uuid)
      returns json
      language sql
      stable
      security definer
      set search_path to 'public', 'pg_temp'
      as $body$
        select coalesce(json_agg(json_build_object(
                 'room_id', room_id, 'parent_room_id', parent_room_id, 'unread_count', cnt)), '[]'::json)
        from (
          select m.room_id, cr.parent_room_id, count(*)::int as cnt
          from public.chat_messages m
          join public.room_participants rp
            on rp.room_id = m.room_id
           and rp.user_id = p_user_id
           and rp.status = 'active'
          join public.chat_rooms cr on cr.id = m.room_id
          left join public.room_read_states rs
            on rs.room_id = m.room_id
           and rs.user_id = p_user_id
          where p_user_id = auth.uid()                              -- only your own counts
            and m.user_id is distinct from p_user_id                -- not your own messages
            and (m.expires_at is null or m.expires_at > now())      -- not expired
            and m.created_at > coalesce(rs.last_read_at, rp.joined_at) -- unread window
          group by m.room_id, cr.parent_room_id
        ) t;
      $body$
    $fn$;
  end if;
end $$;
