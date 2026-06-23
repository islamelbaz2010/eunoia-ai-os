-- Phase 1: AI assistant conversations, messages, and usage events

create table if not exists public.ai_conversations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid references public.users(id),
  title text,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ai_messages (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  conversation_id uuid not null references public.ai_conversations(id) on delete cascade,
  role public.ai_message_role not null,
  content text not null,
  provider text,
  model text,
  tokens_in integer not null default 0,
  tokens_out integer not null default 0,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create table if not exists public.usage_events (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid references public.users(id),
  event_type text not null,
  quantity numeric(12,4) not null default 1,
  provider text,
  model text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index if not exists idx_ai_conversations_org on public.ai_conversations(org_id, updated_at desc);
create index if not exists idx_ai_messages_conversation on public.ai_messages(org_id, conversation_id, created_at);
create index if not exists idx_usage_events_org_type on public.usage_events(org_id, event_type, created_at desc);

alter table public.ai_conversations enable row level security;
alter table public.ai_messages enable row level security;
alter table public.usage_events enable row level security;

drop policy if exists ai_conversations_select on public.ai_conversations;
create policy ai_conversations_select on public.ai_conversations for select using (public.is_org_member(org_id));
drop policy if exists ai_conversations_insert on public.ai_conversations;
create policy ai_conversations_insert on public.ai_conversations for insert with check (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[]));
drop policy if exists ai_conversations_update on public.ai_conversations;
create policy ai_conversations_update on public.ai_conversations for update using (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[])) with check (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[]));

drop policy if exists ai_messages_select on public.ai_messages;
create policy ai_messages_select on public.ai_messages for select using (public.is_org_member(org_id));
drop policy if exists ai_messages_insert on public.ai_messages;
create policy ai_messages_insert on public.ai_messages for insert with check (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[]));

drop policy if exists usage_events_select on public.usage_events;
create policy usage_events_select on public.usage_events for select using (public.is_org_member(org_id));
drop policy if exists usage_events_insert on public.usage_events;
create policy usage_events_insert on public.usage_events for insert with check (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[]));

