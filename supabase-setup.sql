-- ============================================================
-- Futsal Attendance Tracker — Supabase setup (safe to re-run)
-- Run this in your Supabase project's SQL Editor
-- (Dashboard → SQL Editor → New query → paste → Run)
-- ============================================================

-- 0. Create tables if they don't exist yet, and make sure RLS is OFF
--    while we set up columns/data — in case an earlier partial run
--    already turned it on and would otherwise block these edits.
--    NOTE: "create table if not exists" is a no-op if the table is
--    already there (Postgres doesn't reconcile columns in that case) —
--    so for a brand-new project this creates the full correct table in
--    one shot, and for your existing table it's skipped, with the
--    ALTER TABLE / cleanup statements further down doing the patching.
create table if not exists public.match_info (
  id int primary key default 1
);
create table if not exists public.players (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  display_name text not null,
  attend text check (attend in ('yes','no')),
  group_name text check (group_name in ('A','B')),
  created_at timestamptz not null default now()
);
alter table public.match_info disable row level security;
alter table public.players disable row level security;

-- 1. Match info: a single row holding venue + kickoff time
alter table public.match_info add column if not exists venue text;
alter table public.match_info add column if not exists kickoff_time text;
alter table public.match_info add column if not exists updated_at timestamptz not null default now();
update public.match_info set venue = 'Central Futsal Arena' where venue is null;
update public.match_info set kickoff_time = 'Fri, 7:00 PM' where kickoff_time is null;
alter table public.match_info alter column venue set not null;
alter table public.match_info alter column kickoff_time set not null;

insert into public.match_info (id, venue, kickoff_time)
  values (1, 'Central Futsal Arena', 'Fri, 7:00 PM')
  on conflict (id) do nothing;

-- 2. Players: one row per player — either a signed-in user
--    (user_id set) or a guest added by the admin (user_id null)
alter table public.players add column if not exists user_id uuid references auth.users(id) on delete set null;
alter table public.players add column if not exists display_name text;
update public.players set display_name = 'Player' where display_name is null;
alter table public.players alter column display_name set not null;
alter table public.players add column if not exists attend text;
alter table public.players add column if not exists group_name text;
alter table public.players add column if not exists created_at timestamptz not null default now();

-- Neutralize ANY other NOT NULL columns already on this table that our
-- inserts don't set (e.g. a leftover "team" column from an earlier
-- schema). Without this, any such column blocks every insert with a
-- "null value in column ... violates not-null constraint" error.
do $$
declare
  col record;
begin
  for col in
    select column_name
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'players'
      and is_nullable = 'no'
      and column_name not in ('id', 'display_name', 'created_at')
  loop
    execute format('alter table public.players alter column %I drop not null', col.column_name);
  end loop;
end $$;

-- Sanitize any leftover/legacy values so the CHECK constraints below
-- can never fail to apply. A single bad row here would otherwise abort
-- this entire script partway through — silently leaving every function
-- further down (including the admin "add player" fix) never created.
update public.players set attend = null where attend is not null and attend not in ('yes','no');
update public.players set group_name = null where group_name is not null and group_name not in ('A','B');

