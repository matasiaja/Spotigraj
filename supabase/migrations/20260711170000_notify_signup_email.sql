-- Wysyła powiadomienie mailowe (przez edge function notify-signup) za każdym razem,
-- gdy w auth.users pojawi się nowy zarejestrowany użytkownik.

create extension if not exists pg_net with schema extensions;

create or replace function public.notify_new_user_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://xjwbofgfdwivomvlppfm.supabase.co/functions/v1/notify-signup',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer sb_publishable__yBtwe_DMyYk8ZvuxtAhIw_WNr3zXIS'
    ),
    body := jsonb_build_object(
      'record', jsonb_build_object('email', new.email, 'created_at', new.created_at)
    )
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_notify on auth.users;

create trigger on_auth_user_created_notify
after insert on auth.users
for each row execute function public.notify_new_user_signup();
