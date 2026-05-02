--
-- PostgreSQL database dump
-- Clean schema for Normsar Silo (public schema only)
-- All Supabase auth, storage, and realtime schemas removed
--

--
-- Extensions
--

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
COMMENT ON EXTENSION pg_cron IS 'Job scheduler for PostgreSQL';

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
COMMENT ON EXTENSION pg_net IS 'Async HTTP';

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;
COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';

--
-- Schemas
--

CREATE SCHEMA IF NOT EXISTS private;
CREATE SCHEMA IF NOT EXISTS extensions;

--
-- Tables
--

CREATE TABLE public.ai_briefing_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    title text,
    content text,
    briefing_date date DEFAULT CURRENT_DATE,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.chat_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    room_id uuid NOT NULL,
    user_id uuid NOT NULL,
    content text NOT NULL,
    attachments jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    tags text[] DEFAULT '{}'::text[],
    allow_forwarding boolean DEFAULT false,
    reply_to_message_id uuid,
    key_version integer DEFAULT 1,
    is_pinned boolean DEFAULT false,
    metadata jsonb,
    mentioned_users uuid[] DEFAULT '{}'::uuid[],
    expires_at timestamp with time zone,
    CONSTRAINT chat_messages_content_len_check CHECK ((char_length(content) <= 20000)),
    CONSTRAINT chat_messages_tags_len_check CHECK (((tags IS NULL) OR (array_length(tags, 1) <= 20)))
);

CREATE TABLE public.chat_rooms (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    is_direct_message boolean DEFAULT false NOT NULL,
    is_personal_vault boolean DEFAULT false NOT NULL,
    parent_room_id uuid,
    is_private_topic boolean DEFAULT false NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    is_public boolean DEFAULT false,
    allow_join_requests boolean DEFAULT false,
    is_e2ee boolean DEFAULT false,
    created_by uuid DEFAULT auth.uid(),
    websocket_transport text DEFAULT 'supabase'::text,
    is_archived boolean DEFAULT false,
    description text,
    CONSTRAINT chat_rooms_name_len_check CHECK (((name IS NULL) OR (char_length(name) <= 120))),
    CONSTRAINT chat_rooms_websocket_transport_len_check CHECK (((websocket_transport IS NULL) OR (char_length(websocket_transport) <= 50))),
    CONSTRAINT check_room_description_length CHECK ((char_length(description) <= 250)),
    CONSTRAINT check_room_description_not_empty CHECK (((description IS NULL) OR (char_length(TRIM(BOTH FROM description)) > 0)))
);

CREATE SEQUENCE public.doc_segments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE public.doc_segments (
    id bigint DEFAULT nextval('public.doc_segments_id_seq'::regclass) NOT NULL,
    room_id uuid,
    content text NOT NULL,
    embedding public.vector(768) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    source_message_id uuid,
    fed_by_user_id uuid,
    chunk_index integer,
    file_path text,
    CONSTRAINT doc_segments_content_len_check CHECK ((char_length(content) <= 20000)),
    CONSTRAINT doc_segments_file_path_len_check CHECK (((file_path IS NULL) OR (char_length(file_path) <= 1024)))
);

CREATE TABLE public.governance_proposals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    room_id uuid,
    nominee_user_id uuid NOT NULL,
    proposed_by uuid NOT NULL,
    status text DEFAULT 'pending'::text,
    created_at timestamp with time zone DEFAULT now(),
    silo_id uuid,
    CONSTRAINT room_governance_proposals_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'executed'::text, 'rejected'::text])))
);

CREATE TABLE public.message_reactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    message_id uuid NOT NULL,
    user_id uuid NOT NULL,
    emoji text NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT message_reactions_emoji_len_check CHECK (((emoji IS NULL) OR (char_length(emoji) <= 16)))
);

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    username text NOT NULL,
    avatar_url text,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    full_name text,
    vault_credentials text,
    display_name text,
    updated_at timestamp with time zone DEFAULT now(),
    email text,
    CONSTRAINT profiles_display_name_len_check CHECK (((display_name IS NULL) OR (char_length(display_name) <= 120))),
    CONSTRAINT profiles_email_len_check CHECK (((email IS NULL) OR (char_length(email) <= 254))),
    CONSTRAINT profiles_full_name_len_check CHECK (((full_name IS NULL) OR (char_length(full_name) <= 120))),
    CONSTRAINT profiles_username_len_check CHECK (((username IS NULL) OR ((char_length(username) >= 1) AND (char_length(username) <= 30))))
);

CREATE TABLE public.proposal_votes (
    proposal_id uuid NOT NULL,
    user_id uuid NOT NULL,
    vote text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT proposal_votes_vote_check CHECK ((vote = ANY (ARRAY['yes'::text, 'no'::text])))
);

CREATE TABLE public.room_keys (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    room_id uuid NOT NULL,
    version integer NOT NULL,
    lit_ciphertext text NOT NULL,
    lit_data_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT room_keys_lit_ciphertext_len_check CHECK (((lit_ciphertext IS NOT NULL) AND (char_length(lit_ciphertext) <= 500))),
    CONSTRAINT room_keys_lit_data_hash_len_check CHECK (((lit_data_hash IS NOT NULL) AND (char_length(lit_data_hash) <= 256)))
);

