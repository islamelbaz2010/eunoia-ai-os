-- Phase 1: tenancy, auth profiles, and RBAC

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  industry_vertical text,
  locale_default text not null default 'en',
  status public.organization_status not null default 'pending_onboarding',
  trial_ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.users (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  email text not null unique,
  full_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.super_admins (
  user_id uuid primary key references public.users(id) on delete cascade,
  created_by uuid references public.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.organization_members (
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  role public.organization_role not null default 'viewer',
  invited_by uuid references public.users(id),
  joined_at timestamptz not null default now(),
  primary key (org_id, user_id)
);

create index if not exists idx_organizations_status on public.organizations(status);
create index if not exists idx_users_auth_user_id on public.users(auth_user_id);
create index if not exists idx_org_members_user on public.organization_members(user_id);
create index if not exists idx_org_members_org_role on public.organization_members(org_id, role);

alter table public.organizations enable row level security;
alter table public.users enable row level security;
alter table public.super_admins enable row level security;
alter table public.organization_members enable row level security;

create or replace function public.current_user_profile_id()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select id from public.users where auth_user_id = auth.uid()
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.super_admins sa
    join public.users u on u.id = sa.user_id
    where u.auth_user_id = auth.uid()
  )
$$;

create or replace function public.is_org_member(target_org_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select public.is_super_admin()
    or exists (
      select 1
      from public.organization_members om
      join public.users u on u.id = om.user_id
      where om.org_id = target_org_id
        and u.auth_user_id = auth.uid()
    )
$$;

create or replace function public.has_org_role(target_org_id uuid, allowed_roles public.organization_role[])
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select public.is_super_admin()
    or exists (
      select 1
      from public.organization_members om
      join public.users u on u.id = om.user_id
      where om.org_id = target_org_id
        and u.auth_user_id = auth.uid()
        and om.role = any(allowed_roles)
    )
$$;

drop policy if exists organizations_select_member on public.organizations;
create policy organizations_select_member
on public.organizations
for select
using (public.is_org_member(id));

drop policy if exists organizations_update_owner on public.organizations;
create policy organizations_update_owner
on public.organizations
for update
using (public.has_org_role(id, array['organization_owner']::public.organization_role[]))
with check (public.has_org_role(id, array['organization_owner']::public.organization_role[]));

drop policy if exists users_select_self_or_super on public.users;
create policy users_select_self_or_super
on public.users
for select
using (
  auth_user_id = auth.uid()
  or public.is_super_admin()
  or exists (
    select 1
    from public.organization_members om_self
    join public.organization_members om_other on om_other.org_id = om_self.org_id
    where om_self.user_id = public.current_user_profile_id()
      and om_other.user_id = users.id
  )
);

drop policy if exists users_update_self on public.users;
create policy users_update_self
on public.users
for update
using (auth_user_id = auth.uid())
with check (auth_user_id = auth.uid());

drop policy if exists super_admins_select_super on public.super_admins;
create policy super_admins_select_super
on public.super_admins
for select
using (public.is_super_admin());

drop policy if exists org_members_select_member on public.organization_members;
create policy org_members_select_member
on public.organization_members
for select
using (public.is_org_member(org_id));

drop policy if exists org_members_write_owner on public.organization_members;
create policy org_members_write_owner
on public.organization_members
for all
using (public.has_org_role(org_id, array['organization_owner']::public.organization_role[]))
with check (public.has_org_role(org_id, array['organization_owner']::public.organization_role[]));
