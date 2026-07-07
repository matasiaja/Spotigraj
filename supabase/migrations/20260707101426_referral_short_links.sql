-- Referral system, step 4: hidden short referral link.
-- 5-character short_id, structurally and visually unrelated to the
-- 8-character referral_code on profiles (own table, own generator, own alphabet
-- position/length) — not derived from or embedding referral_code in any way.
-- Frontend button and the short_id -> referrer_id resolver Edge Function are
-- out of scope for this migration.

-- 1. Short-id generator -------------------------------------------------------
-- Same ambiguous-character exclusions as generate_referral_code(): no 0/O, 1/l/I.
create or replace function public.generate_short_link_id()
returns text
language plpgsql
set search_path = public
as $$
declare
  chars text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  code text;
  i int;
  code_exists boolean;
begin
  loop
    code := '';
    for i in 1..5 loop
      code := code || substr(chars, floor(random() * length(chars))::int + 1, 1);
    end loop;
    select exists(select 1 from public.referral_links where short_id = code) into code_exists;
    exit when not code_exists;
  end loop;
  return code;
end;
$$;

-- 2. referral_links -------------------------------------------------------
create table public.referral_links (
  id uuid primary key default gen_random_uuid(),
  short_id text not null unique default public.generate_short_link_id(),
  referrer_id uuid not null unique references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  click_count integer not null default 0 check (click_count >= 0)
);
-- short_id and referrer_id are each already indexed via their UNIQUE constraints.

-- 3. Backfill: one row per existing profile ------------------------------------
-- Inserted one row at a time (not a single bulk INSERT ... SELECT) so each
-- collision check inside the default sees short_ids assigned earlier in this loop.
do $$
declare
  r record;
begin
  for r in select id from public.profiles loop
    insert into public.referral_links (referrer_id) values (r.id);
  end loop;
end $$;

-- 4. RLS -----------------------------------------------------------------
alter table public.referral_links enable row level security;

create policy "Users can view their own referral link"
  on public.referral_links
  for select
  to authenticated
  using (auth.uid() = referrer_id);

create policy "Block direct inserts, service_role only"
  on public.referral_links
  for insert
  to authenticated, anon
  with check (false);

create policy "Block direct updates, service_role only"
  on public.referral_links
  for update
  to authenticated, anon
  using (false);

-- Not explicitly requested, but added for consistency with the deny-policy
-- convention from step 2 (RLS already blocks this by default with no policy;
-- this just makes it explicit and auditable).
create policy "Block direct deletes, service_role only"
  on public.referral_links
  for delete
  to authenticated, anon
  using (false);
