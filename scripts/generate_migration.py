#!/usr/bin/env python3
"""
Normalize scraped pricing data into industry_rates upsert migration.

Input:
  scripts/scraped_pricing_raw.json

Output:
  supabase/migrations/006_industry_rates_2026.sql
"""

from __future__ import annotations

import json
import re
import statistics
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW_PATH = PROJECT_ROOT / "scripts" / "scraped_pricing_raw.json"
OUT_SQL = PROJECT_ROOT / "supabase" / "migrations" / "006_industry_rates_2026.sql"
BASELINE_SEED = PROJECT_ROOT / "supabase" / "migrations" / "002_seed_industry.sql"


SOURCE_WEIGHTS = {
    "angi": 0.40,
    "homeguide": 0.35,
    "housecallpro": 0.25,
}

CATEGORY_HOUR_FACTORS = {
    "Fixtures": 0.6,
    "Drain Services": 0.7,
    "Pipe Repair": 0.8,
    "Water Heater": 1.0,
    "Pump Services": 0.8,
    "Emergency": 0.9,
    "Inspection": 0.5,
    "Septic": 0.9,
}


@dataclass
class ServiceSpec:
    id: str
    category: str
    subcategory: str
    display_name: str
    description: str
    tags: list[str]
    aliases: list[str]


