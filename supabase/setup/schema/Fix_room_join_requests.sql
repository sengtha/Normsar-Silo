-- Fix: "Request to Join" was blocked by RLS.
--
-- The only INSERT policy on room_participants was "Only Admins and Mods can
-- add participants", so a regular user could never file their own join
-- request. Additionally, non-public rooms that accept join requests were not
-- SELECT-able by prospective members, so the join page could not even load
-- room details.
--
-- Run this in the SQL Editor of an EXISTING Silo. Fresh deployments already
-- include these policies via normsar_silo_schema.sql.

-- 1. Prospective members can view rooms that accept join requests
--    (needed for the /join/<silo>/<room> page and for the policy below).
DROP POLICY IF EXISTS "Authenticated users can view joinable rooms" ON public.chat_rooms;
CREATE POLICY "Authenticated users can view joinable rooms" ON public.chat_rooms
    FOR SELECT TO authenticated
    USING (
        (allow_join_requests = true)
        AND (is_direct_message = false)
        AND (COALESCE(is_personal_vault, false) = false)
    );

-- 2. Users can create their OWN join request — strictly pending + member,
--    and only for rooms that actually accept join requests.
DROP POLICY IF EXISTS "Users can request to join joinable rooms" ON public.room_participants;
CREATE POLICY "Users can request to join joinable rooms" ON public.room_participants
    FOR INSERT TO authenticated
    WITH CHECK (
        (user_id = auth.uid())
        AND (status = 'pending'::text)
        AND ((role)::text = 'member'::text)
        AND (EXISTS (
            SELECT 1 FROM public.chat_rooms cr
            WHERE cr.id = room_participants.room_id
              AND cr.allow_join_requests = true
              AND cr.is_direct_message = false
              AND COALESCE(cr.is_personal_vault, false) = false
        ))
    );
