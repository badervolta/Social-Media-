-- Phase 0: shared data for the Volta Social Media Command Centre.
-- Every table has Row Level Security. Only signed-in Volta team members can read;
-- clients can never delete real data, read platform tokens, or send anything.
-- (Run once in the Supabase SQL editor. Safe to re-run.)

create schema if not exists private;

-- Team roles -------------------------------------------------------------
create table if not exists public.team_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  role text not null default 'member' check (role in ('admin','member')),
  created_at timestamptz not null default now()
);

create or replace function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.team_members(user_id, email) values (new.id, new.email)
  on conflict (user_id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();

-- Existing users become members; Bader is admin.
insert into public.team_members(user_id, email)
  select id, email from auth.users on conflict (user_id) do nothing;
update public.team_members set role = 'admin' where lower(email) = 'bader@voltaeffect.com';

create or replace function private.is_team_member() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.team_members where user_id = (select auth.uid()));
$$;
create or replace function private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.team_members where user_id = (select auth.uid()) and role = 'admin');
$$;
grant usage on schema private to authenticated;
grant execute on function private.is_team_member() to authenticated;
grant execute on function private.is_admin() to authenticated;

-- Interactions -----------------------------------------------------------
create table if not exists public.interactions (
  id uuid primary key default gen_random_uuid(),
  platform text not null check (platform in ('facebook','instagram','linkedin')),
  external_id text not null,
  type text not null,
  sender text not null,
  sender_meta text,
  context text,
  content text not null,
  received_at timestamptz not null default now(),
  priority text not null default 'info' check (priority in ('urgent','needs','info')),
  reason text,
  rule text,
  match text,
  intent text,
  flags jsonb not null default '[]'::jsonb,
  status text not null default 'new' check (status in ('new','followup','reviewed')),
  moderation text check (moderation in ('pending','kept','hide','escalated')),
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (platform, external_id)
);

-- Reply drafts (one per interaction). Approval is recorded with the approver.
create table if not exists public.reply_drafts (
  interaction_id uuid primary key references public.interactions(id) on delete cascade,
  body text not null,
  state text not null default 'draft' check (state in ('draft','edited','approved','sent')),
  variant int not null default 0,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  updated_by uuid references auth.users(id) default auth.uid(),
  updated_at timestamptz not null default now(),
  constraint approval_has_approver check (state <> 'approved' or (approved_by is not null and approved_at is not null))
);

-- Append-only history of who did what.
create table if not exists public.activity_log (
  id bigint generated always as identity primary key,
  interaction_id uuid references public.interactions(id) on delete cascade,
  actor uuid references auth.users(id) default auth.uid(),
  actor_email text,
  action text not null,
  at timestamptz not null default now()
);

-- Connection status only. Access tokens will live in Supabase Vault, never here.
create table if not exists public.connected_accounts (
  platform text primary key check (platform in ('facebook','instagram','linkedin')),
  account_name text,
  status text not null default 'not_connected' check (status in ('not_connected','connected','needs_reconnect','error')),
  connected_by_email text,
  connected_at timestamptz,
  expires_at timestamptz,
  last_sync_at timestamptz,
  last_error text
);
insert into public.connected_accounts(platform) values ('facebook'),('instagram'),('linkedin')
  on conflict (platform) do nothing;

create table if not exists public.digests (
  id bigint generated always as identity primary key,
  generated_at timestamptz not null default now(),
  generated_by uuid references auth.users(id) default auth.uid(),
  window_start timestamptz,
  window_end timestamptz,
  summary_text text
);

-- Row Level Security ------------------------------------------------------
alter table public.team_members enable row level security;
alter table public.interactions enable row level security;
alter table public.reply_drafts enable row level security;
alter table public.activity_log enable row level security;
alter table public.connected_accounts enable row level security;
alter table public.digests enable row level security;

revoke all on public.team_members, public.interactions, public.reply_drafts,
  public.activity_log, public.connected_accounts, public.digests from anon;

-- Signed-in users can only change workflow fields on an interaction, never its content.
revoke update on public.interactions from authenticated;
grant update (status, moderation, intent, updated_at) on public.interactions to authenticated;
-- The history can't be edited or removed from the browser.
revoke update, delete on public.activity_log from authenticated;
-- Connection status is written only by the server.
revoke insert, update, delete on public.connected_accounts from authenticated;

drop policy if exists "team reads team" on public.team_members;
create policy "team reads team" on public.team_members for select to authenticated
  using ((select private.is_team_member()));

drop policy if exists "team reads interactions" on public.interactions;
create policy "team reads interactions" on public.interactions for select to authenticated
  using ((select private.is_team_member()));
drop policy if exists "team updates interactions" on public.interactions;
create policy "team updates interactions" on public.interactions for update to authenticated
  using ((select private.is_team_member())) with check ((select private.is_team_member()));
-- Clients may only add or remove fictional demo rows. Real rows come from the server.
drop policy if exists "team adds demo rows" on public.interactions;
create policy "team adds demo rows" on public.interactions for insert to authenticated
  with check ((select private.is_team_member()) and is_demo);
drop policy if exists "admins remove demo rows" on public.interactions;
create policy "admins remove demo rows" on public.interactions for delete to authenticated
  using ((select private.is_admin()) and is_demo);

drop policy if exists "team reads drafts" on public.reply_drafts;
create policy "team reads drafts" on public.reply_drafts for select to authenticated
  using ((select private.is_team_member()));
drop policy if exists "team writes drafts" on public.reply_drafts;
create policy "team writes drafts" on public.reply_drafts for insert to authenticated
  with check ((select private.is_team_member()) and state <> 'sent'
              and (approved_by is null or approved_by = (select auth.uid())));
drop policy if exists "team edits drafts" on public.reply_drafts;
create policy "team edits drafts" on public.reply_drafts for update to authenticated
  using ((select private.is_team_member()) and state <> 'sent')
  with check ((select private.is_team_member()) and state <> 'sent'
              and (approved_by is null or approved_by = (select auth.uid())));

drop policy if exists "team reads log" on public.activity_log;
create policy "team reads log" on public.activity_log for select to authenticated
  using ((select private.is_team_member()));
drop policy if exists "team appends own log" on public.activity_log;
create policy "team appends own log" on public.activity_log for insert to authenticated
  with check ((select private.is_team_member()) and actor = (select auth.uid()));

drop policy if exists "team reads connections" on public.connected_accounts;
create policy "team reads connections" on public.connected_accounts for select to authenticated
  using ((select private.is_team_member()));

drop policy if exists "team reads digests" on public.digests;
create policy "team reads digests" on public.digests for select to authenticated
  using ((select private.is_team_member()));
drop policy if exists "team saves digests" on public.digests;
create policy "team saves digests" on public.digests for insert to authenticated
  with check ((select private.is_team_member()) and generated_by = (select auth.uid()));

create index if not exists interactions_received_at_idx on public.interactions (received_at desc);
create index if not exists activity_log_interaction_idx on public.activity_log (interaction_id, at);
