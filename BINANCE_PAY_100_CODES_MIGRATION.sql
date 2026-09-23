-- USA Free Tools — Binance Pay Mystery Box migration
-- Intended setup: 100 Binance Pay codes, each worth $100.
-- IMPORTANT: Keep actual codes server-side in Supabase; never put them in HTML/JS.
-- This migration is for a campaign that has NOT already initialized its mystery milestones.
-- It refuses to initialize if existing milestones are present.

-- 1) Allow $100 rewards. Existing rows are preserved.
alter table public.mystery_reward_codes
  drop constraint if exists mystery_reward_codes_reward_amount_check;

alter table public.mystery_reward_codes
  add constraint mystery_reward_codes_reward_amount_check
  check (reward_amount = 100);

-- 2) Initialize 100 random winning milestones from 1..100,000,
-- using 100 unused $100 Binance Pay codes.
create or replace function public.initialize_mystery_milestones()
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if exists (select 1 from public.mystery_box_milestones where campaign_id=1) then
    raise exception 'Mystery milestones are already initialized; do not reinitialize a live campaign';
  end if;

  if (select count(*) from public.mystery_reward_codes
      where claimed_at is null and reward_amount=100) < 100 then
    raise exception 'Add at least 100 unused $100 Binance Pay codes first';
  end if;

  with chosen_codes as (
    select id, row_number() over (order by id) rn
    from public.mystery_reward_codes
    where claimed_at is null and reward_amount=100
    order by id
    limit 100
  ),
  chosen_slots as (
    select milestone, row_number() over (order by random()) rn
    from generate_series(1,100000) as milestone
    order by random()
    limit 100
  )
  insert into public.mystery_box_milestones(campaign_id,reward_code_id,milestone)
  select 1, c.id, s.milestone
  from chosen_codes c
  join chosen_slots s using (rn);
end;
$$;

revoke all on function public.initialize_mystery_milestones() from public;

-- After inserting the 100 codes in Supabase Table Editor, run: 
-- select public.initialize_mystery_milestones();
