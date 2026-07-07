-- Referral system replacing paid Premium: unique referral code per profile,
-- referral relationships with anti-fraud tracking, and earned-months ledger.
-- Does not touch existing Stripe/subscriptions logic.

-- 1. Referral code generator -------------------------------------------------
-- Excludes visually ambiguous characters: 0/O, 1/l/I.
create or replace function public.generate_referral_code()
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
    for i in 1..8 loop
      code := code || substr(chars, floor(random() * length(chars))::int + 1, 1);
    end loop;
    select exists(select 1 from public.profiles where referral_code = code) into code_exists;
    exit when not code_exists;
  end loop;
  return code;
end;
$$;

-- 2. profiles.referral_code ---------------------------------------------------
alter table public.profiles add column referral_code text;

-- Backfill existing rows one at a time (not a single bulk UPDATE) so each
-- collision check sees the codes already assigned earlier in this loop.
do $$
declare
  r record;
begin
  for r in select id from public.profiles where referral_code is null loop
    update public.profiles set referral_code = public.generate_referral_code() where id = r.id;
  end loop;
end $$;

alter table public.profiles alter column referral_code set not null;
alter table public.profiles add constraint profiles_referral_code_key unique (referral_code);
alter table public.profiles alter column referral_code set default public.generate_referral_code();

-- 3. referrals ----------------------------------------------------------------
create table public.referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_id uuid not null references public.profiles(id) on delete cascade,
  referred_user_id uuid not null unique references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  status text not null default 'pending' check (status in ('pending', 'active', 'expired')),
  activated_at timestamptz,
  ip_hash text,
  email_verified_at timestamptz,
  profile_completed_at timestamptz,
  first_relogin_at timestamptz,
  first_action_at timestamptz,
  constraint referrals_no_self_referral check (referrer_id <> referred_user_id)
);

create index referrals_referrer_id_idx on public.referrals(referrer_id);
create index referrals_status_idx on public.referrals(status);
create index referrals_ip_hash_idx on public.referrals(ip_hash);
-- referred_user_id is already indexed via its own UNIQUE constraint above.

alter table public.referrals enable row level security;

create policy "Users can view their own referrals"
  on public.referrals
  for select
  to authenticated
  using (auth.uid() = referrer_id or auth.uid() = referred_user_id);

-- No insert/update/delete policy for authenticated/anon: all writes happen
-- through service_role in an Edge Function, which bypasses RLS in Supabase.

-- 4. referral_credits ----------------------------------------------------------
create table public.referral_credits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  active_referrals_count integer not null default 0 check (active_referrals_count >= 0),
  total_months_earned integer not null default 0 check (total_months_earned >= 0),
  total_months_granted integer not null default 0 check (total_months_granted >= 0),
  updated_at timestamptz not null default now()
);

alter table public.referral_credits enable row level security;

create policy "Users can view their own referral credits"
  on public.referral_credits
  for select
  to authenticated
  using (auth.uid() = user_id);

-- No insert/update/delete policy for authenticated/anon: all writes happen
-- through service_role in an Edge Function, which bypasses RLS in Supabase.
