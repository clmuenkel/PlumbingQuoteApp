-- Brooks Plumbing tuning: company profile + residential/water-heater service refinement.

update public.company_settings
set
  company_name = 'Brooks Plumbing',
  company_phone = '(214) 368-3838',
  company_address = '627 E Walnut Cir, Garland, TX 75040',
  labor_rate_per_hour = 95.00,
  tax_rate = 0.0825,
  updated_at = now()
where id = 'default';

insert into public.company_settings (
  id, company_name, company_phone, company_address, labor_rate_per_hour, tax_rate, updated_at
)
values (
  'default', 'Brooks Plumbing', '(214) 368-3838', '627 E Walnut Cir, Garland, TX 75040', 95.00, 0.0825, now()
)
on conflict (id) do update set
  company_name = excluded.company_name,
  company_phone = excluded.company_phone,
  company_address = excluded.company_address,
  labor_rate_per_hour = excluded.labor_rate_per_hour,
  tax_rate = excluded.tax_rate,
  updated_at = now();

-- Add Brooks-specific sub-services that are common in residential fixture/water-heater work.
insert into public.industry_rates (
  id, category, subcategory, display_name, description,
  price_good, price_better, price_best,
  labor_hours_good, labor_hours_better, labor_hours_best,
  labor_rate_per_hour,
  warranty_months_good, warranty_months_better, warranty_months_best,
  solution_good, solution_better, solution_best,
  tags, source, source_urls, is_active, updated_at
)
values
(
  'ir_outdoor_faucet',
  'Fixtures',
  'Outdoor Faucet Replacement',
  'Outdoor Faucet Replacement',
  'Replace leaking or frozen exterior sillcock/hose bib with code-compliant freeze-resistant assembly.',
  150.00, 225.00, 350.00,
  0.9, 1.4, 2.2,
  95.00,
  3, 12, 24,
  'Replace damaged outdoor faucet only and confirm basic function.',
  'Replace outdoor faucet plus shutoff/supply refresh as needed, pressure test, and weather-seal penetration.',
  'Full exterior faucet upgrade with premium freeze-resistant hardware, valve/line correction, and extended reliability scope.',
  array['fixtures','outdoor','hose bib','sillcock','residential'],
  'brooks_residential_2026',
  array['https://brooksplumbingtexas.com/plumbing-fixture-repair-replacement'],
  true,
  now()
),
(
  'ir_showerhead_replace',
  'Fixtures',
  'Showerhead Replacement',
  'Showerhead Replacement',
  'Replace worn, corroded, or leaking showerhead and restore proper flow.',
  85.00, 150.00, 275.00,
  0.5, 0.9, 1.6,
  95.00,
  3, 12, 24,
  'Install standard showerhead and verify leak-free operation.',
  'Install upgraded showerhead, clean/repair threaded connection, and optimize spray/flow performance.',
  'Install premium showerhead with connection remediation, trim-level cleanup, and extended performance scope.',
  array['fixtures','shower','residential'],
  'brooks_residential_2026',
  array['https://brooksplumbingtexas.com/plumbing-fixture-repair-replacement'],
  true,
  now()
),
(
  'ir_wh_element_replace',
  'Water Heater',
  'Water Heater Element Replacement',
  'Water Heater Element Replacement',
  'Diagnose and replace failed electric water-heater heating element(s).',
  150.00, 225.00, 350.00,
  1.0, 1.7, 2.6,
  95.00,
  3, 12, 24,
  'Replace failed heating element and restore hot-water function.',
  'Replace element with full electrical/water-side verification and sediment impact check.',
  'Multi-component corrective scope (elements plus performance tuning/maintenance) for long-term reliability.',
  array['water heater','electric','element','residential'],
  'brooks_residential_2026',
  array['https://brooksplumbingtexas.com'],
  true,
  now()
),
(
  'ir_wh_thermostat_replace',
  'Water Heater',
  'Water Heater Thermostat Replacement',
  'Water Heater Thermostat Replacement',
  'Diagnose and replace faulty water-heater thermostat/control component.',
  125.00, 200.00, 325.00,
  0.9, 1.5, 2.4,
  95.00,
  3, 12, 24,
  'Replace faulty thermostat and restore standard temperature control.',
  'Replace thermostat/control with calibration and full operating verification.',
  'Expanded control-system corrective scope with related safety/performance checks.',
  array['water heater','thermostat','control','residential'],
  'brooks_residential_2026',
  array['https://brooksplumbingtexas.com'],
  true,
  now()
),
(
  'ir_wh_anode_rod',
  'Water Heater',
  'Water Heater Anode Rod Replacement',
  'Water Heater Anode Rod Replacement',
  'Replace sacrificial anode rod to reduce corrosion and extend tank life.',
  100.00, 175.00, 275.00,
  0.7, 1.2, 2.0,
  95.00,
  3, 12, 24,
  'Replace anode rod only and verify basic condition.',
  'Replace anode rod with corrosion inspection and minor corrective adjustments.',
  'Comprehensive anti-corrosion maintenance scope including anode replacement and related preventative items.',
  array['water heater','anode','maintenance','residential'],
  'brooks_residential_2026',
  array['https://brooksplumbingtexas.com'],
  true,
  now()
),
(
  'ir_wh_pressure_valve',
  'Water Heater',
  'Water Heater TPR Valve Replacement',
  'Water Heater TPR Valve Replacement',
  'Replace temperature-pressure relief valve and verify safe discharge path.',
  100.00, 175.00, 250.00,
  0.8, 1.3, 2.0,
  95.00,
  3, 12, 24,
  'Replace TPR valve and confirm leak-free operation.',
  'Replace TPR valve with discharge-line verification and safety-function checks.',
  'Full safety remediation scope including TPR/discharge compliance corrections and performance validation.',
  array['water heater','TPR','safety','residential'],
  'brooks_residential_2026',
  array['https://brooksplumbingtexas.com'],
  true,
  now()
)
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
  labor_rate_per_hour = excluded.labor_rate_per_hour,
  warranty_months_good = excluded.warranty_months_good,
  warranty_months_better = excluded.warranty_months_better,
  warranty_months_best = excluded.warranty_months_best,
  solution_good = excluded.solution_good,
  solution_better = excluded.solution_better,
  solution_best = excluded.solution_best,
  tags = excluded.tags,
  source = excluded.source,
  source_urls = excluded.source_urls,
  is_active = excluded.is_active,
  updated_at = now();

-- Make existing rows less generic and more specific to residential quoting context.
update public.industry_rates
set
  solution_good = concat(
    'Perform a focused ', lower(subcategory),
    ' scope to resolve the immediate customer concern using standard residential parts.'
  ),
  solution_better = concat(
    'Perform a full ', lower(subcategory),
    ' repair/replacement scope with root-cause correction, updated connectors/components where needed, and stronger warranty coverage.'
  ),
  solution_best = concat(
    'Deliver a premium ', lower(subcategory),
    ' solution with preventative upgrades, highest durability components, and long-term reliability focus.'
  ),
  source = coalesce(source, 'brooks_residential_2026'),
  updated_at = now()
where is_active = true;

-- Specialized wording for water-heater installation rows.
update public.industry_rates
set
  solution_good = 'Replace existing water heater with standard code-compliant installation and basic startup checks.',
  solution_better = 'Remove/dispose old water heater, install new unit with code-compliant connectors, expansion tank as required, permit/inspection coordination, and full performance verification.',
  solution_best = 'Premium installation scope with code upgrades, improved reliability components, optimization of delivery/recirculation context, and extended long-term protection.',
  updated_at = now()
where id in ('ir_wheater_tank_install', 'ir_wheater_tankless_install');
