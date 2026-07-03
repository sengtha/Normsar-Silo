-- Per-room unread tracking for sidebar badges (Silo side).
--
-- Mirrors the Hub's room_read_states + get_user_room_unread_counts. Run this
-- in the SQL Editor of an EXISTING Silo. Fresh deployments already include
-- these objects via normsar_silo_schema.sql.
--
-- Note: in a Silo, auth.uid() resolves to the Hub JWT `sub`, which equals
-- profiles.id — so read states reference profiles(id), matching how
-- room_participants.user_id is defined here.

create table if not exists public.room_read_states (
  user_id uuid not null references public.profiles (id) on delete cascade,
  room_id uuid not null references public.chat_rooms (id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (user_id, room_id)
);

create index if not exists chat_messages_room_created_idx
  on public.chat_messages (room_id, created_at);

alter table public.room_read_states enable row level security;

drop policy if exists "Users manage own read states (select)" on public.room_read_states;
create policy "Users manage own read states (select)" on public.room_read_states
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "Users manage own read states (insert)" on public.room_read_states;
create policy "Users manage own read states (insert)" on public.room_read_states
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "Users manage own read states (update)" on public.room_read_states;
create policy "Users manage own read states (update)" on public.room_read_states
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create or replace function public.get_user_room_unread_counts(p_user_id uuid)
returns json
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
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
    where m.user_id is distinct from p_user_id
      and (m.expires_at is null or m.expires_at > now())
      and m.created_at > coalesce(rs.last_read_at, rp.joined_at)
    group by m.room_id, cr.parent_room_id
  ) t;
$$;