-- constraints (drop-then-add so re-running this script doesn't error)
alter table public.players drop constraint if exists players_attend_check;
alter table public.players add constraint players_attend_check check (attend in ('yes','no'));
alter table public.players drop constraint if exists players_group_name_check;
alter table public.players add constraint players_group_name_check check (group_name in ('A','B'));

-- 3. Row Level Security (turned back on now that data/columns are clean)
alter table public.match_info enable row level security;
alter table public.players enable row level security;

drop policy if exists "read match info" on public.match_info;
create policy "read match info" on public.match_info
  for select using (auth.role() = 'authenticated');

drop policy if exists "read players" on public.players;
create policy "read players" on public.players
  for select using (auth.role() = 'authenticated');

-- Only the admin account can change the venue / kickoff time
drop policy if exists "admin updates match info" on public.match_info;
create policy "admin updates match info" on public.match_info
  for update using ( lower(auth.jwt() ->> 'email') = 'whitewalkerofnorth@gmail.com' );

-- The admin can add any player row; a signed-in user can add their own row
drop policy if exists "admin or self inserts player" on public.players;
create policy "admin or self inserts player" on public.players
  for insert with check (
    lower(auth.jwt() ->> 'email') = 'whitewalkerofnorth@gmail.com'
    or auth.uid() = user_id
  );

-- Only the admin can delete players
drop policy if exists "admin deletes player" on public.players;
create policy "admin deletes player" on public.players
  for delete using ( lower(auth.jwt() ->> 'email') = 'whitewalkerofnorth@gmail.com' );

-- The admin can update any row; a user can update their own row
-- (the trigger below stops a non-admin from renaming themselves or
--  reassigning the row to someone else)
drop policy if exists "admin or self updates player" on public.players;
create policy "admin or self updates player" on public.players
  for update using (
    lower(auth.jwt() ->> 'email') = 'whitewalkerofnorth@gmail.com'
    or auth.uid() = user_id
  ) with check (
    lower(auth.jwt() ->> 'email') = 'whitewalkerofnorth@gmail.com'
    or auth.uid() = user_id
  );

-- 4. Guard trigger: non-admins may only ever change attend/group_name
create or replace function public.guard_player_update()
returns trigger
language plpgsql
security definer
as $$
begin
  if lower(auth.jwt() ->> 'email') is distinct from 'whitewalkerofnorth@gmail.com' then
    new.display_name := old.display_name;
    new.user_id := old.user_id;
  end if;
  return new;
end;
$$;

drop trigger if exists players_guard_update on public.players;
create trigger players_guard_update
  before update on public.players
  for each row execute function public.guard_player_update();

-- 5. Turn on realtime broadcasting for both tables (skip quietly if already added)
do $$
begin
  alter publication supabase_realtime add table public.match_info;
exception when others then raise notice 'realtime publication step skipped: %', SQLERRM;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.players;
exception when others then raise notice 'realtime publication step skipped: %', SQLERRM;
end $$;

-- 6. Explicit table-level grants. RLS policies only control WHICH rows a
--    role can touch — the role also needs baseline permission on the
--    table itself. Supabase usually sets this up automatically, but if
--    these tables were created directly in the SQL editor it may be
--    missing, which causes every write to fail with a "permission
--    denied for table players" error regardless of the RLS policies
--    above. Running this explicitly removes that possibility.
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.players to authenticated;
grant select, insert, update, delete on public.match_info to authenticated;

-- 7. Admin actions as SECURITY DEFINER functions.
--    These run with the privileges of the function's owner (the role
--    that runs this script, normally "postgres" — the same role that
--    owns these tables and therefore always bypasses RLS on them). That
--    means these calls succeed regardless of any RLS-policy or GRANT
--    misconfiguration on the base tables — the only gate is the email
--    check written directly into each function. This is the reliable
--    path for every admin-only write in the app.

create or replace function public.admin_add_player(p_name text, p_group text default null)
returns public.players
language plpgsql
security definer
set search_path = public
as $$
declare
  new_row public.players;
  col record;
  cols text[] := array['display_name','attend','group_name'];
  vals text[] := array[
    quote_literal(trim(p_name)),
    case when p_group is not null then quote_literal('yes') else 'null' end,
    case when p_group is not null then quote_literal(p_group) else 'null' end
  ];
  ins_sql text;
begin
  if lower(auth.jwt() ->> 'email') is distinct from 'whitewalkerofnorth@gmail.com' then
    raise exception 'Only the admin can add players';
  end if;

  -- Auto-fill ANY other required column this table happens to have
  -- (e.g. legacy "team", "username", "password", etc. columns) with a safe blank value,
  -- so admin never needs to know about or supply it.
  for col in
    select c.column_name, c.data_type
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'players'
      and c.is_nullable = 'no'
      and c.column_name not in ('id','display_name','attend','group_name','created_at','user_id')
  loop
    cols := cols || col.column_name;
    vals := vals || (case
      when col.data_type in ('character varying','text','character') then quote_literal('')
      when col.data_type = 'uuid' then 'gen_random_uuid()'
      when col.data_type = 'boolean' then 'false'
      when col.data_type in ('integer','bigint','smallint','numeric','real','double precision') then '0'
      else 'null'
    end);
  end loop;

  ins_sql := format('insert into public.players (%s) values (%s) returning *',
                     array_to_string(cols, ','), array_to_string(vals, ','));
  execute ins_sql into new_row;
  return new_row;