SERVICE_SPECS: list[ServiceSpec] = [
    ServiceSpec("ir_faucet_repair", "Fixtures", "Faucet Replacement", "Faucet Replacement", "Repair or replace leaking faucet and reconnect fittings", ["faucet", "fixture", "leak", "replace"], ["faucet installation", "faucet replacement", "faucet or fixture install", "faucet and fixture replacement"]),
    ServiceSpec("ir_toilet_replacement", "Fixtures", "Toilet Replacement", "Toilet Replacement", "Replace toilet and reset seals and water connection points", ["toilet", "fixture", "replace"], ["toilet installation", "toilet replacement"]),
    ServiceSpec("ir_disposal_replacement", "Fixtures", "Garbage Disposal Replacement", "Garbage Disposal Replacement", "Replace jammed or failed garbage disposal unit", ["garbage", "disposal", "replace"], ["garbage disposal install", "garbage disposal replacement", "cost to install a garbage disposal"]),
    ServiceSpec("ir_kitchen_drain", "Drain Services", "Kitchen Drain Clearing", "Kitchen Drain Clearing", "Clear kitchen drain obstruction and restore normal flow", ["kitchen", "drain", "clog"], ["drain clearing", "unclog a sink", "cost to unclog a drain", "sink/tub"]),
    ServiceSpec("ir_main_drain", "Drain Services", "Main Drain Snaking", "Main Drain Snaking", "Snake main line and verify full drainage restoration", ["main line", "drain", "snaking"], ["main drain snaking", "main sewer line cleaning", "sewer line cleaning"]),
    ServiceSpec("ir_hydro_jet", "Drain Services", "Hydro Jetting", "Hydro Jetting", "Hydro-jet line to remove heavy scale and buildup", ["drain", "jetting", "hydro"], ["hydro jet", "hydro-jet", "high pressure jet"]),
    ServiceSpec("ir_shutoff_valve", "Pipe Repair", "Shutoff Valve Replacement", "Shutoff Valve Replacement", "Replace failed shutoff valve with quarter-turn valve", ["shutoff", "valve", "pipe"], ["main water shut-off valve", "shut-off valve replacement", "water shut off valve replacement"]),
    ServiceSpec("ir_pipe_leak", "Pipe Repair", "Pipe Leak Repair", "Pipe Leak Repair", "Repair leaking supply or drain section and pressure test", ["pipe", "leak", "repair"], ["pipe repair", "minor leak repair", "cost to fix a leak", "leaking pipes"]),
    ServiceSpec("ir_wheater_tank_install", "Water Heater", "Tank Water Heater Install", "Tank Water Heater Install", "Install tank water heater with code-compliant connections and startup", ["water heater", "tank", "install"], ["water heater installation", "water heater replacement", "tank water heater install"]),
    ServiceSpec("ir_wheater_tankless_install", "Water Heater", "Tankless Water Heater Install", "Tankless Water Heater Install", "Install tankless water heater and commission system", ["water heater", "tankless", "install"], ["tankless water heater installation", "tankless water heater install"]),
    ServiceSpec("ir_wheater_flush", "Water Heater", "Water Heater Flush", "Water Heater Flush", "Perform full flush and preventive maintenance", ["water heater", "flush", "maintenance"], ["water heater flush", "water heater maintenance"]),
    ServiceSpec("ir_emergency_leak", "Emergency", "Burst Pipe Emergency Response", "Burst Pipe Emergency Response", "Emergency response to active leak with stabilization and repair", ["emergency", "burst", "pipe", "leak"], ["burst pipe repair", "burst pipe emergency", "emergency pipe repair"]),
    ServiceSpec("ir_emergency_overflow", "Emergency", "Overflow Emergency Response", "Overflow Emergency Response", "Emergency response for overflow event and immediate mitigation", ["emergency", "overflow", "toilet"], ["overflow emergency", "toilet overflow", "emergency service call"]),
    # New services.
    ServiceSpec("ir_sink_install", "Fixtures", "Sink Installation", "Sink Installation", "Install sink fixture and verify proper sealing and drainage", ["sink", "fixture", "install"], ["sink installation"]),
    ServiceSpec("ir_shower_valve_replace", "Fixtures", "Shower Valve Replacement", "Shower Valve Replacement", "Replace shower valve and rebalance flow and temperature", ["shower", "valve", "replace"], ["shower valve installation", "shower valve replacement"]),
    ServiceSpec("ir_bathtub_install", "Fixtures", "Bathtub Installation", "Bathtub Installation", "Install bathtub and complete fixture and drain hookups", ["bathtub", "tub", "install"], ["bathtub installation", "walk-in tub installation"]),
    ServiceSpec("ir_water_softener_install", "Fixtures", "Water Softener Installation", "Water Softener Installation", "Install water softener and test system operation", ["water softener", "install"], ["water softener installation"]),
    ServiceSpec("ir_toilet_repair", "Fixtures", "Toilet Repair", "Toilet Repair", "Repair toilet fill, flush, seal, or clog-related issues", ["toilet", "repair"], ["toilet repair"]),
    ServiceSpec("ir_drain_pipe_replacement", "Drain Services", "Drain Pipe Replacement", "Drain Pipe Replacement", "Repair or replace damaged drain pipe segments", ["drain", "pipe", "replacement"], ["drain line repair", "cost to replace drain pipes", "drain pipe replacement"]),
    ServiceSpec("ir_sewer_camera_inspection", "Drain Services", "Sewer Camera Inspection", "Sewer Camera Inspection", "Inspect sewer/drain line with camera and provide findings", ["sewer", "camera", "inspection"], ["sewer line inspection", "sewer camera inspection"]),
    ServiceSpec("ir_sewer_line_replacement", "Drain Services", "Sewer Line Replacement", "Sewer Line Replacement", "Replace damaged sewer main line and restore service", ["sewer", "line", "replacement"], ["sewer line replacement", "sewer main line repair"]),
    ServiceSpec("ir_gas_line_repair", "Pipe Repair", "Gas Line Repair", "Gas Line Repair", "Repair gas line and verify leak-safe operation", ["gas line", "repair"], ["gas line repair"]),
    ServiceSpec("ir_main_water_line_repair", "Pipe Repair", "Main Water Line Repair", "Main Water Line Repair", "Repair main water line leak and restore pressure", ["main water line", "repair"], ["water main repair", "main water line repair"]),
    ServiceSpec("ir_reroute_plumbing", "Pipe Repair", "Rerouting Plumbing", "Rerouting Plumbing", "Reroute plumbing for access, remodel, or damaged lines", ["reroute", "plumbing"], ["rerouting plumbing"]),
    ServiceSpec("ir_full_house_repipe", "Pipe Repair", "Full House Repipe", "Full House Repipe", "Replace major in-home plumbing runs with modern piping", ["repipe", "whole house"], ["full repipe", "whole-house plumbing", "new plumbing pipes cost"]),
    ServiceSpec("ir_water_heater_repair", "Water Heater", "Water Heater Repair", "Water Heater Repair", "Diagnose and repair tank or tankless water heater faults", ["water heater", "repair"], ["water heater repair"]),
    ServiceSpec("ir_gas_valve_replacement", "Water Heater", "Gas Valve Replacement", "Gas Valve Replacement", "Replace water heater gas control valve and test system", ["gas valve", "water heater"], ["water heater gas valve replacement"]),
    ServiceSpec("ir_sump_pump_install", "Pump Services", "Sump Pump Installation", "Sump Pump Installation", "Install sump pump and verify discharge operation", ["sump pump", "install"], ["sump pump installation"]),
    ServiceSpec("ir_sump_pump_repair", "Pump Services", "Sump Pump Repair", "Sump Pump Repair", "Repair sump pump and restore pumping performance", ["sump pump", "repair"], ["sump pump repair"]),
    ServiceSpec("ir_well_pump_repair", "Pump Services", "Well Pump Repair", "Well Pump Repair", "Repair well pump components and restore water delivery", ["well pump", "repair"], ["well pump repair"]),
    ServiceSpec("ir_emergency_service_call", "Emergency", "Emergency Service Call", "Emergency Service Call", "Urgent dispatch fee and first-hour diagnostics for emergency calls", ["emergency", "service", "call"], ["emergency service call", "emergency plumber cost", "after-hours or holiday repair"]),
    ServiceSpec("ir_plumbing_inspection", "Inspection", "Plumbing Inspection", "Plumbing Inspection", "Perform plumbing inspection and document findings", ["inspection", "plumbing"], ["plumbing inspection", "sewer line inspection"]),
    ServiceSpec("ir_septic_pumping", "Septic", "Septic Tank Pumping", "Septic Tank Pumping", "Pump septic tank and inspect condition", ["septic", "pumping"], ["septic tank pumping"]),
    ServiceSpec("ir_septic_repair", "Septic", "Septic Tank Repair", "Septic Tank Repair", "Repair septic system components and restore operation", ["septic", "repair"], ["septic tank repair"]),
]


