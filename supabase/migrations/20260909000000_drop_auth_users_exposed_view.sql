-- Security Advisor (krytyczne, reguła "auth_users_exposed"): każdy widok w schemacie
-- public, który odpytuje auth.users i ma nadane uprawnienia dla anon/authenticated,
-- jest traktowany jako luka bezpieczeństwa — niezależnie od tego, co dokładnie zwraca.
-- Winowajca: public.active_accounts_count (patrz
-- 20260903120000_active_accounts_count_verified_only.sql) — widok zwraca tylko COUNT,
-- ale sama możliwość odpytania go przez REST API z publicznym anon key i tak łamie tę
-- regułę linterową, bo technicznie ktoś mógłby podmienić definicję/dodać kolumny i
-- niepostrzeżenie zacząć zwracać więcej niż licznik.
--
-- Naprawa: ten sam licznik jako funkcja SECURITY DEFINER zamiast widoku. Funkcja
-- uruchamia się z uprawnieniami właściciela (który ma dostęp do auth.users), a anon
-- dostaje tylko prawo do jej WYWOŁANIA (RPC) — nie ma już żadnego obiektu w public,
-- który wprost odpytuje auth.users z uprawnieniami dla anon/authenticated, więc
-- Security Advisor przestaje to flagować.
create or replace function public.get_active_accounts_count()
returns integer
language sql
security definer
set search_path = public
as $$
  select (count(*))::integer
  from auth.users
  where email_confirmed_at is not null
    and id <> 'f32d66cc-6f00-4944-84f3-5658c4e3588f'::uuid;
$$;

grant execute on function public.get_active_accounts_count() to anon;
grant execute on function public.get_active_accounts_count() to authenticated;

drop view if exists public.active_accounts_count;
