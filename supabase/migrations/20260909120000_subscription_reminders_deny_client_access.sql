-- subscription_reminders is a server-only bookkeeping table: it is written by the
-- subscription-reminder cron/edge function via service_role (which bypasses RLS),
-- and clients must never read or write it.
--
-- It already had RLS enabled with no policies (= deny all), which is the correct
-- state. This adds an explicit deny-all policy to document that intent and to
-- clear the Security Advisor "RLS Enabled No Policy" suggestion.

create policy "No client access" on public.subscription_reminders
  for all to anon, authenticated
  using (false) with check (false);
