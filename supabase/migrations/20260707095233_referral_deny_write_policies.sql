-- Referral system, step 2: explicit deny policies for direct writes.
--
-- RLS + SELECT policies for `referrals` and `referral_credits` were already
-- defined in 20260707094214_referral_system.sql. With RLS enabled and no
-- permissive policy for a command, Postgres already denies that command —
-- these policies make that denial explicit and self-documenting in the
-- schema rather than relying on the absence of a policy.
--
-- service_role (used by Edge Functions) has BYPASSRLS in Supabase by
-- default, so none of this affects it: it can insert/update/delete freely.

-- 1. referrals ------------------------------------------------------------
create policy "Block direct inserts, service_role only"
  on public.referrals
  for insert
  to authenticated, anon
  with check (false);

create policy "Block direct updates, service_role only"
  on public.referrals
  for update
  to authenticated, anon
  using (false);

create policy "Block direct deletes, service_role only"
  on public.referrals
  for delete
  to authenticated, anon
  using (false);

-- 2. referral_credits -------------------------------------------------------
create policy "Block direct inserts, service_role only"
  on public.referral_credits
  for insert
  to authenticated, anon
  with check (false);

create policy "Block direct updates, service_role only"
  on public.referral_credits
  for update
  to authenticated, anon
  using (false);

create policy "Block direct deletes, service_role only"
  on public.referral_credits
  for delete
  to authenticated, anon
  using (false);
