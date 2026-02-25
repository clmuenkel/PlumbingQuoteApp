-- Phase 1.5 status workflow, logging, and analytics

do $$
begin
  if exists (select 1 from pg_type where typname = 'EstimateStatus') then
    alter type "EstimateStatus" add value if not exists 'sent';
    alter type "EstimateStatus" add value if not exists 'accepted';
    alter type "EstimateStatus" add value if not exists 'rejected';
  end if;
end $$;

alter table if exists public.company_settings
  add column if not exists company_name text,
  add column if not exists company_phone text,
  add column if not exists company_address text,
  add column if not exists company_logo_url text;

update public.company_settings
set
  company_name = coalesce(company_name, 'PlumbQuote Services'),
  company_phone = coalesce(company_phone, ''),
  company_address = coalesce(company_address, ''),
  company_logo_url = coalesce(company_logo_url, ''),
  updated_at = now()
where id = 'default';

create table if not exists public.error_logs (
  id text primary key,
  source text not null,
  severity text not null,
  message text not null,
  context jsonb,
  device_info text,
  app_version text,
  created_at timestamptz not null default now()
);

create index if not exists idx_error_logs_created_at
  on public.error_logs (created_at desc);
create index if not exists idx_error_logs_source
  on public.error_logs (source);

create or replace view public.analytics_quote_summary as
select
  date_trunc('day', e."createdAt") as quote_date,
  count(*) as total_quotes,
  count(*) filter (where e.status::text = 'accepted') as accepted,
  count(*) filter (where e.status::text = 'sent') as sent,
  count(*) filter (where e.status::text = 'rejected') as rejected,
  round(avg(eo.total)::numeric, 2) as avg_quote_value,
  round(sum(eo.total) filter (where e.status::text = 'accepted')::numeric, 2) as accepted_revenue
from public."Estimate" e
left join public."EstimateOption" eo
  on eo."estimateId" = e.id and eo.recommended = true
group by 1
order by 1 desc;

create or replace view public.analytics_category_breakdown as
select
  coalesce(e."aiDiagnosisNote", 'Uncategorized') as category,
  count(*) as quote_count,
  round(avg(eo.total)::numeric, 2) as avg_value,
  count(*) filter (where e.status::text = 'accepted') as accepted_count
from public."Estimate" e
left join public."EstimateOption" eo
  on eo."estimateId" = e.id and eo.recommended = true
group by 1
order by 2 desc;

create or replace view public.analytics_technician_performance as
select
  u."name" as technician_name,
  count(*) as total_quotes,
  count(*) filter (where e.status::text = 'accepted') as accepted,
  round(
    100.0 * count(*) filter (where e.status::text = 'accepted') / nullif(count(*), 0),
    1
  ) as acceptance_rate,
  round(avg(eo.total)::numeric, 2) as avg_quote_value
from public."Estimate" e
join public."User" u on u.id = e."createdById"
left join public."EstimateOption" eo
  on eo."estimateId" = e.id and eo.recommended = true
group by 1
order by 3 desc;
