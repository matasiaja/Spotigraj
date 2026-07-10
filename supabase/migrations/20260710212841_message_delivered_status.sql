-- Adds a "delivered" state between "sent" (row exists) and "read" (existing
-- `read` column) so chat bubbles can show three distinct ticks in the UI.
alter table public.messages add column delivered boolean not null default false;

-- Existing messages already visible to their recipients count as delivered
-- (and anything already marked read was, by definition, delivered first).
update public.messages set delivered = true where read = true;
