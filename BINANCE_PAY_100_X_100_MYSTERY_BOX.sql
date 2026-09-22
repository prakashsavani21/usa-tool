-- USA Free Tools — Binance Pay Mystery Box migration
-- 100 winners × $100 = $10,000 total voucher value
-- 100,000 global openings; 3 chances per email per UTC day.
-- Winning positions are stored server-side and are never exposed by the public status RPC.

begin;

-- Allow the new $100 reward value.
alter table public.mystery_reward_codes drop constraint if exists mystery_reward_codes_reward_amount_check;
alter table public.mystery_reward_codes
  add constraint mystery_reward_codes_reward_amount_check
  check (reward_amount = 100);

-- Remove unused old Amazon-style $1/$2/$5 reward inventory.
delete from public.mystery_reward_codes
where claimed_at is null and reward_amount <> 100;

-- 100 server-side winning opening positions.
create table if not exists public.mystery_box_winning_positions (
  click_number bigint primary key check (click_number between 1 and 100000),
  reward_amount numeric(10,2) not null default 100 check (reward_amount = 100),
  claimed_at timestamptz,
  claimed_by text,
  reward_code_id bigint references public.mystery_reward_codes(id),
  created_at timestamptz not null default now()
);

alter table public.mystery_box_winning_positions enable row level security;
revoke all on public.mystery_box_winning_positions from anon, authenticated;

-- Generate 100 unique future winning positions.
-- If the campaign has already recorded a few test openings, positions are chosen after the current counter.
delete from public.mystery_box_winning_positions;
insert into public.mystery_box_winning_positions (click_number)
select click_number
from (
  select gs as click_number
  from generate_series(
    greatest(1, (select total_clicks + 1 from public.mystery_box_campaign where id = 1)),
    100000
  ) gs
  order by random()
  limit 100
) s;

-- Replace the claim RPC with the 100 × $100 logic.
drop function if exists public.claim_mystery_box(text);

create or replace function public.claim_mystery_box(p_email text)
returns table (
  won boolean,
  reward_amount numeric,
  reward_code text,
  click_number bigint,
  total_clicks bigint,
  max_clicks bigint,
  attempts_left integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(p_email));
  v_today date := (now() at time zone 'UTC')::date;
  v_campaign_total bigint;
  v_campaign_max bigint;
  v_campaign_active boolean;
  v_attempt_no integer;
  v_click bigint;
  v_reward_id bigint;
  v_reward_code text;
  v_attempts_left integer;
  v_position_id bigint;
begin
  if length(v_email) < 5 or position('@' in v_email) < 2 then
    raise exception 'Please enter a valid email address';
  end if;

  select c.total_clicks, c.max_clicks, c.active
    into v_campaign_total, v_campaign_max, v_campaign_active
  from public.mystery_box_campaign c
  where c.id = 1
  for update;

  if not found then raise exception 'Mystery Box campaign not found'; end if;
  if not v_campaign_active or v_campaign_total >= v_campaign_max then
    raise exception 'Mystery Box campaign is complete';
  end if;

  select count(*)::integer into v_attempt_no
  from public.mystery_box_attempts a
  where a.campaign_id = 1 and a.email = v_email and a.attempt_date = v_today;

  if v_attempt_no >= 3 then
    raise exception 'You have used all 3 Mystery Box chances today';
  end if;
  v_attempt_no := v_attempt_no + 1;
  v_click := v_campaign_total + 1;

  update public.mystery_box_campaign c
  set total_clicks = v_click,
      active = case when v_click >= c.max_clicks then false else c.active end
  where c.id = 1;

  -- Claim the winning position atomically if this click is one of the 100 winners.
  select wp.click_number into v_position_id
  from public.mystery_box_winning_positions wp
  where wp.click_number = v_click and wp.claimed_at is null
  for update;

  if v_position_id is not null then
    select r.id, r.reward_code into v_reward_id, v_reward_code
    from public.mystery_reward_codes r
    where r.reward_amount = 100 and r.claimed_at is null
    order by r.id
    limit 1
    for update;

    if v_reward_id is null then
      raise exception 'A $100 Binance Pay voucher is not available for this winner';
    end if;

    update public.mystery_reward_codes r
    set claimed_at = now(), claimed_by = v_email
    where r.id = v_reward_id;

    update public.mystery_box_winning_positions wp
    set claimed_at = now(), claimed_by = v_email, reward_code_id = v_reward_id
    where wp.click_number = v_click;
  end if;

  insert into public.mystery_box_attempts(campaign_id,email,attempt_date,attempt_no,click_number)
  values(1,v_email,v_today,v_attempt_no,v_click);

  v_attempts_left := 3 - v_attempt_no;

  return query
  select
    (v_reward_id is not null),
    case when v_reward_id is not null then 100::numeric else null::numeric end,
    v_reward_code,
    v_click,
    v_click,
    v_campaign_max,
    v_attempts_left;
end;
$$;

grant execute on function public.claim_mystery_box(text) to anon, authenticated;

commit;

-- AFTER running this migration, insert your 100 real Binance Pay voucher codes:
-- insert into public.mystery_reward_codes (reward_amount, reward_code) values
-- (100,'PASTE_CODE_001'), (100,'PASTE_CODE_002'), ... (100,'PASTE_CODE_100');