def sanitize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value or "").strip()


def q(value: str) -> str:
    return value.replace("'", "''")


def q_array(values: Iterable[str]) -> str:
    values = list(values)
    if not values:
        return "array[]::text[]"
    escaped = ",".join("'" + q(v) + "'" for v in values)
    return f"array[{escaped}]"


def load_rows() -> list[dict]:
    payload = json.loads(RAW_PATH.read_text(encoding="utf-8"))
    return payload.get("rows", [])


def row_matches_service(row: dict, aliases: list[str]) -> bool:
    haystack = f"{row.get('service', '')} {row.get('raw_text', '')}".lower()
    return any(alias in haystack for alias in aliases)


def robust_mean(values: list[float]) -> float:
    """
    Mean with simple trimming for outlier-heavy scraped rows.
    """
    if not values:
        raise ValueError("Cannot average empty list")
    sorted_vals = sorted(values)
    if len(sorted_vals) >= 6:
        trim = max(1, int(len(sorted_vals) * 0.15))
        trimmed = sorted_vals[trim:-trim]
        if trimmed:
            return round(statistics.mean(trimmed), 2)
    return round(statistics.mean(sorted_vals), 2)


def compute_prices_for_service(rows: list[dict], spec: ServiceSpec) -> tuple[float, float, float, list[str], list[str]]:
    rows_for_spec = [r for r in rows if row_matches_service(r, spec.aliases)]

    per_source: dict[str, dict[str, list[float]]] = {}
    for r in rows_for_spec:
        source = r.get("source", "unknown")
        low = float(r.get("price_low") or 0)
        high = float(r.get("price_high") or 0)
        avg = float(r.get("price_avg") or ((low + high) / 2.0))
        if low <= 0 or high <= 0:
            continue
        if high < low:
            low, high = high, low
        # Filter clearly irrelevant outliers from scraping noise.
        if low < 20 or high > 50000:
            continue
        per_source.setdefault(source, {"low": [], "mid": [], "high": [], "urls": []})
        per_source[source]["low"].append(low)
        per_source[source]["mid"].append(avg)
        per_source[source]["high"].append(high)
        per_source[source]["urls"].append(r.get("source_url", ""))

    source_urls: set[str] = set()
    participating_sources: list[str] = []
    weighted_low = 0.0
    weighted_mid = 0.0
    weighted_high = 0.0
    weight_sum = 0.0
    for source, stats in per_source.items():
        if not stats["low"]:
            continue
        source_weight = SOURCE_WEIGHTS.get(source, 0.2)
        low = robust_mean(stats["low"])
        mid = robust_mean(stats["mid"])
        high = robust_mean(stats["high"])
        weighted_low += low * source_weight
        weighted_mid += mid * source_weight
        weighted_high += high * source_weight
        weight_sum += source_weight
        participating_sources.append(source)
        source_urls.update([u for u in stats["urls"] if u])

    if weight_sum == 0:
        # Fall back to a conservative default if no rows matched.
        return 175.0, 240.0, 320.0, [], []

    good = round(weighted_low / weight_sum, 2)
    better = round(weighted_mid / weight_sum, 2)
    best = round(weighted_high / weight_sum, 2)

    # Keep tiers monotonic and sane.
    # Smooth tiers so noisy source spreads still produce usable Good/Better/Best ladders.
    better = max(better, round(good * 1.15, 2), good + 10)
    better = min(better, round(good * 1.60, 2))
    best = max(best, round(better * 1.20, 2), better + 15)
    best = min(best, round(better * 1.70, 2))
    return good, better, best, sorted(source_urls), sorted(set(participating_sources))


def compute_hours(price: float, category: str, labor_rate: float = 95.0) -> float:
    factor = CATEGORY_HOUR_FACTORS.get(category, 0.75)
    hours = (price / labor_rate) * factor
    return round(max(0.5, min(hours, 12.0)), 1)


