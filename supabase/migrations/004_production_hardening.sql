-- Production hardening updates:
-- 1) Verify enum labels used by edge function.
-- 2) Restrict quote image reads to owner folder.
-- 3) Add company pricing settings (tax/labor).

do $$
declare
  user_role_labels text[];
  estimate_status_labels text[];
  tier_type_name text;
  tier_labels text[];
begin
  select array_agg(e.enumlabel order by e.enumsortorder)
    into user_role_labels
  from pg_type t
  join pg_enum e on e.enumtypid = t.oid
  where t.typname = 'UserRole';

  if user_role_labels is null or not ('technician' = any(user_role_labels)) then
    raise exception 'Missing required enum label UserRole.technician';
  end if;

  select array_agg(e.enumlabel order by e.enumsortorder)
    into estimate_status_labels
  from pg_type t
  join pg_enum e on e.enumtypid = t.oid
  where t.typname = 'EstimateStatus';

  if estimate_status_labels is null or not ('draft' = any(estimate_status_labels)) then
    raise exception 'Missing required enum label EstimateStatus.draft';
  end if;

  select t.typname
    into tier_type_name
  from pg_type t
  where t.typtype = 'e'
    and exists (
      select 1
      from pg_enum e
      where e.enumtypid = t.oid
      group by e.enumtypid
      having bool_or(e.enumlabel = 'good')
         and bool_or(e.enumlabel = 'better')
         and bool_or(e.enumlabel = 'best')
    )
  limit 1;

  if tier_type_name is null then
    raise exception 'Could not find enum type containing good/better/best labels';
  end if;

  select array_agg(e.enumlabel order by e.enumsortorder)
    into tier_labels
  from pg_type t
  join pg_enum e on e.enumtypid = t.oid
  where t.typname = tier_type_name;

  if tier_labels is null
     or not ('good' = any(tier_labels))
     or not ('better' = any(tier_labels))
     or not ('best' = any(tier_labels)) then
    raise exception 'Tier enum must include good, better, best';
  end if;
end $$;

create table if not exists public.company_settings (
  id text primary key,
  labor_rate_per_hour numeric(10,2) not null default 95.00,
  tax_rate numeric(6,4) not null default 0.0800,
  updated_at timestamptz not null default now()
);

insert into public.company_settings (id, labor_rate_per_hour, tax_rate, updated_at)
values ('default', 95.00, 0.0800, now())
on conflict (id) do update set
  labor_rate_per_hour = excluded.labor_rate_per_hour,
  tax_rate = excluded.tax_rate,
  updated_at = now();

drop policy if exists "Authenticated users can read quote images" on storage.objects;
create policy "Authenticated users can read own quote images"
on storage.objects for select to authenticated
using (
  bucket_id = 'quote-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);
