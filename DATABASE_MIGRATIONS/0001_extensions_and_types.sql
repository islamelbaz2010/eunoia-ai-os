-- Phase 1: extensions and shared enum types

create extension if not exists "pgcrypto";
create extension if not exists "vector";

do $$
begin
  create type public.organization_status as enum (
    'pending_onboarding',
    'trialing',
    'active',
    'suspended',
    'canceled'
  );
exception
  when duplicate_object then null;
end $$;

do $$
begin
  create type public.organization_role as enum (
    'organization_owner',
    'executive',
    'analyst',
    'viewer'
  );
exception
  when duplicate_object then null;
end $$;

do $$
begin
  create type public.lead_status as enum (
    'new',
    'contacted',
    'qualified',
    'proposal',
    'won',
    'lost'
  );
exception
  when duplicate_object then null;
end $$;

do $$
begin
  create type public.activity_type as enum (
    'call',
    'email',
    'meeting',
    'whatsapp',
    'note',
    'task'
  );
exception
  when duplicate_object then null;
end $$;

do $$
begin
  create type public.kb_document_status as enum (
    'pending',
    'processing',
    'ready',
    'failed'
  );
exception
  when duplicate_object then null;
end $$;

do $$
begin
  create type public.ai_message_role as enum (
    'user',
    'assistant',
    'system'
  );
exception
  when duplicate_object then null;
end $$;