CREATE TABLE public.room_participants (
    room_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role character varying(50) DEFAULT 'member'::character varying,
    joined_at timestamp with time zone DEFAULT now(),
    status text DEFAULT 'active'::text,
    title text,
    CONSTRAINT room_participants_role_check CHECK (((role)::text = ANY ((ARRAY['admin'::character varying, 'moderator'::character varying, 'member'::character varying])::text[]))),
    CONSTRAINT room_participants_title_len_check CHECK (((title IS NULL) OR (char_length(title) <= 120))),
    CONSTRAINT valid_room_status CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'rejected'::text, 'left'::text])))
);

CREATE TABLE public.shared_content (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    original_message_id uuid,
    original_author_id uuid,
    shared_by_user_id uuid,
    target_room_id uuid,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE public.silo_activity_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    action_type text NOT NULL,
    location_name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT silo_activity_logs_action_type_len_check CHECK (((action_type IS NOT NULL) AND (char_length(action_type) <= 50))),
    CONSTRAINT silo_activity_logs_location_name_len_check CHECK (((location_name IS NULL) OR (char_length(location_name) <= 100)))
);

CREATE TABLE public.user_dismissals (
    user_id uuid NOT NULL,
    item_id uuid NOT NULL,
    item_type text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);

--
-- Primary Keys
--
ALTER TABLE ONLY public.ai_briefing_logs
    ADD CONSTRAINT ai_briefing_logs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.ai_briefing_logs
    ADD CONSTRAINT unique_user_briefing_day UNIQUE (user_id, briefing_date);

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.chat_rooms
    ADD CONSTRAINT rooms_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.doc_segments
    ADD CONSTRAINT doc_segments_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.governance_proposals
    ADD CONSTRAINT room_governance_proposals_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.message_reactions
    ADD CONSTRAINT message_reactions_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.message_reactions
    ADD CONSTRAINT message_reactions_message_id_user_id_emoji_key UNIQUE (message_id, user_id, emoji);

ALTER TABLE ONLY public.message_reactions
    ADD CONSTRAINT unique_user_message_emoji UNIQUE (message_id, user_id, emoji);

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_username_key UNIQUE (username);

ALTER TABLE ONLY public.proposal_votes
    ADD CONSTRAINT proposal_votes_pkey PRIMARY KEY (proposal_id, user_id);

ALTER TABLE ONLY public.room_keys
    ADD CONSTRAINT room_keys_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.room_keys
    ADD CONSTRAINT unique_room_version UNIQUE (room_id, version);

ALTER TABLE ONLY public.room_participants
    ADD CONSTRAINT room_participants_pkey PRIMARY KEY (room_id, user_id);

ALTER TABLE ONLY public.shared_content
    ADD CONSTRAINT shared_content_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.shared_content
    ADD CONSTRAINT unique_share_per_user_room UNIQUE NULLS NOT DISTINCT (original_message_id, shared_by_user_id, target_room_id);

ALTER TABLE ONLY public.silo_activity_logs
    ADD CONSTRAINT silo_activity_logs_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.user_dismissals
    ADD CONSTRAINT user_dismissals_pkey PRIMARY KEY (user_id, item_id, item_type);

-- Foreign Keys
-- public.ai_briefing_logs
ALTER TABLE ONLY public.ai_briefing_logs
    ADD CONSTRAINT ai_briefing_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id);

