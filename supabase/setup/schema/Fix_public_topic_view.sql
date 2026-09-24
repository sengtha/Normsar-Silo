-- Lets members of a parent room see its non-private sub-topics. Safe to
-- re-run: normsar_silo_schema.sql already contains this policy, and the
-- docker init runs this script after it, so it must not fail if it exists.
drop policy if exists "Authenticated users can view non-private child rooms via parent membership" on public.chat_rooms;
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
