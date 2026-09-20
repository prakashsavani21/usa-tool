-- 10-day Share Bonus campaign: Sep 19–28, 2026 (Pacific Time)
-- 1st $500, 2nd $300, 3rd $200

alter table public.share_events
  add column if not exists campaign_key text not null default 'sep-2026';

create index if not exists share_events_campaign_email_idx
on public.share_events (campaign_key, lower(email));

alter table public.share_events enable row level security;

drop policy if exists "allow public share events" on public.share_events;
create policy "allow public share events"
on public.share_events
for insert
to anon
with check (
  campaign_key = 'sep-2026'
  and length(email) > 3
  and position('@' in email) > 1
  and length(platform) between 2 and 30
);

create or replace view public.share_leaderboard
as
select
  regexp_replace(lower(email), '^(.{2}).*(@.*)$', '\1***\2') as display_email,
  count(*)::bigint as share_count
from public.share_events
where campaign_key = 'sep-2026'
  and created_at >= timestamptz '2026-09-19 00:00:00-07'
  and created_at <  timestamptz '2026-09-29 00:00:00-07'
group by regexp_replace(lower(email), '^(.{2}).*(@.*)$', '\1***\2')
order by share_count desc, display_email asc;
