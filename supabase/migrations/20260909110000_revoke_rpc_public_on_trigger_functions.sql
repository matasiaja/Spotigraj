-- Follow-up to 20260909100000: the functions still had an EXECUTE grant to PUBLIC
-- (proacl entry `=X/postgres`), so anon/authenticated could still call them.
-- Revoke from PUBLIC as well. Triggers still fire (Postgres does not check
-- EXECUTE when firing a trigger function).

revoke execute on function public.notify_match_push() from public;
revoke execute on function public.notify_message_push() from public;
revoke execute on function public.notify_user_email_verified() from public;
revoke execute on function public.create_referral_link_for_new_profile() from public;
revoke execute on function public.protect_is_premium() from public;

-- Landing page counter: drop the blanket PUBLIC grant; anon/authenticated keep
-- their explicit grants so the landing RPC still works.
revoke execute on function public.get_active_accounts_count() from public;
