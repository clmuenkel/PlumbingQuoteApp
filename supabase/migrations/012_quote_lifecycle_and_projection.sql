-- Track customer lifecycle events and enrich analytics with forecast metrics.

alter table "Estimate"
  add column if not exists "viewedAt" timestamptz;

drop view if exists analytics_quote_summary;

create or replace view analytics_quote_summary as
with base as (
  select
    date_trunc('day', e."createdAt") as quote_date,
    e.status::text as status,
    e."viewedAt" as viewed_at,
    eo.total as option_total
  from "Estimate" e
  left join lateral (
    select total
    from "EstimateOption" eo
    where eo."estimateId" = e.id and eo.recommended = true
    limit 1
  ) eo on true
),
historical as (
  select
    case
      when count(*) filter (where status in ('sent', 'accepted', 'rejected')) = 0 then 0::numeric
      else
        count(*) filter (where status = 'accepted')::numeric
        / nullif(count(*) filter (where status in ('sent', 'accepted', 'rejected')), 0)::numeric
    end as acceptance_rate
  from base
)
select
  b.quote_date,
  count(*) as total_quotes,
  count(*) filter (where b.status = 'accepted') as accepted,
  count(*) filter (where b.status = 'sent') as sent,
  count(*) filter (where b.status = 'rejected') as rejected,
  count(*) filter (where b.viewed_at is not null) as viewed,
  round(avg(b.option_total)::numeric, 2)::double precision as avg_quote_value,
  round(sum(case when b.status = 'accepted' then coalesce(b.option_total, 0) else 0 end)::numeric, 2)::double precision as accepted_revenue,
  round(sum(case when b.status = 'sent' then coalesce(b.option_total, 0) else 0 end)::numeric, 2)::double precision as pending_sent_value,
  round((
    sum(case when b.status = 'accepted' then coalesce(b.option_total, 0) else 0 end)
    + (sum(case when b.status = 'sent' then coalesce(b.option_total, 0) else 0 end) * h.acceptance_rate)
  )::numeric, 2)::double precision as projected_revenue
from base b
cross join historical h
group by b.quote_date, h.acceptance_rate
order by b.quote_date desc;