def build_sql(records: list[dict]) -> str:
    values_sql_lines = []
    for r in records:
        values_sql_lines.append(
            "("
            f"'{q(r['id'])}', "
            f"'{q(r['category'])}', "
            f"'{q(r['subcategory'])}', "
            f"'{q(r['display_name'])}', "
            f"'{q(r['description'])}', "
            f"{r['price_good']:.2f}, {r['price_better']:.2f}, {r['price_best']:.2f}, "
            f"{r['labor_hours_good']:.1f}, {r['labor_hours_better']:.1f}, {r['labor_hours_best']:.1f}, "
            f"{q_array(r['tags'])}, "
            f"'{q(r['source'])}', "
            f"{q_array(r['source_urls'])}"
            ")"
        )

    values_clause = ",\n      ".join(values_sql_lines)

    return f"""-- Industry pricing refresh for 2026 with multi-source attribution.
-- Generated by scripts/generate_migration.py

alter table public.industry_rates
  add column if not exists source_urls text[] not null default '{{}}';

with seed_rates as (
  select * from (
    values
      {values_clause}
  ) as t(
    id, category, subcategory, display_name, description,
    price_good, price_better, price_best,
    labor_hours_good, labor_hours_better, labor_hours_best,
    tags, source, source_urls
  )
)
insert into public.industry_rates (
  id, category, subcategory, display_name, description,
  price_good, price_better, price_best,
  labor_hours_good, labor_hours_better, labor_hours_best,
  labor_rate_per_hour,
  warranty_months_good, warranty_months_better, warranty_months_best,
  solution_good, solution_better, solution_best,
  tags, source, source_urls, is_active, updated_at
)
select
  id, category, subcategory, display_name, description,
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
  source,
  source_urls,
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
  source_urls = excluded.source_urls,
  is_active = excluded.is_active,
  updated_at = now();
"""


def parse_existing_seed_prices() -> dict[str, tuple[float, float, float]]:
    """
    Pull old values from 002_seed_industry.sql for comparison output.
    """
    text = BASELINE_SEED.read_text(encoding="utf-8")
    pattern = re.compile(
        r"\('([^']+)'\s*,\s*'[^']+'\s*,\s*'[^']+'\s*,\s*'[^']+'\s*,\s*'[^']+'\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)",
        re.MULTILINE,
    )
    prices: dict[str, tuple[float, float, float]] = {}
    for match in pattern.finditer(text):
        prices[match.group(1)] = (
            float(match.group(2)),
            float(match.group(3)),
            float(match.group(4)),
        )
    return prices


def main() -> int:
    if not RAW_PATH.exists():
        raise FileNotFoundError(f"Missing input file: {RAW_PATH}")

    rows = load_rows()
    records = []
    for spec in SERVICE_SPECS:
        price_good, price_better, price_best, source_urls, used_sources = compute_prices_for_service(rows, spec)
        records.append(
            {
                "id": spec.id,
                "category": spec.category,
                "subcategory": spec.subcategory,
                "display_name": spec.display_name,
                "description": spec.description,
                "price_good": price_good,
                "price_better": price_better,
                "price_best": price_best,
                "labor_hours_good": compute_hours(price_good, spec.category),
                "labor_hours_better": compute_hours(price_better, spec.category),
                "labor_hours_best": compute_hours(price_best, spec.category),
                "tags": spec.tags,
                "source": (
                    " | ".join([s.title() for s in used_sources]) + " 2026 normalized"
                    if used_sources
                    else "Default baseline (insufficient source rows)"
                ),
                "source_urls": source_urls,
            }
        )

    OUT_SQL.write_text(build_sql(records), encoding="utf-8")

    old_prices = parse_existing_seed_prices()
    print("Generated migration:", OUT_SQL)
    print("\nOld vs New (existing seeded rows):")
    print("id | old_good -> new_good | old_better -> new_better | old_best -> new_best")
    for r in records:
        if r["id"] not in old_prices:
            continue
        old_good, old_better, old_best = old_prices[r["id"]]
        print(
            f"{r['id']} | "
            f"{old_good:.2f} -> {r['price_good']:.2f} | "
            f"{old_better:.2f} -> {r['price_better']:.2f} | "
            f"{old_best:.2f} -> {r['price_best']:.2f}"
        )

    # Quality checks.
    print("\nValidation warnings:")
    warning_count = 0
    for r in records:
        if r["price_good"] <= 0 or r["price_better"] <= 0 or r["price_best"] <= 0:
            print(f"- Non-positive price for {r['id']}")
            warning_count += 1
        if r["price_best"] > (r["price_good"] * 2.0):
            print(f"- Large source spread for {r['id']}: best more than 2x good")
            warning_count += 1
        if not r["source_urls"]:
            print(f"- Only fallback/default data for {r['id']} (no matched source rows)")
            warning_count += 1
    if warning_count == 0:
        print("- none")

    print(f"\nTotal rows prepared: {len(records)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
