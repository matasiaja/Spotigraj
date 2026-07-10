-- Admin broadcast announcements: lets a designated admin write ad-hoc
-- messages ("Wiadomość") shown once to every Spotigrajton, reusing the
-- one-shot modal pattern already used for the P4Z0 announcement.

-- 1. profiles.is_admin ---------------------------------------------------
alter table public.profiles add column is_admin boolean not null default false;

update public.profiles
set is_admin = true
where id = (select id from auth.users where email = 'info@mattsmok.art');

-- 2. announcements --------------------------------------------------------
create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  message text not null check (char_length(trim(message)) > 0),
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  active boolean not null default true
);

create index announcements_active_created_at_idx on public.announcements(active, created_at desc);

alter table public.announcements enable row level security;

create policy "Authenticated users can read active announcements"
  on public.announcements
  for select
  to authenticated
  using (active = true);

create policy "Admins can insert announcements"
  on public.announcements
  for insert
  to authenticated
  with check (
    exists (select 1 from public.profiles where id = auth.uid() and is_admin)
  );
