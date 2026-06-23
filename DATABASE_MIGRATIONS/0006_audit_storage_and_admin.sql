-- Phase 1: audit log, admin support, and storage notes

create table if not exists public.audit_log (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.organizations(id) on delete set null,
  actor_id uuid references public.users(id) on delete set null,
  actor_type text not null default 'user',
  action text not null,
  resource_type text not null,
  resource_id uuid,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create table if not exists public.rate_limit_events (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.organizations(id) on delete cascade,
  user_id uuid references public.users(id) on delete cascade,
  route_key text not null,
  window_start timestamptz not null,
  count integer not null default 1,
  created_at timestamptz not null default now(),
  unique (org_id, user_id, route_key, window_start)
);

create index if not exists idx_audit_log_org_created on public.audit_log(org_id, created_at desc);
create index if not exists idx_audit_log_resource on public.audit_log(resource_type, resource_id);
create index if not exists idx_rate_limit_events_lookup on public.rate_limit_events(org_id, user_id, route_key, window_start);

alter table public.audit_log enable row level security;
alter table public.rate_limit_events enable row level security;

drop policy if exists audit_log_select on public.audit_log;
create policy audit_log_select
on public.audit_log
for select
using (
  public.is_super_admin()
  or (
    org_id is not null
    and public.has_org_role(org_id, array['organization_owner','executive']::public.organization_role[])
  )
);

drop policy if exists audit_log_insert on public.audit_log;
create policy audit_log_insert
on public.audit_log
for insert
with check (
  public.is_super_admin()
  or (
    org_id is not null
    and public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[])
  )
);

drop policy if exists rate_limit_events_select_super on public.rate_limit_events;
create policy rate_limit_events_select_super on public.rate_limit_events for select using (public.is_super_admin());

drop policy if exists rate_limit_events_insert_member on public.rate_limit_events;
create policy rate_limit_events_insert_member on public.rate_limit_events for insert with check (org_id is null or public.is_org_member(org_id));

drop policy if exists rate_limit_events_update_member on public.rate_limit_events;
create policy rate_limit_events_update_member on public.rate_limit_events for update using (org_id is null or public.is_org_member(org_id)) with check (org_id is null or public.is_org_member(org_id));

-- Storage setup is usually executed through Supabase storage APIs.
-- If running with sufficient privileges, create the private knowledge bucket:
insert into storage.buckets (id, name, public)
values ('knowledge-documents', 'knowledge-documents', false)
on conflict (id) do nothing;

drop policy if exists "knowledge documents readable by org members" on storage.objects;
create policy "knowledge documents readable by org members"
on storage.objects
for select
using (
  bucket_id = 'knowledge-documents'
  and public.is_org_member((storage.foldername(name))[1]::uuid)
);

drop policy if exists "knowledge documents writable by analysts" on storage.objects;
create policy "knowledge documents writable by analysts"
on storage.objects
for insert
with check (
  bucket_id = 'knowledge-documents'
  and public.has_org_role((storage.foldername(name))[1]::uuid, array['organization_owner','executive','analyst']::public.organization_role[])
);

drop policy if exists "knowledge documents deletable by executives" on storage.objects;
create policy "knowledge documents deletable by executives"
on storage.objects
for delete
using (
  bucket_id = 'knowledge-documents'
  and public.has_org_role((storage.foldername(name))[1]::uuid, array['organization_owner','executive']::public.organization_role[])
);
