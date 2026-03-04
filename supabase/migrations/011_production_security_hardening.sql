-- Production security hardening:
-- 1) lock down custom tables with RLS policies
-- 2) remove role escalation from auth trigger

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public."User" ("id", "authId", "name", "email", "role", "active", "createdAt", "updatedAt")
  values (
    concat('mob_', replace(new.id::text, '-', '')),
    new.id::text,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    new.email,
    'technician'::"UserRole",
    true,
    now(),
    now()
  )
  on conflict ("authId") do update
  set "email" = excluded."email",
      "name" = excluded."name",
      "updatedAt" = now();

  return new;
end;
$$;

alter table if exists public.company_settings enable row level security;
drop policy if exists company_settings_read_authenticated on public.company_settings;
create policy company_settings_read_authenticated
  on public.company_settings
  for select
  to authenticated
  using (true);

drop policy if exists company_settings_update_authenticated on public.company_settings;
create policy company_settings_update_authenticated
  on public.company_settings
  for update
  to authenticated
  using (true)
  with check (true);

alter table if exists public.industry_rates enable row level security;
drop policy if exists industry_rates_read_authenticated on public.industry_rates;
create policy industry_rates_read_authenticated
  on public.industry_rates
  for select
  to authenticated
  using (is_active = true);

alter table if exists public.error_logs enable row level security;
drop policy if exists error_logs_block_all_authenticated on public.error_logs;
create policy error_logs_block_all_authenticated
  on public.error_logs
  for all
  to authenticated
  using (false)
  with check (false);

alter table if exists public.competitor_pricing enable row level security;
drop policy if exists competitor_pricing_block_all_authenticated on public.competitor_pricing;
create policy competitor_pricing_block_all_authenticated
  on public.competitor_pricing
  for all
  to authenticated
  using (false)
  with check (false);

alter table if exists public.parts_catalog enable row level security;
drop policy if exists parts_catalog_block_all_authenticated on public.parts_catalog;
create policy parts_catalog_block_all_authenticated
  on public.parts_catalog
  for all
  to authenticated
  using (false)
  with check (false);

alter table if exists public.price_book_vectors enable row level security;
drop policy if exists price_book_vectors_block_all_authenticated on public.price_book_vectors;
create policy price_book_vectors_block_all_authenticated
  on public.price_book_vectors
  for all
  to authenticated
  using (false)
  with check (false);

alter table if exists public.pipeline_runs enable row level security;
drop policy if exists pipeline_runs_block_all_authenticated on public.pipeline_runs;
create policy pipeline_runs_block_all_authenticated
  on public.pipeline_runs
  for all
  to authenticated
  using (false)
  with check (false);

revoke execute on function public.match_price_book_vectors(extensions.vector, int) from public, anon, authenticated;
revoke execute on function public.match_parts_catalog(extensions.vector, int) from public, anon, authenticated;
revoke execute on function public.match_competitor_pricing(extensions.vector, int, text) from public, anon, authenticated;
