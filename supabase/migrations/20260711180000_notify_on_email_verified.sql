-- Poprawka: powiadomienie mailowe ma iść nie przy samej rejestracji (INSERT do auth.users,
-- czyli przed potwierdzeniem maila), tylko dopiero gdy użytkownik zweryfikuje konto klikając
-- link potwierdzający (moment, gdy email_confirmed_at zmienia się z null na wartość).

drop trigger if exists on_auth_user_created_notify on auth.users;
drop function if exists public.notify_new_user_signup();

create or replace function public.notify_user_email_verified()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.email_confirmed_at is null and new.email_confirmed_at is not null then
    perform net.http_post(
      url := 'https://xjwbofgfdwivomvlppfm.supabase.co/functions/v1/notify-signup',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer sb_publishable__yBtwe_DMyYk8ZvuxtAhIw_WNr3zXIS'
      ),
      body := jsonb_build_object(
        'record', jsonb_build_object('email', new.email, 'created_at', new.email_confirmed_at)
      )
    );
  end if;
  return new;
end;
$$;

create trigger on_auth_user_email_verified_notify
after update on auth.users
for each row execute function public.notify_user_email_verified();