-- public.chat_messages
ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_reply_to_message_id_fkey FOREIGN KEY (reply_to_message_id) REFERENCES public.chat_messages(id) ON DELETE SET NULL;

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.chat_rooms(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- public.chat_rooms
ALTER TABLE ONLY public.chat_rooms
    ADD CONSTRAINT chat_rooms_parent_room_id_fkey FOREIGN KEY (parent_room_id) REFERENCES public.chat_rooms(id) ON DELETE SET NULL;

-- public.doc_segments
ALTER TABLE ONLY public.doc_segments
    ADD CONSTRAINT doc_segments_fed_by_user_id_fkey FOREIGN KEY (fed_by_user_id) REFERENCES public.profiles(id);

ALTER TABLE ONLY public.doc_segments
    ADD CONSTRAINT doc_segments_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.chat_rooms(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.doc_segments
    ADD CONSTRAINT doc_segments_source_message_id_fkey FOREIGN KEY (source_message_id) REFERENCES public.chat_messages(id) ON DELETE CASCADE;

-- public.governance_proposals
ALTER TABLE ONLY public.governance_proposals
    ADD CONSTRAINT fk_governance_nominee FOREIGN KEY (nominee_user_id) REFERENCES public.profiles(id);

ALTER TABLE ONLY public.governance_proposals
    ADD CONSTRAINT fk_governance_proposed_by FOREIGN KEY (proposed_by) REFERENCES public.profiles(id);

ALTER TABLE ONLY public.governance_proposals
    ADD CONSTRAINT room_governance_proposals_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.chat_rooms(id) ON DELETE CASCADE;

-- public.message_reactions
ALTER TABLE ONLY public.message_reactions
    ADD CONSTRAINT message_reactions_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.chat_messages(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.message_reactions
    ADD CONSTRAINT message_reactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- public.proposal_votes
ALTER TABLE ONLY public.proposal_votes
    ADD CONSTRAINT proposal_votes_proposal_id_fkey FOREIGN KEY (proposal_id) REFERENCES public.governance_proposals(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.proposal_votes
    ADD CONSTRAINT proposal_votes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- public.room_keys
ALTER TABLE ONLY public.room_keys
    ADD CONSTRAINT room_keys_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.chat_rooms(id) ON DELETE CASCADE;

-- public.room_participants
ALTER TABLE ONLY public.room_participants
    ADD CONSTRAINT room_participants_room_id_fkey FOREIGN KEY (room_id) REFERENCES public.chat_rooms(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.room_participants
    ADD CONSTRAINT room_participants_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- public.shared_content
ALTER TABLE ONLY public.shared_content
    ADD CONSTRAINT shared_content_original_author_id_fkey FOREIGN KEY (original_author_id) REFERENCES public.profiles(id);

ALTER TABLE ONLY public.shared_content
    ADD CONSTRAINT shared_content_original_message_id_fkey FOREIGN KEY (original_message_id) REFERENCES public.chat_messages(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.shared_content
    ADD CONSTRAINT shared_content_shared_by_user_id_fkey FOREIGN KEY (shared_by_user_id) REFERENCES public.profiles(id);

ALTER TABLE ONLY public.shared_content
    ADD CONSTRAINT shared_content_target_room_id_fkey FOREIGN KEY (target_room_id) REFERENCES public.chat_rooms(id) ON DELETE CASCADE;

-- public.user_dismissals
ALTER TABLE ONLY public.user_dismissals
    ADD CONSTRAINT user_dismissals_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;



--
-- Private Functions
--

CREATE FUNCTION private.auto_execute_creator_transfer() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'private', 'pg_temp'
    AS $$
DECLARE
    v_room_id UUID;
    v_nominee_id UUID;
    v_old_owner_id UUID;
    v_active_members INT;
    v_required_votes INT;
    v_current_yes_votes INT;
BEGIN
    SET LOCAL row_security = off;

    IF NEW.vote = 'yes' THEN
        SELECT p.room_id, p.nominee_user_id
        INTO v_room_id, v_nominee_id
        FROM public.governance_proposals p
        WHERE p.id = NEW.proposal_id AND p.status = 'pending';

        IF v_room_id IS NOT NULL THEN
            SELECT count(*)
            INTO v_active_members
            FROM public.room_participants rp
            WHERE rp.room_id = v_room_id AND rp.status = 'active';

            v_required_votes := LEAST(CEIL(v_active_members * 0.51), 10);

            SELECT count(*)
            INTO v_current_yes_votes
            FROM public.proposal_votes pv
            WHERE pv.proposal_id = NEW.proposal_id AND pv.vote = 'yes';

            IF v_current_yes_votes >= v_required_votes THEN
                SELECT r.created_by
                INTO v_old_owner_id
                FROM public.chat_rooms r
                WHERE r.id = v_room_id;

                UPDATE public.chat_rooms
                SET created_by = v_nominee_id
                WHERE id = v_room_id;

                UPDATE public.room_participants
                SET role = 'member'
                WHERE room_id = v_room_id AND user_id = v_old_owner_id;

                UPDATE public.room_participants
                SET role = 'admin'
                WHERE room_id = v_room_id AND user_id = v_nominee_id;

                UPDATE public.governance_proposals
                SET status = 'executed'
                WHERE id = NEW.proposal_id;
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


CREATE FUNCTION private.auto_toggle_dm_to_group() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  v_active_count INT;
  v_allow_join BOOLEAN;
  v_is_vault BOOLEAN;
  v_room_name TEXT;
  v_room_id UUID;
BEGIN
  -- Determine the affected room_id based on the database action
  IF TG_OP = 'DELETE' THEN
    v_room_id := OLD.room_id;
  ELSE
    v_room_id := NEW.room_id;
  END IF;

  -- Fetch room settings, including the room name
  SELECT allow_join_requests, COALESCE(is_personal_vault, false), name
  INTO v_allow_join, v_is_vault, v_room_name
  FROM public.chat_rooms
  WHERE id = v_room_id;

  -- Ensure we never touch personal vaults
  IF v_is_vault = FALSE THEN

    -- Count how many 'active' members currently exist
    SELECT count(*) INTO v_active_count
    FROM public.room_participants
    WHERE room_id = v_room_id AND status = 'active';

    -- RULE 1: Upgrade to Group
    -- If an unnamed DM gets a 3rd person, it becomes a group.
    IF v_active_count > 2 THEN
      UPDATE public.chat_rooms SET is_direct_message = false WHERE id = v_room_id;
    END IF;

    -- RULE 2: Downgrade to DM (The Fix)
    -- ONLY downgrade to a DM if the active count is 2 AND the room does not have a custom name.
    -- This protects your named community rooms from vanishing if members leave or haven't joined yet.
    IF v_active_count <= 2 AND v_room_name IS NULL THEN
      UPDATE public.chat_rooms SET is_direct_message = true WHERE id = v_room_id;
    END IF;

  END IF;

  RETURN NULL;
END;
$$;

CREATE FUNCTION private.enforce_room_participant_update() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public', 'auth'
    AS $$
begin
  -- If the user is an admin in this room, allow all updates.
  if exists (
    select 1 from public.room_participants rp
    where rp.room_id = NEW.room_id
      and rp.user_id = auth.uid()
      and rp.role = 'admin'
  ) then
    return NEW;
  end if;

  -- If the user is a moderator in this room, they may update status/title/role.
  -- They cannot change who the participant is (user_id) or move it to another room.
  if exists (
    select 1 from public.room_participants rp
    where rp.room_id = NEW.room_id
      and rp.user_id = auth.uid()
      and rp.role = 'moderator'
  ) then
    if (NEW.user_id <> OLD.user_id) or (NEW.room_id <> OLD.room_id) then
      raise exception 'Moderators may not change participant identity or room';
    end if;

    -- Allow role changes (e.g., setting someone to admin), as long as the value is valid
    -- (enforced by existing CHECK constraint).
    if (NEW.joined_at <> OLD.joined_at) then
      raise exception 'Moderators may not modify joined_at';
    end if;

    return NEW;
  end if;

  raise exception 'Not authorized to update room participants';
end;
$$;


CREATE FUNCTION private.handle_new_room_admin() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
BEGIN
  -- We only insert if there is an authenticated user making the request
  IF auth.uid() IS NOT NULL THEN
    INSERT INTO public.room_participants (room_id, user_id, role, status)
    VALUES (NEW.id, auth.uid(), 'admin', 'active');
  END IF;

  RETURN NEW;
END;
$$;


CREATE FUNCTION private.is_room_participant_admin_or_moderator(p_room_id uuid, p_user_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
  select exists (
    select 1
    from public.room_participants rp
    where rp.room_id = p_room_id
      and rp.user_id = p_user_id
      and rp.role::text in ('admin','moderator')
  );
$$;


CREATE FUNCTION private.log_silo_activity() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog', 'public'
    AS $$
DECLARE
  fetched_room_name TEXT;
BEGIN
  -- 1. Fetch the actual text name of the room using the ID from the new message
  SELECT name INTO fetched_room_name
  FROM public.chat_rooms
  WHERE id = NEW.room_id;

  -- 2. Insert the human-readable record into the log
  INSERT INTO public.silo_activity_logs (
    user_id,
    action_type,
    location_name
  )
  VALUES (
    NEW.user_id,
    TG_ARGV[0], -- Action type (e.g., 'Sent Message')
    COALESCE(fetched_room_name, 'General')
  );

  RETURN NEW;
END;
$$;


CREATE FUNCTION private.prevent_downgrading_security() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  -- Check if attempting to disable a Personal Vault
  IF OLD.is_personal_vault = true AND NEW.is_personal_vault = false THEN
    RAISE EXCEPTION 'Security constraint violation: Cannot remove personal vault status from this room.';
  END IF;

  -- Check if attempting to disable End-to-End Encryption
  IF OLD.is_e2ee = true AND NEW.is_e2ee = false THEN
    RAISE EXCEPTION 'Security constraint violation: Cannot disable End-to-End Encryption once enabled.';
  END IF;

  -- If neither rule is broken, allow the update to proceed
  RETURN NEW;
END;
$$;

--
-- Public Functions
--
CREATE FUNCTION public.is_room_admin_or_mod(_room_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.room_participants rp
    WHERE rp.room_id = _room_id
      AND rp.user_id = auth.uid()
      AND rp.status = 'active'
      AND rp.role IN ('admin', 'moderator')
  );
$$;

CREATE FUNCTION public._is_admin_or_moderator_of_room(p_room_id uuid) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  SELECT public.is_room_admin_or_mod(p_room_id);
$$;


CREATE FUNCTION public.get_shared_message(p_share_id uuid) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  result JSON;
BEGIN
  SELECT json_build_object(
    'id', m.id,
    'original_message_id', m.id,
    'content', m.content,
    'created_at', m.created_at,
    'attachments', m.attachments,
    'author_name', COALESCE(p.display_name, p.full_name, 'Unknown User'),
    'author_avatar', p.avatar_url,
    'shared_by', COALESCE(sp.display_name, 'Someone')
  ) INTO result
  FROM public.shared_content sc
  JOIN public.chat_messages m ON sc.original_message_id = m.id
  LEFT JOIN public.profiles p ON m.user_id = p.id
  LEFT JOIN public.profiles sp ON sc.shared_by_user_id = sp.id
  WHERE sc.id = p_share_id
  AND m.allow_forwarding = true; 

  RETURN result;
END;
$$;


CREATE FUNCTION public.get_unique_room_tags(p_room_id uuid) RETURNS TABLE(tag text)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT unnest(tags) AS tag
  FROM public.chat_messages
  WHERE room_id = p_room_id 
    AND tags IS NOT NULL 
    AND array_length(tags, 1) > 0;
END;
$$;


CREATE FUNCTION public.get_user_action_inbox(p_user_id uuid) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$DECLARE
  result json;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: You can only query your own inbox.';
  END IF;
  -- Build the inbox payload
  SELECT json_agg(row_to_json(t)) INTO result
  FROM (
    SELECT 
      m.id AS message_id,
      m.room_id,
      r.name AS room_name,
      p.full_name AS author_full_name,
      p.username AS author_username,
      p.avatar_url,
      m.content,
      m.created_at,
      CASE 
        -- Compare the user's UUID against the UUID array
        WHEN p_user_id = ANY(m.mentioned_users) THEN 'mention'
        ELSE 'reply'
      END AS inbox_type
    FROM public.chat_messages m
    JOIN public.chat_rooms r ON m.room_id = r.id
    JOIN public.profiles p ON m.user_id = p.id
    -- Ensure they are still active in the room
    JOIN public.room_participants rp 
      ON m.room_id = rp.room_id
     AND rp.user_id = p_user_id
     AND rp.status = 'active'
    WHERE
      m.created_at > NOW() - INTERVAL '90 days' 
      AND m.user_id <> p_user_id
      AND (
        -- Match against the new UUID array
        p_user_id = ANY(m.mentioned_users)
        OR m.reply_to_message_id IN (
          SELECT id
          FROM public.chat_messages
          WHERE user_id = p_user_id
        )
      )
      -- Exclude encrypted rooms
      AND COALESCE(r.is_personal_vault, false) = false
      AND COALESCE(r.is_e2ee, false) = false
      AND NOT EXISTS (
        SELECT 1
        FROM public.user_dismissals ud
        WHERE ud.user_id = p_user_id
          AND ud.item_id = m.id 
          AND ud.item_type IN ('mention', 'reply')
      )
    ORDER BY m.created_at DESC
    LIMIT 50
  ) t;

  RETURN COALESCE(result, '[]'::json);
END;$$;


CREATE FUNCTION public.get_user_active_todos(p_user_id uuid) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$DECLARE
  result json;
BEGIN
  IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Unauthorized: You can only query your own inbox.';
  END IF;
  SELECT json_agg(row_to_json(t)) INTO result
  FROM (
    SELECT
      m.id AS message_id,
      m.room_id,
      r.name AS room_name,
      p.full_name AS author_full_name,
      p.username AS author_username,
      p.avatar_url,
      m.content,
      m.created_at
    FROM public.chat_messages m
    JOIN public.chat_rooms r ON m.room_id = r.id
    JOIN public.profiles p ON m.user_id = p.id

    -- Ensure they are still active in the room
    JOIN public.room_participants rp
      ON m.room_id = rp.room_id
     AND rp.user_id = p_user_id
     AND rp.status = 'active'

    WHERE
      m.created_at > NOW() - INTERVAL '90 days'
      -- Exclude encrypted rooms
      AND (COALESCE(r.is_personal_vault, false) = false)
      AND (COALESCE(r.is_e2ee, false) = false)
      -- Must be a todo message
      AND ('todo' = ANY(m.tags) OR m.content ILIKE '%#todo%')

      -- THE DELEGATION LOGIC
      AND (
        -- Case 1: Delegated (The current user's UUID is explicitly in the array)
        p_user_id = ANY(m.mentioned_users)
        OR
        -- Case 2: Self-Assigned (Nobody was mentioned, AND the current user wrote it)
        (
          coalesce(cardinality(m.mentioned_users), 0) = 0
          AND m.user_id = p_user_id
        )
      )

      -- EXCLUDE DISMISSED ITEMS
      AND NOT EXISTS (
        SELECT 1
        FROM public.user_dismissals ud
        WHERE ud.user_id = p_user_id
          -- Comparing UUID to UUID cleanly without type casting
          AND ud.item_id = m.id
          AND ud.item_type = 'todo'
      )
    ORDER BY m.created_at DESC
    LIMIT 50
  ) t;

  RETURN COALESCE(result, '[]'::json);
END;$$;


CREATE FUNCTION public.handle_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE FUNCTION public.is_room_member(_room_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.room_participants rp
    WHERE rp.room_id = _room_id
      AND rp.user_id = auth.uid()
      AND rp.status = 'active'
  );
$$;


CREATE FUNCTION public.match_doc_segments(query_embedding public.vector, match_threshold double precision, match_count integer, p_room_id uuid) RETURNS TABLE(id bigint, content text, similarity double precision)
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    ds.id,
    ds.content,
    1 - (ds.embedding <=> query_embedding) AS similarity
  FROM public.doc_segments ds
  -- Privacy Lock: Only search documents that were fed into THIS specific room
  WHERE ds.room_id = p_room_id 
  AND 1 - (ds.embedding <=> query_embedding) > match_threshold
  ORDER BY ds.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;


CREATE FUNCTION public.update_chat_room_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE public.chat_rooms
  SET updated_at = NOW()
  WHERE id = NEW.room_id;
  
  RETURN NEW;
END;
$$;

-- TRIGGER

-- chat_rooms
-- Automatically adds the creator as an admin when a new room is created
CREATE TRIGGER on_room_created 
  AFTER INSERT ON public.chat_rooms 
  FOR EACH ROW EXECUTE FUNCTION private.handle_new_room_admin();

-- Updates the 'updated_at' column whenever room details change
CREATE TRIGGER set_chat_rooms_updated_at 
  BEFORE UPDATE ON public.chat_rooms 
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Prevents disabling E2E encryption or Personal Vault status once enabled
CREATE TRIGGER trigger_prevent_downgrading_security 
  BEFORE UPDATE ON public.chat_rooms 
  FOR EACH ROW EXECUTE FUNCTION private.prevent_downgrading_security();

-- Logs a "Sent Message" action to the silo activity logs
CREATE TRIGGER trigger_log_new_message 
  AFTER INSERT ON public.chat_messages 
  FOR EACH ROW EXECUTE FUNCTION private.log_silo_activity('Sent Message');

-- Bumps the 'updated_at' timestamp on the parent chat room when a new message is sent
CREATE TRIGGER trigger_update_room_timestamp 
  AFTER INSERT ON public.chat_messages 
  FOR EACH ROW EXECUTE FUNCTION public.update_chat_room_timestamp();

-- room_participants
-- Ensures only Admins/Mods can alter participant statuses/roles safely
CREATE TRIGGER room_participants_update_guard 
  BEFORE UPDATE ON public.room_participants 
  FOR EACH ROW EXECUTE FUNCTION private.enforce_room_participant_update();

-- Automatically toggles the `is_direct_message` flag if a 3rd person joins or leaves
CREATE TRIGGER trigger_auto_toggle_dm_to_group 
  AFTER INSERT OR DELETE OR UPDATE OF status ON public.room_participants 
  FOR EACH ROW EXECUTE FUNCTION private.auto_toggle_dm_to_group();

--proposal_votes
-- Automatically executes a creator transfer if a governance proposal reaches the required 'yes' votes
CREATE TRIGGER trigger_auto_execute_creator_transfer 
  AFTER INSERT ON public.proposal_votes 
  FOR EACH ROW EXECUTE FUNCTION private.auto_execute_creator_transfer();


--
-- Row Level Security (RLS) Policies
--

-- Enable RLS on all tables
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.doc_segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shared_content ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.governance_proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.proposal_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_briefing_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.silo_activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_dismissals ENABLE ROW LEVEL SECURITY;

-- Chat_room
create policy "Authenticated users can view non-private child rooms via parent membership"
on public.chat_rooms
for select
to authenticated
using (
  is_private_topic = false
  and parent_room_id is not null
  and exists (
    select 1
    from public.room_participants rp
    where rp.room_id = chat_rooms.parent_room_id
      and rp.user_id = auth.uid()
      and rp.status = 'active'
  )
);

CREATE POLICY "Admins and Mods can update rooms" ON public.chat_rooms FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1 FROM public.room_participants WHERE ((room_participants.room_id = chat_rooms.id) AND (room_participants.user_id = auth.uid()) AND ((room_participants.role)::text = ANY ((ARRAY['admin'::character varying, 'moderator'::character varying])::text[]))))));

CREATE POLICY "Allow public to view public rooms" ON public.chat_rooms FOR SELECT TO anon USING ((is_public = true));

CREATE POLICY "Authenticated users can create rooms" ON public.chat_rooms FOR INSERT TO authenticated WITH CHECK ((auth.uid() IS NOT NULL));

CREATE POLICY "Only Admins can delete rooms" ON public.chat_rooms FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1 FROM public.room_participants WHERE ((room_participants.room_id = chat_rooms.id) AND (room_participants.user_id = auth.uid()) AND ((room_participants.role)::text = 'admin'::text)))));

CREATE POLICY chat_rooms_select_stable ON public.chat_rooms FOR SELECT TO authenticated USING (((created_by = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1 FROM public.room_participants WHERE ((room_participants.room_id = chat_rooms.id) AND (room_participants.user_id = ( SELECT auth.uid() AS uid)) AND (room_participants.status = 'active'::text))))));

-- chat_messages
CREATE POLICY "Allow admins and mods to pin messages" ON public.chat_messages FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1 FROM public.room_participants WHERE ((room_participants.room_id = chat_messages.room_id) AND (room_participants.user_id = auth.uid()) AND ((room_participants.role)::text = ANY ((ARRAY['admin'::character varying, 'moderator'::character varying])::text[]))))));

