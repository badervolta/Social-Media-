-- Team-wide settings (one row). Everyone on the team can read; only admins can change.
create table if not exists public.app_settings (
  id int primary key default 1 check (id = 1),
  digest_hour int not null default 13 check (digest_hour between 0 and 23),
  digest_minute int not null default 0 check (digest_minute in (0, 15, 30, 45)),
  updated_by uuid references auth.users(id),
  updated_by_email text,
  updated_at timestamptz not null default now()
);
insert into public.app_settings (id) values (1) on conflict (id) do nothing;

alter table public.app_settings enable row level security;
revoke all on public.app_settings from anon;
revoke insert, delete on public.app_settings from authenticated;
revoke update on public.app_settings from authenticated;
grant update (digest_hour, digest_minute, updated_by, updated_by_email, updated_at) on public.app_settings to authenticated;

drop policy if exists "team reads settings" on public.app_settings;
create policy "team reads settings" on public.app_settings for select to authenticated
  using ((select private.is_team_member()));
drop policy if exists "admins change settings" on public.app_settings;
create policy "admins change settings" on public.app_settings for update to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()) and updated_by = (select auth.uid()));
