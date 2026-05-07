-- Run this in Supabase SQL Editor
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text unique not null,
  display_name text,
  created_at timestamptz not null default now()
);

alter table public.profiles add column if not exists display_name text;
update public.profiles
set display_name = split_part(email, '@', 1)
where coalesce(trim(display_name), '') = '';

create table if not exists public.contacts (
  owner_id uuid not null references public.profiles(id) on delete cascade,
  contact_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, contact_id),
  constraint contacts_not_self check (owner_id <> contact_id)
);

create table if not exists public.chat_groups (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.group_members (
  group_id uuid not null references public.chat_groups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.banned_users (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  banned_by uuid not null references public.profiles(id) on delete cascade,
  reason text,
  banned_at timestamptz not null default now()
);

create table if not exists public.messages (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('dm','group')),
  dm_a uuid references public.profiles(id) on delete cascade,
  dm_b uuid references public.profiles(id) on delete cascade,
  group_id uuid references public.chat_groups(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  text text not null,
  created_at timestamptz not null default now(),
  constraint dm_shape check (
    (kind = 'dm' and dm_a is not null and dm_b is not null and group_id is null)
    or
    (kind = 'group' and group_id is not null and dm_a is null and dm_b is null)
  )
);

alter table public.messages add column if not exists status text not null default 'sent';
alter table public.messages add column if not exists read_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'messages_status_check'
      and conrelid = 'public.messages'::regclass
  ) then
    alter table public.messages
      add constraint messages_status_check check (status in ('sent', 'read'));
  end if;
end
$$;

update public.messages
set status = case when read_at is null then 'sent' else 'read' end
where status not in ('sent', 'read')
   or (read_at is not null and status <> 'read');

alter table public.profiles enable row level security;
alter table public.contacts enable row level security;
alter table public.chat_groups enable row level security;
alter table public.group_members enable row level security;
alter table public.banned_users enable row level security;
alter table public.messages enable row level security;

create or replace function public.is_admin_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = auth.uid()
      and lower(p.email) = 'cburdick28@brewstermadrid.com'
  );
$$;

grant execute on function public.is_admin_user() to authenticated;

create or replace function public.is_user_banned(target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.banned_users b
    where b.user_id = target_user_id
  );
$$;

grant execute on function public.is_user_banned(uuid) to authenticated;

drop policy if exists profiles_select_all on public.profiles;
create policy profiles_select_all on public.profiles
  for select to authenticated using (true);

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
  for insert to authenticated with check (id = auth.uid());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists contacts_select_owner on public.contacts;
create policy contacts_select_owner on public.contacts
  for select to authenticated using (owner_id = auth.uid() and not public.is_user_banned());

drop policy if exists contacts_insert_owner on public.contacts;
create policy contacts_insert_owner on public.contacts
  for insert to authenticated with check (owner_id = auth.uid() and not public.is_user_banned());

drop policy if exists chat_groups_select_all on public.chat_groups;
create policy chat_groups_select_all on public.chat_groups
  for select to authenticated using (not public.is_user_banned());

drop policy if exists chat_groups_insert_creator on public.chat_groups;
create policy chat_groups_insert_creator on public.chat_groups
  for insert to authenticated with check (created_by = auth.uid() and not public.is_user_banned());

drop policy if exists group_members_select_member on public.group_members;
create policy group_members_select_member on public.group_members
  for select to authenticated using (user_id = auth.uid() and not public.is_user_banned());

drop policy if exists group_members_insert_self on public.group_members;
create policy group_members_insert_self on public.group_members
  for insert to authenticated with check (user_id = auth.uid() and not public.is_user_banned());

drop policy if exists banned_users_select_admin on public.banned_users;
create policy banned_users_select_admin on public.banned_users
  for select to authenticated using (public.is_admin_user());