CREATE POLICY "Allow public to view messages in public rooms" ON public.chat_messages FOR SELECT TO anon USING ((EXISTS ( SELECT 1 FROM public.chat_rooms WHERE ((chat_rooms.id = chat_messages.room_id) AND (chat_rooms.is_public = true)))));

CREATE POLICY "Authors can edit their own messages" ON public.chat_messages FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));

CREATE POLICY "Authors or Admins/Mods can delete messages" ON public.chat_messages FOR DELETE TO authenticated USING (((user_id = auth.uid()) OR (EXISTS ( SELECT 1 FROM public.room_participants WHERE ((room_participants.room_id = chat_messages.room_id) AND (room_participants.user_id = auth.uid()) AND ((room_participants.role)::text = ANY ((ARRAY['admin'::character varying, 'moderator'::character varying])::text[])))))));

CREATE POLICY "Messages viewable by participants or if public" ON public.chat_messages FOR SELECT TO authenticated USING (((EXISTS ( SELECT 1 FROM public.chat_rooms WHERE ((chat_rooms.id = chat_messages.room_id) AND (chat_rooms.is_public = true)))) OR (EXISTS ( SELECT 1 FROM public.room_participants WHERE ((room_participants.room_id = chat_messages.room_id) AND (room_participants.user_id = auth.uid()))))));

