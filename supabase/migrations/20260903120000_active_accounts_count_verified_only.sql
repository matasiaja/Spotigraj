-- Licznik na landing page ma pokazywać liczbę kont, które zweryfikowały adres e-mail
-- (kliknęły link potwierdzający), a nie kont z uzupełnionym profilem (rola + miasto).
-- auth.users.email_confirmed_at przechodzi z null na wartość dokładnie w tym momencie
-- (patrz 20260711180000_notify_on_email_verified.sql).
--
-- Poprzednia definicja (dla historii):
--   SELECT (count(*))::integer AS count
--   FROM profiles
--   WHERE ((role IS NOT NULL) AND (city IS NOT NULL)
--          AND (id <> 'f32d66cc-6f00-4944-84f3-5658c4e3588f'::uuid));
-- Wykluczenie konta f32d66cc-6f00-4944-84f3-5658c4e3588f (testowe/wewnętrzne)
-- zostaje — to zasada niezależna od tego, jaką metrykę liczymy.

create or replace view public.active_accounts_count as
select (count(*))::integer as count
from auth.users
where email_confirmed_at is not null
  and id <> 'f32d66cc-6f00-4944-84f3-5658c4e3588f'::uuid;

-- CREATE OR REPLACE zachowuje istniejące grants, ale na wszelki wypadek
-- upewniamy się, że anon (landing page, publiczny klucz) nadal ma dostęp do odczytu.
grant select on public.active_accounts_count to anon;
grant select on public.active_accounts_count to authenticated;
