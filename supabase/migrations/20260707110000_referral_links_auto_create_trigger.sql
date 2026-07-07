-- Referral system, step 5: auto-create referral_links row for new profiles.
-- Migration 20260707101426 backfilled one row per EXISTING profile at the time,
-- but referrer_id has no default and RLS blocks client-side inserts (service_role
-- only) — any profile created after that migration got no referral_links row.
-- This trigger closes that gap going forward.

create or replace function public.create_referral_link_for_new_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.referral_links (referrer_id) values (new.id)
  on conflict (referrer_id) do nothing;
  return new;
end;
$$;

create trigger trg_create_referral_link_for_new_profile
  after insert on public.profiles
  for each row
  execute function public.create_referral_link_for_new_profile();

-- Backfill any profiles created in the gap between the two migrations.
insert into public.referral_links (referrer_id)
select p.id from public.profiles p
left join public.referral_links l on l.referrer_id = p.id
where l.referrer_id is null;