CREATE POLICY "Only participants can send messages" ON public.chat_messages FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1 FROM public.room_participants WHERE ((room_participants.room_id = chat_messages.room_id) AND (room_participants.user_id = auth.uid())))));

--room_participants
CREATE POLICY "Admins and Mods can update participants" ON public.room_participants FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1 FROM public.room_participants rp WHERE ((rp.room_id = room_participants.room_id) AND (rp.user_id = auth.uid()) AND ((rp.role)::text = ANY ((ARRAY['admin'::character varying, 'moderator'::character varying])::text[]))))));

CREATE POLICY "Leave room or Admins/Mods can kick" ON public.room_participants FOR DELETE TO authenticated USING (((user_id = auth.uid()) OR (public.is_room_admin_or_mod(room_id) AND (((EXISTS ( SELECT 1 FROM public.room_participants rp_self WHERE ((rp_self.room_id = room_participants.room_id) AND (rp_self.user_id = auth.uid()) AND ((rp_self.role)::text = 'admin'::text)))) AND (user_id <> ( SELECT cr.created_by FROM public.chat_rooms cr WHERE (cr.id = room_participants.room_id)))) OR ((NOT (EXISTS ( SELECT 1 FROM public.room_participants rp_self WHERE ((rp_self.room_id = room_participants.room_id) AND (rp_self.user_id = auth.uid()) AND ((rp_self.role)::text = 'admin'::text))))) AND ((role)::text = 'member'::text))) AND (NOT (EXISTS ( SELECT 1 FROM public.governance_proposals gp WHERE ((gp.room_id = room_participants.room_id) AND (gp.nominee_user_id = room_participants.user_id) AND (gp.status = 'active'::text))))))));

