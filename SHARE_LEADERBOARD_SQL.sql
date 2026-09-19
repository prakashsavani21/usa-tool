create table if not exists share_events (
  id bigint generated always as identity primary key,
  email text not null,
  platform text not null,
  created_at timestamptz not null default now()
);

create index if not exists share_events_email_idx
on share_events (lower(email));

alter table share_events enable row level security;

drop policy if exists "allow public share events" on share_events;
create policy "allow public share events"
on share_events
for insert
to anon
with check (length(email) > 3 and position('@' in email) > 1);

create or replace view share_leaderboard
with (display_email, share_count)
as
select
  regexp_replace(lower(email), '^(.{2}).*(@.*)$', '\1***\2') as display_email,
  count(*)::bigint as share_count
from share_events
group by regexp_replace(lower(email), '^(.{2}).*(@.*)$', '\1***\2')
order by share_count desc;
