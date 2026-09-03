-- Licznik na landing page ma pokazywać liczbę kont, które zweryfikowały adres e-mail
-- (kliknęły link potwierdzający), a nie wszystkie zarejestrowane konta.
-- auth.users.email_confirmed_at przechodzi z null na wartość dokładnie w tym momencie
-- (patrz 20260711180000_notify_on_email_verified.sql).

create or replace view public.active_accounts_count as
select count(*) as count
from auth.users
where email_confirmed_at is not null;

-- CREATE OR REPLACE zachowuje istniejące grants, ale na wszelki wypadek
-- upewniamy się, że anon (landing page, publiczny klucz) nadal ma dostęp do odczytu.
grant select on public.active_accounts_count to anon;
grant select on public.active_accounts_count to authenticated;
