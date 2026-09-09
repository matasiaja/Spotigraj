-- ============================================================================
-- DRAFT — DO NOT RUN AS-IS. Needs index.html changes + testing in the live app.
-- Filename intentionally not in migration format so the CLI ignores it.
-- ============================================================================
--
-- Goal: honour the onboarding promise "numer telefonu pokazywany po matchu".
-- Today every authenticated user can read every profile's `phone` column.
--
-- Two legitimate ways a phone should be visible to someone else:
--   1. mutual like  (matches: both directions have action = 'like')
--   2. the owner set stand_by = true  (Zastępstwa / Stand-By: phone is broadcast
--      to all signed-in users on purpose, with a "Zadzwoń teraz" button)
--
-- Approach: stop exposing the raw column; serve phone through SECURITY DEFINER
-- functions that encode the rules above.

-- 1. Hide the column from the API roles (RLS is row-level; this is column-level).
revoke select (phone) on public.profiles from anon, authenticated;
-- NOTE: PostgREST needs the owner (postgres) to keep access; it does.
-- After this, `select ... , phone , ...` from the client returns 42501 and the
-- whole request fails, so every client read of phone MUST move to the RPCs below.

-- 2. One target's phone, only if caller is allowed to see it.
create or replace function public.get_contact_phone(target uuid)
returns text
language sql
security definer
set search_path = public
as $$
  select p.phone
  from public.profiles p
  where p.id = target
    and (
      p.stand_by is true
      or exists (
        select 1 from public.matches m1
        where m1.user_id = auth.uid() and m1.target_id = target and m1.action = 'like'
      ) and exists (
        select 1 from public.matches m2
        where m2.user_id = target and m2.target_id = auth.uid() and m2.action = 'like'
      )
    );
$$;
revoke execute on function public.get_contact_phone(uuid) from public;
grant execute on function public.get_contact_phone(uuid) to authenticated;

-- 3. Stand-By list including phone (replaces the phone column in the
--    loadZastepstwa() query at index.html:5644).
create or replace function public.get_standby_musicians()
returns table (id uuid, full_name text, role text, city text, genres text[],
               avatar_color text, phone text, status text, gender text)
language sql
security definer
set search_path = public
as $$
  select p.id, p.full_name, p.role, p.city, p.genres,
         p.avatar_color, p.phone, p.status, p.gender
  from public.profiles p
  where p.stand_by is true
    and p.id <> auth.uid()
    and p.id <> 'f32d66cc-6f00-4944-84f3-5658c4e3588f'::uuid;  -- SYSTEM_ACCOUNT_ID
$$;
revoke execute on function public.get_standby_musicians() from public;
grant execute on function public.get_standby_musicians() to authenticated;

-- ----------------------------------------------------------------------------
-- index.html changes required alongside this migration:
--
--   ~line 5644  loadZastepstwa():
--     - remove the sb.from('profiles').select('...,phone,...').eq('stand_by',true)
--     + const { data } = await sb.rpc('get_standby_musicians');
--
--   ~line 5731  (single profile phone lookup):
--     - sb.from('profiles').select('full_name,phone,role,gender').eq('id',userId)
--     + keep the name/role/gender select, drop phone; fetch phone separately:
--     + const { data: ph } = await sb.rpc('get_contact_phone', { target: userId });
--       (ph is null when caller isn't matched and target isn't stand_by)
--
--   ~line 4818  own-profile view: `p` is the caller's own row -> reads own phone.
--     After the column revoke this select (index.html:2618 / 2913 `select('*')`)
--     will 42501. Fix: those own-profile selects must enumerate columns instead
--     of '*', OR add a get_my_phone() helper. Simplest: change the 2-3
--     own-profile `select('*')` calls to an explicit column list that omits
--     phone, then load own phone via a get_my_phone() SECURITY DEFINER returning
--     (select phone from profiles where id = auth.uid()).
--
-- Test after deploy: (a) matched pair sees each other's phone, (b) unmatched
-- pair gets null, (c) stand_by musician's phone shows in Zastępstwa, (d) editing
-- own profile still shows/saves own phone, (e) anon gets nothing from /profiles.