end;
$$;

create or replace function public.admin_remove_player(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if lower(auth.jwt() ->> 'email') is distinct from 'whitewalkerofnorth@gmail.com' then
    raise exception 'Only the admin can remove players';
  end if;
  delete from public.players where id = p_id;
end;
$$;

create or replace function public.admin_set_group(p_id uuid, p_group text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if lower(auth.jwt() ->> 'email') is distinct from 'whitewalkerofnorth@gmail.com' then
    raise exception 'Only the admin can move players between groups';
  end if;
  update public.players set group_name = p_group where id = p_id;
end;
$$;

create or replace function public.admin_set_attend(p_id uuid, p_val text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if lower(auth.jwt() ->> 'email') is distinct from 'whitewalkerofnorth@gmail.com' then
    raise exception 'Only the admin can set another player''s attendance';
  end if;
  update public.players
    set attend = p_val,
        group_name = case when p_val is distinct from 'yes' then null else group_name end
    where id = p_id;
end;
$$;

create or replace function public.admin_reset_players()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if lower(auth.jwt() ->> 'email') is distinct from 'whitewalkerofnorth@gmail.com' then
    raise exception 'Only the admin can reset players';
  end if;
  update public.players set attend = null, group_name = null;
end;
$$;

create or replace function public.admin_update_match_info(p_venue text default null, p_kickoff text default null)
returns public.match_info
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_row public.match_info;
begin
  if lower(auth.jwt() ->> 'email') is distinct from 'whitewalkerofnorth@gmail.com' then
    raise exception 'Only the admin can edit match info';
  end if;
  update public.match_info
    set venue = coalesce(p_venue, venue),
        kickoff_time = coalesce(p_kickoff, kickoff_time),
        updated_at = now()
    where id = 1
    returning * into updated_row;
  return updated_row;
end;
$$;

-- Self-registration when a user first logs in. Also goes through a
-- SECURITY DEFINER function, for the same reason as the admin actions
-- above: it works regardless of RLS/GRANT state, and it uses the same
-- "team" column detection so a brand-new user's very first login never
-- fails on that leftover column either.
create or replace function public.ensure_self_player(p_display_name text)
returns public.players
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_row public.players;
  new_row public.players;
  uid uuid := auth.uid();
  col record;
  cols text[] := array['user_id','display_name','attend','group_name'];
  vals text[] := array[quote_literal(uid::text) || '::uuid', quote_literal(trim(p_display_name)), 'null', 'null'];
  ins_sql text;
begin
  if uid is null then
    raise exception 'Not signed in';
  end if;

  select * into existing_row from public.players where user_id = uid limit 1;
  if found then
    -- Keep the display name in sync (e.g. the trigger above may have
    -- created this row with an email-derived name before the app ever
    -- ran; this corrects it to the app's authoritative name, "ARUN"
    -- included, without disturbing attend/group_name).
    if existing_row.display_name is distinct from trim(p_display_name) then
      update public.players
        set display_name = trim(p_display_name)
        where id = existing_row.id
        returning * into existing_row;
    end if;
    return existing_row;
  end if;

  -- Same auto-fill as admin_add_player: any other required column this
  -- table happens to have gets a safe blank value automatically.
  for col in
    select c.column_name, c.data_type
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'players'
      and c.is_nullable = 'no'
      and c.column_name not in ('id','user_id','display_name','attend','group_name','created_at')
  loop
    cols := cols || col.column_name;
    vals := vals || (case
      when col.data_type in ('character varying','text','character') then quote_literal('')
      when col.data_type = 'uuid' then 'gen_random_uuid()'
      when col.data_type = 'boolean' then 'false'
      when col.data_type in ('integer','bigint','smallint','numeric','real','double precision') then '0'
      else 'null'
    end);
  end loop;

  ins_sql := format('insert into public.players (%s) values (%s) returning *',
                     array_to_string(cols, ','), array_to_string(vals, ','));
  execute ins_sql into new_row;
  return new_row;
end;
$$;

grant execute on function public.admin_add_player(text, text) to authenticated;
grant execute on function public.admin_remove_player(uuid) to authenticated;
grant execute on function public.admin_set_group(uuid, text) to authenticated;
grant execute on function public.admin_set_attend(uuid, text) to authenticated;
grant execute on function public.admin_reset_players() to authenticated;
grant execute on function public.admin_update_match_info(text, text) to authenticated;
grant execute on function public.ensure_self_player(text) to authenticated;

-- 8. Auto-create a roster row the INSTANT an account is created — via a
--    trigger on auth.users itself, not app logic. This matters because
--    if email confirmation is turned on for this project, a brand-new
--    signup doesn't get signed in immediately, so the app's own
--    ensure_self_player call (which only runs after a real login) would
--    never fire until they confirm and log in. This trigger removes
--    that gap entirely: the row exists the moment the account does.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  col record;
  cols text[];
  vals text[];
  ins_sql text;
begin
  if exists (select 1 from public.players where user_id = new.id) then
    return new;
  end if;

  cols := array['user_id','display_name','attend','group_name'];
  vals := array[
    quote_literal(new.id::text) || '::uuid',
    quote_literal(coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1), 'Player')),
    'null',
    'null'
  ];

  for col in
    select c.column_name, c.data_type
    from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = 'players'
      and c.is_nullable = 'no'
      and c.column_name not in ('id','user_id','display_name','attend','group_name','created_at')
  loop
    cols := cols || col.column_name;
    vals := vals || (case
      when col.data_type in ('character varying','text','character') then quote_literal('')
      when col.data_type = 'uuid' then 'gen_random_uuid()'
      when col.data_type = 'boolean' then 'false'
      when col.data_type in ('integer','bigint','smallint','numeric','real','double precision') then '0'
      else 'null'
    end);
  end loop;

  ins_sql := format('insert into public.players (%s) values (%s)',
                     array_to_string(cols, ','), array_to_string(vals, ','));
  execute ins_sql;
  return new;
exception when others then
  -- Never let a roster-row hiccup block account creation itself.
  raise notice 'handle_new_user: skipped auto-creating a player row (%)', SQLERRM;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill: create rows for anyone who signed up BEFORE this trigger
-- existed (the trigger above only fires on new signups going forward).
-- Uses the same dynamic column-filling so it can't be blocked by any
-- legacy required column either.
do $$
declare
  u record;
  col record;
  cols text[];
  vals text[];
  ins_sql text;
begin
  for u in
    select au.id, au.email, au.raw_user_meta_data
    from auth.users au
    where not exists (select 1 from public.players p where p.user_id = au.id)
  loop
    cols := array['user_id','display_name','attend','group_name'];
    vals := array[
      quote_literal(u.id::text) || '::uuid',
      quote_literal(coalesce(u.raw_user_meta_data ->> 'display_name', split_part(u.email, '@', 1), 'Player')),
      'null',
      'null'
    ];

    for col in
      select c.column_name, c.data_type
      from information_schema.columns c
      where c.table_schema = 'public' and c.table_name = 'players'
        and c.is_nullable = 'no'
        and c.column_name not in ('id','user_id','display_name','attend','group_name','created_at')
    loop
      cols := cols || col.column_name;
      vals := vals || (case
        when col.data_type in ('character varying','text','character') then quote_literal('')
        when col.data_type = 'uuid' then 'gen_random_uuid()'
        when col.data_type = 'boolean' then 'false'
        when col.data_type in ('integer','bigint','smallint','numeric','real','double precision') then '0'
        else 'null'
      end);
    end loop;

    ins_sql := format('insert into public.players (%s) values (%s)',
                       array_to_string(cols, ','), array_to_string(vals, ','));
    execute ins_sql;
  end loop;
end $$;