create or replace function public.can_invite_to_group(target_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.group_members gm
    where gm.group_id = target_group_id
      and gm.user_id = auth.uid()
  )
  and not exists (
    select 1
    from public.banned_users b
    where b.user_id = auth.uid()
  );
$$;

grant execute on function public.can_invite_to_group(uuid) to authenticated;

create or replace function public.ban_user(target_user_id uuid, ban_reason text default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    return false;
  end if;

  if target_user_id = auth.uid() then
    return false;
  end if;

  if exists (
    select 1
    from public.profiles p
    where p.id = target_user_id
      and lower(p.email) = 'cburdick28@brewstermadrid.com'
  ) then
    return false;
  end if;

  insert into public.banned_users (user_id, banned_by, reason)
  values (target_user_id, auth.uid(), nullif(trim(coalesce(ban_reason, '')), ''))
  on conflict (user_id)
  do update set
    banned_by = excluded.banned_by,
    reason = excluded.reason,
    banned_at = now();

  delete from public.group_members where user_id = target_user_id;
  delete from public.contacts where owner_id = target_user_id or contact_id = target_user_id;

  return true;
end;
$$;

grant execute on function public.ban_user(uuid, text) to authenticated;

drop policy if exists group_members_insert_by_member on public.group_members;
create policy group_members_insert_by_member on public.group_members
  for insert to authenticated
  with check (public.can_invite_to_group(group_id) and not public.is_user_banned());

create or replace function public.invite_to_group(target_group_id uuid, target_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_user_banned(target_user_id) then
    return false;
  end if;

  if not public.can_invite_to_group(target_group_id) then
    return false;
  end if;

  insert into public.group_members (group_id, user_id)
  values (target_group_id, target_user_id)
  on conflict (group_id, user_id) do nothing;

  return true;
end;
$$;

grant execute on function public.invite_to_group(uuid, uuid) to authenticated;

drop policy if exists messages_select_visible on public.messages;
create policy messages_select_visible on public.messages
  for select to authenticated using (
    not public.is_user_banned()
    and (
      public.is_admin_user()
      or
      (kind = 'dm' and auth.uid() in (dm_a, dm_b))
      or
      (kind = 'group' and exists (
        select 1 from public.group_members gm
        where gm.group_id = messages.group_id and gm.user_id = auth.uid()
      ))
    )
  );

drop policy if exists messages_insert_dm on public.messages;
create policy messages_insert_dm on public.messages
  for insert to authenticated with check (
    not public.is_user_banned()
    and
    kind = 'dm'
    and sender_id = auth.uid()
    and auth.uid() in (dm_a, dm_b)
  );

drop policy if exists messages_insert_group on public.messages;
create policy messages_insert_group on public.messages
  for insert to authenticated with check (
    not public.is_user_banned()
    and
    kind = 'group'
    and sender_id = auth.uid()
    and exists (
      select 1 from public.group_members gm
      where gm.group_id = messages.group_id and gm.user_id = auth.uid()
    )
  );

drop policy if exists messages_update_receipts on public.messages;
create policy messages_update_receipts on public.messages
  for update to authenticated
  using (
    not public.is_user_banned()
    and sender_id <> auth.uid()
    and (
      (kind = 'dm' and auth.uid() in (dm_a, dm_b))
      or
      (kind = 'group' and exists (
        select 1 from public.group_members gm
        where gm.group_id = messages.group_id and gm.user_id = auth.uid()
      ))
    )
  )
  with check (
    not public.is_user_banned()
    and sender_id <> auth.uid()
    and status = 'read'
    and read_at is not null
    and (
      (kind = 'dm' and auth.uid() in (dm_a, dm_b))
      or
      (kind = 'group' and exists (
        select 1 from public.group_members gm
        where gm.group_id = messages.group_id and gm.user_id = auth.uid()
      ))
    )
  );

drop policy if exists messages_delete_admin on public.messages;
create policy messages_delete_admin on public.messages
  for delete to authenticated using (public.is_admin_user());
