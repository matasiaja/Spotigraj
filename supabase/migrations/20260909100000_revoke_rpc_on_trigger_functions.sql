-- Security Advisor: "Public/Signed-In Users Can Execute SECURITY DEFINER Function"
-- These are trigger-only functions and should not be callable via /rest/v1/rpc.
-- Postgres does not check EXECUTE privilege when firing triggers, so revoking is safe.

revoke execute on function public.notify_match_push() from anon, authenticated;
revoke execute on function public.notify_message_push() from anon, authenticated;
revoke execute on function public.notify_user_email_verified() from anon, authenticated;
revoke execute on function public.create_referral_link_for_new_profile() from anon, authenticated;
revoke execute on function public.protect_is_premium() from anon, authenticated;

-- get_active_accounts_count() intentionally stays callable by anon (landing page counter).