CREATE POLICY "Only Admins and Mods can add participants" ON public.room_participants FOR INSERT TO authenticated WITH CHECK (public.is_room_admin_or_mod(room_id));

CREATE POLICY "View room participants" ON public.room_participants FOR SELECT TO authenticated USING ((public.is_room_admin_or_mod(room_id) OR ((status = 'active'::text) AND public.is_room_member(room_id)) OR (user_id = auth.uid())));

-- profiles
CREATE POLICY "Allow public to view profiles of active public participants" ON public.profiles FOR SELECT TO anon USING ((EXISTS ( SELECT 1 FROM (public.chat_messages JOIN public.chat_rooms ON ((chat_rooms.id = chat_messages.room_id))) WHERE ((chat_messages.user_id = profiles.id) AND (chat_rooms.is_public = true)))));

CREATE POLICY "Users can insert their own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK ((id = auth.uid()));

CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE TO authenticated USING ((id = auth.uid())) WITH CHECK ((id = auth.uid()));

CREATE POLICY "Valid token holders can read all profiles" ON public.profiles FOR SELECT TO authenticated USING (((auth.jwt() ->> 'sub'::text) IS NOT NULL));

-- doc_segments (AI RAG)
CREATE POLICY doc_segments_insert_own ON public.doc_segments FOR INSERT TO authenticated WITH CHECK (((fed_by_user_id = auth.uid()) AND (EXISTS ( SELECT 1 FROM public.room_participants rp WHERE ((rp.room_id = doc_segments.room_id) AND (rp.user_id = auth.uid()) AND (rp.status = 'active'::text))))));

