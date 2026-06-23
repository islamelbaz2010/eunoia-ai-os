-- Phase 1: CRM contacts, leads, activities, and notes

create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  email text,
  phone text,
  locale text,
  source text,
  lifecycle_stage text not null default 'lead',
  custom_fields jsonb not null default '{}',
  created_by uuid references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.leads (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  contact_id uuid references public.contacts(id) on delete set null,
  name text not null,
  email text,
  phone text,
  source text,
  status public.lead_status not null default 'new',
  estimated_value numeric(12,2),
  currency text not null default 'USD',
  owner_id uuid references public.users(id),
  next_follow_up_at timestamptz,
  custom_fields jsonb not null default '{}',
  created_by uuid references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.activities (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  contact_id uuid references public.contacts(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete cascade,
  type public.activity_type not null,
  title text not null,
  payload jsonb not null default '{}',
  occurred_at timestamptz not null default now(),
  created_by uuid references public.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  contact_id uuid references public.contacts(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete cascade,
  body text not null,
  created_by uuid references public.users(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_contacts_org on public.contacts(org_id);
create index if not exists idx_contacts_org_email on public.contacts(org_id, email);
create index if not exists idx_contacts_lifecycle on public.contacts(org_id, lifecycle_stage);
create index if not exists idx_leads_org_status on public.leads(org_id, status);
create index if not exists idx_leads_follow_up on public.leads(org_id, next_follow_up_at);
create index if not exists idx_activities_org_created on public.activities(org_id, occurred_at desc);
create index if not exists idx_activities_contact on public.activities(contact_id, occurred_at desc);
create index if not exists idx_activities_lead on public.activities(lead_id, occurred_at desc);
create index if not exists idx_notes_contact on public.notes(contact_id, created_at desc);
create index if not exists idx_notes_lead on public.notes(lead_id, created_at desc);

alter table public.contacts enable row level security;
alter table public.leads enable row level security;
alter table public.activities enable row level security;
alter table public.notes enable row level security;

drop policy if exists contacts_select on public.contacts;
create policy contacts_select on public.contacts for select using (public.is_org_member(org_id));
drop policy if exists contacts_insert on public.contacts;
create policy contacts_insert on public.contacts for insert with check (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[]));
drop policy if exists contacts_update on public.contacts;
create policy contacts_update on public.contacts for update using (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[])) with check (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[]));
drop policy if exists contacts_delete on public.contacts;
create policy contacts_delete on public.contacts for delete using (public.has_org_role(org_id, array['organization_owner','executive']::public.organization_role[]));

drop policy if exists leads_select on public.leads;
create policy leads_select on public.leads for select using (public.is_org_member(org_id));
drop policy if exists leads_insert on public.leads;
create policy leads_insert on public.leads for insert with check (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[]));
drop policy if exists leads_update on public.leads;
create policy leads_update on public.leads for update using (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[])) with check (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[]));
drop policy if exists leads_delete on public.leads;
create policy leads_delete on public.leads for delete using (public.has_org_role(org_id, array['organization_owner','executive']::public.organization_role[]));

drop policy if exists activities_select on public.activities;
create policy activities_select on public.activities for select using (public.is_org_member(org_id));
drop policy if exists activities_insert on public.activities;
create policy activities_insert on public.activities for insert with check (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[]));

drop policy if exists notes_select on public.notes;
create policy notes_select on public.notes for select using (public.is_org_member(org_id));
drop policy if exists notes_insert on public.notes;
create policy notes_insert on public.notes for insert with check (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[]));

