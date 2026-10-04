create or replace function app_private.compute_compatibility_scores()
returns table (
  candidate_user_id uuid,
  compatibility_score numeric,
  university_score numeric,
  budget_overlap_score numeric,
  cleanliness_score numeric,
  sleep_schedule_score numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  with current_student as (
    select
      u.user_id,
      u.university,
      p.budget_min_ghs,
      p.budget_max_ghs,
      p.cleanliness_score,
      p.sleep_schedule
    from public.users u
    join public.profiles p on p.user_id = u.user_id
    where u.user_id = (select auth.uid())
      and u.is_verified
  ),
  candidate_inputs as (
    select
      u.user_id as candidate_user_id,
      me.university as my_university,
      u.university as their_university,
      me.budget_min_ghs as my_budget_min,
      me.budget_max_ghs as my_budget_max,
      p.budget_min_ghs as their_budget_min,
      p.budget_max_ghs as their_budget_max,
      me.cleanliness_score as my_cleanliness,
      p.cleanliness_score as their_cleanliness,
      me.sleep_schedule as my_sleep_schedule,
      p.sleep_schedule as their_sleep_schedule
    from current_student me
    join public.users u on u.user_id <> me.user_id and u.is_verified
    join public.profiles p on p.user_id = u.user_id
  ),
  component_scores as (
    select
      candidate_user_id,
      case
        when nullif(btrim(my_university), '') is not null
         and nullif(btrim(their_university), '') is not null
        then case when lower(btrim(my_university)) = lower(btrim(their_university))
                  then 100::numeric else 0::numeric end
      end as university_score,
      case
        when my_budget_min is not null and my_budget_max is not null
         and their_budget_min is not null and their_budget_max is not null
        then case
          when greatest(my_budget_max, their_budget_max)
             = least(my_budget_min, their_budget_min)
          then 100::numeric
          else round(
            100::numeric * greatest(
              0::numeric,
              least(my_budget_max, their_budget_max)
                - greatest(my_budget_min, their_budget_min)
            ) / nullif(
              greatest(my_budget_max, their_budget_max)
                - least(my_budget_min, their_budget_min),
              0
            ),
            2
          )
        end
      end as budget_overlap_score,
      case
        when my_cleanliness is not null and their_cleanliness is not null
        then greatest(0::numeric, 100::numeric - abs(my_cleanliness - their_cleanliness) * 25)
      end as cleanliness_score,
      case
        when nullif(btrim(my_sleep_schedule), '') is not null
         and nullif(btrim(their_sleep_schedule), '') is not null
        then case when lower(btrim(my_sleep_schedule)) = lower(btrim(their_sleep_schedule))
                  then 100::numeric else 0::numeric end
      end as sleep_schedule_score
    from candidate_inputs
  ),
  weighted_scores as (
    select
      *,
      (case when university_score is not null then 35 else 0 end
       + case when budget_overlap_score is not null then 35 else 0 end
       + case when cleanliness_score is not null then 15 else 0 end
       + case when sleep_schedule_score is not null then 15 else 0 end) as available_weight,
      (coalesce(university_score, 0) * 35
       + coalesce(budget_overlap_score, 0) * 35
       + coalesce(cleanliness_score, 0) * 15
       + coalesce(sleep_schedule_score, 0) * 15) as weighted_total
    from component_scores
  )
  select
    candidate_user_id,
    case when available_weight > 0
         then round(weighted_total / available_weight, 2)
    end as compatibility_score,
    university_score,
    budget_overlap_score,
    cleanliness_score,
    sleep_schedule_score
  from weighted_scores
  order by compatibility_score desc nulls last, candidate_user_id;
$$;

revoke all on function app_private.compute_compatibility_scores() from public, anon, authenticated;
grant execute on function app_private.compute_compatibility_scores() to authenticated;

create or replace function public.get_compatibility_scores()
returns table (
  candidate_user_id uuid,
  compatibility_score numeric,
  university_score numeric,
  budget_overlap_score numeric,
  cleanliness_score numeric,
  sleep_schedule_score numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  select *
  from app_private.compute_compatibility_scores();
$$;

revoke all on function public.get_compatibility_scores() from public, anon, authenticated;
grant execute on function public.get_compatibility_scores() to authenticated;