CREATE POLICY doc_segments_select_room_members ON public.doc_segments FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1 FROM public.room_participants rp WHERE ((rp.room_id = doc_segments.room_id) AND (rp.user_id = auth.uid()) AND (rp.status = 'active'::text)))));

-- governance_proposals & proposal_votes
CREATE POLICY "Users can create proposals in their active rooms" ON public.governance_proposals FOR INSERT TO authenticated WITH CHECK (((proposed_by = auth.uid()) AND (EXISTS ( SELECT 1 FROM public.room_participants rp WHERE ((rp.room_id = governance_proposals.room_id) AND (rp.user_id = auth.uid()) AND (rp.status = 'active'::text))))));

CREATE POLICY "Users can view proposals in their active rooms" ON public.governance_proposals FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1 FROM public.room_participants rp WHERE ((rp.room_id = governance_proposals.room_id) AND (rp.user_id = auth.uid()) AND (rp.status = 'active'::text)))));

CREATE POLICY "Admins and Mods can cast votes on active proposals" ON public.proposal_votes FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) AND (EXISTS ( SELECT 1 FROM (public.governance_proposals gp JOIN public.room_participants rp ON ((rp.room_id = gp.room_id))) WHERE ((gp.id = proposal_votes.proposal_id) AND (rp.user_id = auth.uid()) AND (rp.status = 'active'::text) AND ((rp.role)::text = ANY ((ARRAY['admin'::character varying, 'moderator'::character varying])::text[])) AND (gp.status = 'pending'::text))))));

CREATE POLICY "Users can update their own votes" ON public.proposal_votes FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));

CREATE POLICY "Users can view votes for proposals in their active rooms" ON public.proposal_votes FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1 FROM (public.governance_proposals rgp JOIN public.room_participants rp ON ((rgp.room_id = rp.room_id))) WHERE ((rgp.id = proposal_votes.proposal_id) AND (rp.user_id = auth.uid()) AND (rp.status = 'active'::text)))));

-- room_keys (End-to-End Encryption)
CREATE POLICY "Participants can insert room keys for Silos only" ON public.room_keys FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1 FROM (public.room_participants rp JOIN public.chat_rooms cr ON ((rp.room_id = cr.id))) WHERE ((rp.room_id = room_keys.room_id) AND (rp.user_id = auth.uid()) AND (cr.is_e2ee = true)))));

CREATE POLICY "Participants can view room keys in Silos" ON public.room_keys FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1 FROM (public.room_participants rp JOIN public.chat_rooms cr ON ((rp.room_id = cr.id))) WHERE ((rp.room_id = room_keys.room_id) AND (rp.user_id = auth.uid()) AND (cr.is_e2ee = true)))));

-- shared_content
CREATE POLICY "Anyone can insert a share link" ON public.shared_content FOR INSERT TO authenticated WITH CHECK ((shared_by_user_id = COALESCE(auth.uid(), ((auth.jwt() ->> 'sub'::text))::uuid)));

CREATE POLICY "Public Read Access" ON public.shared_content FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can delete their own share links" ON public.shared_content FOR DELETE TO authenticated USING ((shared_by_user_id = COALESCE(auth.uid(), ((auth.jwt() ->> 'sub'::text))::uuid)));

-- message_reactions
CREATE POLICY "Users can delete their own reactions" ON public.message_reactions FOR DELETE TO authenticated USING ((user_id = auth.uid()));

CREATE POLICY "Users can insert their own reactions" ON public.message_reactions FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));

CREATE POLICY "Users can update their own reactions" ON public.message_reactions FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));

CREATE POLICY "Valid token holders can read reactions" ON public.message_reactions FOR SELECT TO authenticated USING (((auth.jwt() ->> 'sub'::text) IS NOT NULL));

-- silo_activity_logs & ai_briefing_logs
CREATE POLICY "Users can insert own logs" ON public.silo_activity_logs FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));

CREATE POLICY "Users can insert own silo logs" ON public.silo_activity_logs FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));

