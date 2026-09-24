-- Room access checks (security fix). Run this in the SQL Editor of every
-- EXISTING Silo. Fresh deployments already include it, both through
-- normsar_silo_schema.sql and the docker init mount. Safe to re-run.
--
-- 1. Messages were readable and postable by ANY participant row, pending and
--    'left' included. Anyone can file a join request (a pending row) for a
--    room that accepts them, so a request alone showed the whole history of a
--    private room and allowed posting into it. Now: active participants (or a
--    public room, for reading).
--
-- 2. Room, message and participant policies checked a member's role without
--    their status, so an admin or moderator who was removed (status 'left')
--    kept their powers. Every role check now requires status 'active'.
--
-- 3. An author could change a message's room_id, moving it into another room
--    (a way to post where you aren't a member), and admins/moderators could
--    rewrite anyone's message content or author. A trigger now keeps room_id
--    and user_id fixed and limits changes to others' messages to moderation
--    (pin, forwarding, task tags).
--
-- 4. Signed-in people who aren't members couldn't see public rooms at all:
--    the only policy showing public rooms was for anon. They now can (as on
--    the Hub), so a public room link works for them and shows the join bar.

-- Same as is_room_admin_or_mod, for admins only. In public because the
-- private schema isn't usable by API roles on Silos.
create or replace function public.is_room_admin(_room_id uuid)
returns boolean
language plpgsql
stable security definer
set search_path to 'public'
as $$
begin
  return exists (
    select 1 from public.room_participants rp
    where rp.room_id = _room_id
      and rp.user_id = auth.uid()
      and rp.status = 'active'
      and rp.role = 'admin'
  );
end;
$$;

-- ---------------------------------------------------------------- rooms
drop policy if exists "Authenticated users can view public rooms" on public.chat_rooms;
create policy "Authenticated users can view public rooms" on public.chat_rooms
  for select to authenticated using (is_public = true);

drop policy if exists "Admins and Mods can update rooms" on public.chat_rooms;
create policy "Admins and Mods can update rooms" on public.chat_rooms
  for update to authenticated using (public.is_room_admin_or_mod(id));

drop policy if exists "Only Admins can delete rooms" on public.chat_rooms;
create policy "Only Admins can delete rooms" on public.chat_rooms
  for delete to authenticated using (public.is_room_admin(id));

-- ---------------------------------------------------------------- messages
drop policy if exists "Messages viewable by participants or if public" on public.chat_messages;
create policy "Messages viewable by participants or if public" on public.chat_messages
  for select to authenticated using (
    exists (select 1 from public.chat_rooms
            where chat_rooms.id = chat_messages.room_id and chat_rooms.is_public = true)
    or exists (select 1 from public.room_participants
               where room_participants.room_id = chat_messages.room_id
                 and room_participants.user_id = auth.uid()
                 and room_participants.status = 'active')
  );

drop policy if exists "Only participants can send messages" on public.chat_messages;
create policy "Only participants can send messages" on public.chat_messages
  for insert to authenticated with check (
    exists (select 1 from public.room_participants
            where room_participants.room_id = chat_messages.room_id
              and room_participants.user_id = auth.uid()
              and room_participants.status = 'active')
  );

drop policy if exists "Allow admins and mods to pin messages" on public.chat_messages;
create policy "Allow admins and mods to pin messages" on public.chat_messages
  for update to authenticated
  using (public.is_room_admin_or_mod(room_id))
  with check (public.is_room_admin_or_mod(room_id));

drop policy if exists "Authors or Admins/Mods can delete messages" on public.chat_messages;
create policy "Authors or Admins/Mods can delete messages" on public.chat_messages
  for delete to authenticated
  using (user_id = auth.uid() or public.is_room_admin_or_mod(room_id));

create or replace function private.guard_chat_message_update()
returns trigger
language plpgsql
set search_path to ''
as $$
declare
  -- Columns someone other than the author may change: moderation (pin,
  -- forwarding, task tags), plus the FK actions that null out
  -- reply_to_message_id (a replied-to message deleted) and user_id (the
  -- author's profile deleted).
  moderation text[] := array['is_pinned', 'allow_forwarding', 'tags', 'reply_to_message_id', 'user_id'];
begin
  if new.room_id is distinct from old.room_id then
    raise exception 'A message cannot be moved to another room' using errcode = '42501';
  end if;
  if new.user_id is distinct from old.user_id and new.user_id is not null then
    raise exception 'A message''s author cannot be changed' using errcode = '42501';
  end if;

  -- Signed-in callers editing someone else's message (admins/moderators; the
  -- service role has no auth.uid() and is checked by its edge functions).
  if auth.uid() is not null and old.user_id is distinct from auth.uid() then
    if (to_jsonb(new) - moderation) is distinct from (to_jsonb(old) - moderation)
       or (new.reply_to_message_id is distinct from old.reply_to_message_id
           and new.reply_to_message_id is not null) then
      raise exception 'Only the author can edit a message' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_chat_message_update on public.chat_messages;
create trigger guard_chat_message_update
  before update on public.chat_messages
  for each row execute function private.guard_chat_message_update();

-- ---------------------------------------------------------------- participants
drop policy if exists "Admins and Mods can update participants" on public.room_participants;
create policy "Admins and Mods can update participants" on public.room_participants
  for update to authenticated using (public.is_room_admin_or_mod(room_id));
