-- Phase 1: knowledge base and vector search

create table if not exists public.kb_documents (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  source_type text not null default 'upload',
  title text not null,
  storage_bucket text,
  storage_path text,
  mime_type text,
  file_size_bytes bigint,
  status public.kb_document_status not null default 'pending',
  error_message text,
  created_by uuid references public.users(id),
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.kb_chunks (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null references public.kb_documents(id) on delete cascade,
  chunk_index integer not null,
  content text not null,
  token_count integer,
  embedding vector(1536),
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (document_id, chunk_index)
);

create index if not exists idx_kb_documents_org on public.kb_documents(org_id, created_at desc);
create index if not exists idx_kb_documents_status on public.kb_documents(status, created_at);
create index if not exists idx_kb_chunks_org_document on public.kb_chunks(org_id, document_id);
create index if not exists idx_kb_chunks_embedding_hnsw on public.kb_chunks using hnsw (embedding vector_cosine_ops);

alter table public.kb_documents enable row level security;
alter table public.kb_chunks enable row level security;

drop policy if exists kb_documents_select on public.kb_documents;
create policy kb_documents_select on public.kb_documents for select using (public.is_org_member(org_id));
drop policy if exists kb_documents_insert on public.kb_documents;
create policy kb_documents_insert on public.kb_documents for insert with check (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[]));
drop policy if exists kb_documents_update on public.kb_documents;
create policy kb_documents_update on public.kb_documents for update using (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[])) with check (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[]));
drop policy if exists kb_documents_delete on public.kb_documents;
create policy kb_documents_delete on public.kb_documents for delete using (public.has_org_role(org_id, array['organization_owner','executive']::public.organization_role[]));

drop policy if exists kb_chunks_select on public.kb_chunks;
create policy kb_chunks_select on public.kb_chunks for select using (public.is_org_member(org_id));
drop policy if exists kb_chunks_insert on public.kb_chunks;
create policy kb_chunks_insert on public.kb_chunks for insert with check (public.has_org_role(org_id, array['organization_owner','executive','analyst']::public.organization_role[]));
drop policy if exists kb_chunks_delete on public.kb_chunks;
create policy kb_chunks_delete on public.kb_chunks for delete using (public.has_org_role(org_id, array['organization_owner','executive']::public.organization_role[]));

create or replace function public.match_kb_chunks(
  query_embedding vector(1536),
  match_org_id uuid,
  match_count integer default 5
)
returns table (
  id uuid,
  document_id uuid,
  content text,
  similarity double precision,
  metadata jsonb
)
language sql
stable
as $$
  select
    kc.id,
    kc.document_id,
    kc.content,
    1 - (kc.embedding <=> query_embedding) as similarity,
    kc.metadata
  from public.kb_chunks kc
  where kc.org_id = match_org_id
    and public.is_org_member(kc.org_id)
    and kc.embedding is not null
  order by kc.embedding <=> query_embedding
  limit least(match_count, 20)
$$;