CREATE POLICY "Users can read own silo logs" ON public.silo_activity_logs FOR SELECT TO authenticated USING ((user_id = auth.uid()));

CREATE POLICY "Users can insert own logs" ON public.ai_briefing_logs FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id));

CREATE POLICY "Users can only see their own briefings" ON public.ai_briefing_logs FOR SELECT TO authenticated USING ((auth.uid() = user_id));

CREATE POLICY "Users can view own logs" ON public.ai_briefing_logs FOR SELECT TO authenticated USING ((auth.uid() = user_id));

-- user_dismissals
CREATE POLICY "Users can only insert their own dismissals" ON public.user_dismissals FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));

CREATE POLICY "Users can read their own dismissals" ON public.user_dismissals FOR SELECT TO authenticated USING ((user_id = auth.uid()));



-- ============================================================================
-- NORMSAR SILO: PRODUCTION PERFORMANCE INDEXES
-- Purpose: Optimized for AI Search, Real-time Messaging, and DAO Governance.
-- ============================================================================

-- 1. AI VECTOR SEARCH (Most Critical)
-- Ensures fast similarity search for RAG/STEM research.
-- Already present in original schema, included here for completeness.
CREATE INDEX IF NOT EXISTS idx_doc_segments_embedding 
ON public.doc_segments USING hnsw (embedding public.vector_cosine_ops);

-- 2. CHAT & MESSAGING PERFORMANCE
-- Speeds up loading the newest messages when entering a room.
CREATE INDEX IF NOT EXISTS idx_chat_messages_room_id_created_at 
ON public.chat_messages(room_id, created_at DESC);

-- Speeds up looking up specific authors for message history.
CREATE INDEX IF NOT EXISTS idx_chat_messages_user_id 
ON public.chat_messages(user_id);

-- 3. NOTIFICATIONS & INBOX (Mentions/Replies)
-- Speeds up the "Action Inbox" by indexing the mentioned_users array.
CREATE INDEX IF NOT EXISTS idx_chat_messages_mentions 
ON public.chat_messages USING gin (mentioned_users);

-- Speeds up reply-thread lookups.
CREATE INDEX IF NOT EXISTS idx_chat_messages_reply_to 
ON public.chat_messages(reply_to_message_id);

-- 4. PERMISSIONS & LOOKUPS
-- Speeds up checking if a user is an Admin/Mod in a room (used in RLS).
CREATE INDEX IF NOT EXISTS idx_room_participants_user_id 
ON public.room_participants(user_id);

-- Optimized room structure lookups.
CREATE INDEX IF NOT EXISTS idx_chat_rooms_parent_room_id 
ON public.chat_rooms(parent_room_id);

CREATE INDEX IF NOT EXISTS idx_chat_rooms_is_archived 
ON public.chat_rooms(is_archived);

-- 5. ACTIVITY & CLEANUP LOOKUPS
-- Speeds up "User Dismissals" to keep the inbox clean.
CREATE INDEX IF NOT EXISTS idx_user_dismissals_lookup 
ON public.user_dismissals(user_id, item_type, item_id);

-- Speeds up activity log dashboard for admins.
CREATE INDEX IF NOT EXISTS idx_silo_activity_logs_user_created 
ON public.silo_activity_logs(user_id, created_at DESC);

-- 6. CONTENT SHARING
-- Speeds up tracking of shared/forwarded messages across Silos.
CREATE INDEX IF NOT EXISTS idx_shared_content_target_room_id 
ON public.shared_content(target_room_id);

CREATE INDEX IF NOT EXISTS idx_shared_content_shared_by 
ON public.shared_content(shared_by_user_id);

-- Insert Normsar AI System Profile
-- Essential for system-level notifications and AI interactions.
INSERT INTO public.profiles (id, username, full_name, display_name, avatar_url)
VALUES (
    '00000000-0000-0000-0000-000000000000', 
    'normsar', 
    'Normsar AI', 
    'Normsar',
    'https://cdn.normsar.io/official/ai.png'
) ON CONFLICT (id) DO UPDATE SET avatar_url = EXCLUDED.avatar_url;

-- Cron Tasks
SELECT cron.schedule(
  'jobid_3_delete_expired_chat_messages',
  '*/5 * * * *',
  $$
  DELETE FROM public.chat_messages
  WHERE expires_at < NOW();
  $$
);
SELECT cron.schedule(
  'jobid_4_cleanup_silo_activity_logs',
  '0 2 * * *',
  $$
  DELETE FROM public.silo_activity_logs
  WHERE created_at < (NOW() - INTERVAL '3 months');
  $$
);
-- Storage
INSERT INTO storage.buckets (id, name, public) VALUES ('silo_uploads', 'silo_uploads', true);
CREATE POLICY "Valid token holders can view files" ON storage.objects 
FOR SELECT USING (
  (bucket_id = 'silo_uploads'::text) AND 
  (((auth.jwt() ->> 'sub'::text))::uuid IS NOT NULL)
);
CREATE POLICY "Valid token holders can upload files" ON storage.objects 
FOR INSERT WITH CHECK (
  (bucket_id = 'silo_uploads'::text) AND 
  (((auth.jwt() ->> 'sub'::text))::uuid IS NOT NULL)
);
CREATE POLICY "Users can delete their own files" ON storage.objects 
FOR DELETE USING (
  (bucket_id = 'silo_uploads'::text) AND 
  ((string_to_array(name, '/'::text))[1] = (auth.jwt() ->> 'sub'::text))
);

