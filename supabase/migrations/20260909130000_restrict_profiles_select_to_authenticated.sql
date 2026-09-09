-- SECURITY: public.profiles was readable by the `anon` role.
--
-- Policy `profiles_select` was `USING (true)` with no role restriction, so it
-- applied to `anon` too. Combined with the table-level SELECT grant to `anon`,
-- anyone holding the public anon key (embedded in the app JS / landing page)
-- could run:
--
--   GET /rest/v1/profiles?select=full_name,phone,city,bio,gender,nationality
--
-- and download every profile row. At the time this was written that was
-- 46 profiles, 38 of them with a phone number.
--
-- Verified with `set role anon; select count(*), count(phone) from profiles;`
-- -> 46 rows / 38 phones visible.
--
-- Fix: restrict the read policy to signed-in users. Every profiles read in
-- index.html is already gated on an authenticated session; landing.html only
-- calls get_active_accounts_count() and never touches profiles.
--
-- This does NOT yet address phone visibility *between* signed-in users (see
-- 20260909140000 sketch): the onboarding copy promises "telefon pokazywany po
-- matchu" but any authenticated user can still read any phone. The Zastępstwa /
-- Stand-By feature intentionally broadcasts phone to all signed-in users, so
-- that refinement needs a product decision.

alter policy "profiles_select" on public.profiles to authenticated;

-- Optional hardening: drop the unused write grants to anon (RLS already blocks
-- the rows, but there is no reason for anon to hold these table privileges).
revoke insert, update, delete, truncate on public.profiles from anon;
