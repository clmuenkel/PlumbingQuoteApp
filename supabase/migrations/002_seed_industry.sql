-- Seed industry baseline rates and map to existing price book.

with seed_rates as (
  select * from (
    values
      ('ir_faucet_repair', 'Fixtures', 'Faucet Replacement', 'Faucet Replacement', 'Repair/replace leaking faucet and reconnect fittings', 215.00, 260.00, 340.00, 1.0, 1.2, 1.7, array['faucet','fixture','leak','replace']),
      ('ir_toilet_replacement', 'Fixtures', 'Toilet Replacement', 'Toilet Replacement', 'Replace toilet and reset seal/connection points', 345.00, 420.00, 525.00, 1.6, 2.0, 2.5, array['toilet','fixture','replace']),
      ('ir_disposal_replacement', 'Fixtures', 'Garbage Disposal Replacement', 'Garbage Disposal Replacement', 'Replace jammed or failed disposal unit', 320.00, 390.00, 495.00, 1.3, 1.6, 2.0, array['garbage','disposal','replace']),
      ('ir_kitchen_drain', 'Drain Services', 'Kitchen Drain Clearing', 'Kitchen Drain Clearing', 'Clear kitchen drain obstruction and restore flow', 145.00, 180.00, 225.00, 0.7, 0.9, 1.2, array['kitchen','drain','clog']),
      ('ir_main_drain', 'Drain Services', 'Main Drain Snaking', 'Main Drain Snaking', 'Snake main line and verify full drainage', 205.00, 250.00, 325.00, 1.3, 1.7, 2.2, array['main line','drain','snaking']),
      ('ir_hydro_jet', 'Drain Services', 'Hydro Jetting', 'Hydro Jetting', 'Hydro jet line to remove heavy buildup', 390.00, 480.00, 595.00, 2.1, 2.6, 3.2, array['drain','jetting','hydro']),
      ('ir_shutoff_valve', 'Pipe Repair', 'Shutoff Valve Replacement', 'Shutoff Valve Replacement', 'Replace failed shutoff valve with quarter-turn valve', 190.00, 230.00, 285.00, 1.0, 1.2, 1.6, array['shutoff','valve','pipe']),
      ('ir_pipe_leak', 'Pipe Repair', 'Pipe Leak Repair', 'Pipe Leak Repair', 'Repair leaking supply/drain section and pressure test', 245.00, 300.00, 395.00, 1.2, 1.6, 2.2, array['pipe','leak','repair']),
      ('ir_wheater_tank_install', 'Water Heater', 'Tank Water Heater Install', 'Tank Water Heater Install', 'Install tank water heater with connections and safety checks', 1550.00, 1900.00, 2450.00, 4.2, 5.2, 6.3, array['water heater','tank','install']),
      ('ir_wheater_tankless_install', 'Water Heater', 'Tankless Water Heater Install', 'Tankless Water Heater Install', 'Install tankless water heater and commission system', 2650.00, 3300.00, 4250.00, 6.7, 8.5, 10.5, array['water heater','tankless','install']),
      ('ir_wheater_flush', 'Water Heater', 'Water Heater Flush', 'Water Heater Flush', 'Perform full flush and preventive maintenance', 130.00, 160.00, 195.00, 0.8, 0.9, 1.1, array['water heater','flush','maintenance']),
      ('ir_emergency_leak', 'Emergency', 'Burst Pipe Emergency Response', 'Burst Pipe Emergency Response', 'Emergency response to active leak with stabilization and repair', 510.00, 620.00, 790.00, 1.8, 2.2, 2.9, array['emergency','burst','pipe','leak']),
      ('ir_emergency_overflow', 'Emergency', 'Overflow Emergency Response', 'Overflow Emergency Response', 'Emergency response for overflow event and immediate mitigation', 445.00, 540.00, 680.00, 1.6, 2.0, 2.5, array['emergency','overflow','toilet'])
  ) as t(id, category, subcategory, display_name, description, price_good, price_better, price_best, labor_hours_good, labor_hours_better, labor_hours_best, tags)
)
insert into public.industry_rates (
  id, category, subcategory, display_name, description,
  price_good, price_better, price_best,
  labor_hours_good, labor_hours_better, labor_hours_best,
  labor_rate_per_hour,
  warranty_months_good, warranty_months_better, warranty_months_best,
  solution_good, solution_better, solution_best,
  tags, source, is_active, updated_at
)
select
  id,
  category,
  subcategory,
  display_name,
  description,
  round(price_good, 2),
  round(price_better, 2),
  round(price_best, 2),
  round(labor_hours_good, 1),
  round(labor_hours_better, 1),
  round(labor_hours_best, 1),
  95.00,
  3, 12, 24,
  'Resolve immediate issue with standard parts and workmanship.',
  'Resolve root cause with upgraded parts and longer coverage.',
  'Future-proof solution with premium scope and maximum coverage.',
  tags,
  'Seeded from current price book + industry baseline',
  true,
  now()
from seed_rates
on conflict (id) do update set
  category = excluded.category,
  subcategory = excluded.subcategory,
  display_name = excluded.display_name,
  description = excluded.description,
  price_good = excluded.price_good,
  price_better = excluded.price_better,
  price_best = excluded.price_best,
  labor_hours_good = excluded.labor_hours_good,
  labor_hours_better = excluded.labor_hours_better,
  labor_hours_best = excluded.labor_hours_best,
  tags = excluded.tags,
  source = excluded.source,
  is_active = excluded.is_active,
  updated_at = now();

insert into public.industry_pricebook_map (
  id, industry_rate_id, price_book_item_id, price_book_category_id, fallback_line_item_name, is_required, quantity, tier_minimum, created_at
)
select
  concat('map_', ir.id, '_', pbi.id),
  ir.id,
  pbi.id,
  pbi."categoryId",
  pbi."name",
  true,
  1,
  null,
  now()
from public.industry_rates ir
join public."PriceBookItem" pbi
  on lower(pbi."name") = lower(ir.subcategory)
on conflict (id) do nothing;
