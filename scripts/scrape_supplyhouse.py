#!/usr/bin/env python3
"""
Scrape SupplyHouse plumbing catalog into parts_catalog with embeddings.

Pipeline:
1) Firecrawl /scrape on leaf category pages (with pagination)
2) Claude Sonnet parse -> structured product rows
3) Normalize + dedupe
4) OpenAI embeddings
5) Supabase upsert into parts_catalog
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

import requests


LEAF_CATEGORY_URLS = [
    "https://www.supplyhouse.com/Tank-Water-Heaters-4313",
    "https://www.supplyhouse.com/Tankless-Water-Heaters-4315",
    "https://www.supplyhouse.com/Water-Heater-Parts-1095",
    "https://www.supplyhouse.com/Anode-Rods-16931000",
    "https://www.supplyhouse.com/Expansion-Tanks-584",
    "https://www.supplyhouse.com/Temperature-Pressure-Relief-Valves-585",
    "https://www.supplyhouse.com/Mixing-Valves-1069",
    "https://www.supplyhouse.com/Bathroom-Faucets-478",
    "https://www.supplyhouse.com/Kitchen-Faucets-480",
    "https://www.supplyhouse.com/Shower-Faucets-481",
    "https://www.supplyhouse.com/Shower-Heads-482",
    "https://www.supplyhouse.com/Toilets-1124",
    "https://www.supplyhouse.com/Toilet-Seats-1125",
    "https://www.supplyhouse.com/Toilet-Parts-1126",
    "https://www.supplyhouse.com/Garbage-Disposals-1127",
    "https://www.supplyhouse.com/Bathroom-Sinks-500",
    "https://www.supplyhouse.com/Kitchen-Sinks-501",
    "https://www.supplyhouse.com/Drain-Cleaning-Tools-1639",
    "https://www.supplyhouse.com/Drain-Openers-1640",
    "https://www.supplyhouse.com/PVC-Pipe-1475",
    "https://www.supplyhouse.com/CPVC-Pipe-1477",
    "https://www.supplyhouse.com/Copper-Tubing-1481",
    "https://www.supplyhouse.com/PEX-Tubing-1029",
    "https://www.supplyhouse.com/PEX-Fittings-1028",
    "https://www.supplyhouse.com/SharkBite-Fittings-1658",
    "https://www.supplyhouse.com/Ball-Valves-604",
    "https://www.supplyhouse.com/Gate-Valves-605",
    "https://www.supplyhouse.com/Check-Valves-607",
    "https://www.supplyhouse.com/Pressure-Reducing-Valves-1098",
    "https://www.supplyhouse.com/Backflow-Preventers-1097",
    "https://www.supplyhouse.com/Sump-Pumps-1320",
    "https://www.supplyhouse.com/Sewage-Pumps-1321",
    "https://www.supplyhouse.com/Well-Pumps-1322",
    "https://www.supplyhouse.com/Water-Softeners-1382",
    "https://www.supplyhouse.com/Whole-House-Water-Filters-1383",
    "https://www.supplyhouse.com/Under-Sink-Water-Filters-1384",
    "https://www.supplyhouse.com/Floor-Drains-1118",
    "https://www.supplyhouse.com/Shower-Drains-1119",
    "https://www.supplyhouse.com/Sink-Drains-1120",
    "https://www.supplyhouse.com/P-Traps-1121",
]

URL_TAXONOMY: dict[str, tuple[str, str]] = {
    "Tank-Water-Heaters-4313": ("Water Heater", "Tank Water Heater"),
    "Tankless-Water-Heaters-4315": ("Water Heater", "Tankless Water Heater"),
    "Water-Heater-Parts-1095": ("Water Heater", "Water Heater Parts"),
    "Anode-Rods-16931000": ("Water Heater", "Anode Rods"),
    "Temperature-Pressure-Relief-Valves-585": ("Water Heater", "TPR Valve"),
    "Expansion-Tanks-584": ("Water Heater", "Expansion Tank"),
    "Bathroom-Faucets-478": ("Fixtures", "Bathroom Faucet"),
    "Kitchen-Faucets-480": ("Fixtures", "Kitchen Faucet"),
    "Shower-Faucets-481": ("Fixtures", "Shower Faucet"),
    "Toilets-1124": ("Fixtures", "Toilet"),
    "Toilet-Parts-1126": ("Fixtures", "Toilet Parts"),
    "Garbage-Disposals-1127": ("Fixtures", "Garbage Disposal"),
    "Sump-Pumps-1320": ("Pump Services", "Sump Pump"),
    "Sewage-Pumps-1321": ("Pump Services", "Sewage Pump"),
    "Well-Pumps-1322": ("Pump Services", "Well Pump"),
    "PVC-Pipe-1475": ("Pipe Repair", "PVC Pipe"),
    "CPVC-Pipe-1477": ("Pipe Repair", "CPVC Pipe"),
    "Copper-Tubing-1481": ("Pipe Repair", "Copper Tubing"),
    "PEX-Tubing-1029": ("Pipe Repair", "PEX Tubing"),
    "PEX-Fittings-1028": ("Pipe Repair", "PEX Fittings"),
    "SharkBite-Fittings-1658": ("Pipe Repair", "SharkBite Fittings"),
    "Ball-Valves-604": ("Pipe Repair", "Ball Valve"),
    "Gate-Valves-605": ("Pipe Repair", "Gate Valve"),
    "Check-Valves-607": ("Pipe Repair", "Check Valve"),
    "Drain-Cleaning-Tools-1639": ("Drain Services", "Drain Cleaning Tools"),
    "Drain-Openers-1640": ("Drain Services", "Drain Openers"),
}

FOCUS_COMMON_JOB_URLS = [
    "https://www.supplyhouse.com/Tank-Water-Heaters-4313",
    "https://www.supplyhouse.com/Tankless-Water-Heaters-4315",
    "https://www.supplyhouse.com/Water-Heater-Parts-1095",
    "https://www.supplyhouse.com/Toilets-1124",
    "https://www.supplyhouse.com/Bathroom-Faucets-478",
    "https://www.supplyhouse.com/Kitchen-Faucets-480",
    "https://www.supplyhouse.com/Garbage-Disposals-1127",
    "https://www.supplyhouse.com/Sump-Pumps-1320",
    "https://www.supplyhouse.com/Ball-Valves-604",
    "https://www.supplyhouse.com/PEX-Fittings-1028",
]


@dataclass
class ProductRow:
    sku: str | None
    brand: str
    name: str
    description: str
    category: str
    subcategory: str | None
    wholesale_price: float | None
    retail_price: float | None
    source_url: str
    specs: dict[str, Any]


def require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required env var: {name}")
    return value


def normalize_price(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value) if value > 0 else None
    text = str(value).replace("$", "").replace(",", "").strip()
    if not text:
        return None
    try:
        parsed = float(text)
    except ValueError:
        return None
    return parsed if parsed > 0 else None


def taxonomy_from_url(source_url: str) -> tuple[str, str | None]:
    for token, (category, subcategory) in URL_TAXONOMY.items():
        if token in source_url:
            return category, subcategory
    return "Plumbing Supplies", None


def firecrawl_scrape(api_key: str, url: str) -> str:
    response = requests.post(
        "https://api.firecrawl.dev/v1/scrape",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        json={
            "url": url,
            "formats": ["markdown"],
            "onlyMainContent": True,
            "timeout": 120000,
        },
        timeout=90,
    )
    response.raise_for_status()
    payload = response.json()
    return str(payload.get("data", {}).get("markdown", "")).strip()


def parse_products_with_claude(
    anthropic_api_key: str, markdown: str, source_url: str, max_rows: int
) -> list[dict[str, Any]]:
    prompt = f"""Extract SupplyHouse plumbing products from this category listing page.
Return STRICT JSON only. No markdown.
Schema:
[
  {{
    "sku": "string|null",
    "brand": "string|null",
    "name": "string",
    "description": "string|null",
    "category": "string|null",
    "subcategory": "string|null",
    "price": 0,
    "list_price": 0,
    "url": "string|null",
    "specifications": {{}}
  }}
]

Rules:
- Extract only products visible in this page text.
- Do not invent products.
- Keep at most {max_rows} products for this page.
- Use null when a value is not available.

URL: {source_url}
TEXT:
{markdown[:110000]}
"""
    response = requests.post(
        "https://api.anthropic.com/v1/messages",
        headers={
            "x-api-key": anthropic_api_key,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        },
        json={
            "model": "claude-sonnet-4-6",
            "temperature": 0,
            "max_tokens": 4096,
            "messages": [{"role": "user", "content": [{"type": "text", "text": prompt}]}],
        },
        timeout=120,
    )
    response.raise_for_status()
    payload = response.json()
    content = payload.get("content", [])
    text = ""
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                text = str(block.get("text", "")).strip()
                break
    cleaned = text.replace("```json", "").replace("```", "").strip()
    parsed = json.loads(cleaned) if cleaned else []
    return parsed if isinstance(parsed, list) else []


def normalize_row(raw: dict[str, Any], fallback_url: str) -> ProductRow | None:
    name = str(raw.get("name", "")).strip()
    if not name:
        return None
    brand = str(raw.get("brand", "")).strip() or "Unknown"
    description = str(raw.get("description", "")).strip()
    mapped_category, mapped_subcategory = taxonomy_from_url(fallback_url)
    raw_category = str(raw.get("category", "")).strip()
    raw_subcategory = str(raw.get("subcategory", "")).strip()
    category = mapped_category if mapped_category != "Plumbing Supplies" else (raw_category or "Plumbing Supplies")
    subcategory = mapped_subcategory or (raw_subcategory or None)
    sku = str(raw.get("sku", "")).strip() or None
    source_url = str(raw.get("url", "")).strip() or fallback_url
    specs = raw.get("specifications", {})
    if not isinstance(specs, dict):
        specs = {}
    return ProductRow(
        sku=sku,
        brand=brand,
        name=name,
        description=description,
        category=category,
        subcategory=subcategory,
        wholesale_price=normalize_price(raw.get("price")),
        retail_price=normalize_price(raw.get("list_price")),
        source_url=source_url,
        specs=specs,
    )


def generate_embedding(openai_api_key: str, text: str) -> list[float]:
    response = requests.post(
        "https://api.openai.com/v1/embeddings",
        headers={
            "Authorization": f"Bearer {openai_api_key}",
            "Content-Type": "application/json",
        },
        json={"model": "text-embedding-3-small", "dimensions": 1536, "input": text},
        timeout=45,
    )
    response.raise_for_status()
    payload = response.json()
    return payload["data"][0]["embedding"]


def deterministic_id(row: ProductRow) -> str:
    basis = f"{row.brand.lower()}|{row.name.lower()}|{row.sku or ''}"
    token = hashlib.sha1(basis.encode("utf-8")).hexdigest()[:22]
    return f"prt_{token}"


def build_record(row: ProductRow, embedding: list[float]) -> dict[str, Any]:
    now = datetime.now(timezone.utc).isoformat()
    return {
        "id": deterministic_id(row),
        "sku": row.sku,
        "brand": row.brand,
        "name": row.name,
        "description": row.description or None,
        "category": row.category,
        "subcategory": row.subcategory,
        "wholesale_price": row.wholesale_price,
        "retail_price": row.retail_price,
        "unit_of_measure": "each",
        "specifications": row.specs,
        "source": "supplyhouse",
        "source_url": row.source_url,
        "embedding": embedding,
        "is_active": True,
        "date_scraped": now,
        "updated_at": now,
    }


def upsert_parts(supabase_url: str, service_role_key: str, records: list[dict[str, Any]]) -> None:
    if not records:
        return
    response = requests.post(
        f"{supabase_url}/rest/v1/parts_catalog?on_conflict=id",
        headers={
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates",
        },
        json=records,
        timeout=90,
    )
    response.raise_for_status()


def dedupe_records(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    deduped: dict[str, dict[str, Any]] = {}
    for record in records:
        record_id = str(record.get("id", "")).strip()
        if not record_id:
            continue
        deduped[record_id] = record
    return list(deduped.values())


def with_page(url: str, page: int) -> str:
    if page <= 1:
        return url
    sep = "&" if "?" in url else "?"
    return f"{url}{sep}page={page}"


def main() -> None:
    parser = argparse.ArgumentParser(description="Scrape SupplyHouse products into parts_catalog")
    parser.add_argument("--url", action="append", default=[], help="Override/add category URL(s)")
    parser.add_argument("--max-per-page", type=int, default=40, help="Cap products per page")
    parser.add_argument("--max-pages", type=int, default=6, help="Max paginated pages per category")
    parser.add_argument(
        "--focus-common-jobs",
        action="store_true",
        help="Focus scrape on common quoted jobs (water heaters, fixtures, pumps, valves, fittings).",
    )
    args = parser.parse_args()

    firecrawl_key = require_env("FIRECRAWL_API_KEY")
    anthropic_key = require_env("ANTHROPIC_API_KEY")
    openai_key = require_env("OPENAI_API_KEY")
    supabase_url = require_env("SUPABASE_URL")
    service_role_key = require_env("SUPABASE_SERVICE_ROLE_KEY")

    if args.url:
        target_urls = args.url
    elif args.focus_common_jobs:
        target_urls = FOCUS_COMMON_JOB_URLS
    else:
        target_urls = LEAF_CATEGORY_URLS
    staged: list[dict[str, Any]] = []

    for base_url in target_urls:
        empty_pages = 0
        total_for_category = 0
        for page in range(1, max(1, args.max_pages) + 1):
            paged_url = with_page(base_url, page)
            try:
                markdown = firecrawl_scrape(firecrawl_key, paged_url)
                if not markdown:
                    empty_pages += 1
                    print(f"[WARN] Empty markdown: {paged_url}")
                    if empty_pages >= 2:
                        break
                    continue

                raw_products = parse_products_with_claude(
                    anthropic_key, markdown, paged_url, max(1, args.max_per_page)
                )
                normalized: list[ProductRow] = []
                for raw in raw_products:
                    if not isinstance(raw, dict):
                        continue
                    row = normalize_row(raw, paged_url)
                    if row:
                        normalized.append(row)
                limited = normalized[: max(1, args.max_per_page)]
                print(f"[INFO] {paged_url} -> extracted={len(raw_products)} normalized={len(limited)}")
                if not limited:
                    empty_pages += 1
                    if empty_pages >= 2:
                        break
                    continue

                empty_pages = 0
                total_for_category += len(limited)
                for row in limited:
                    emb_text = (
                        f"brand={row.brand}; name={row.name}; category={row.category}; "
                        f"subcategory={row.subcategory or ''}; price={row.wholesale_price}; "
                        f"description={row.description}"
                    )
                    embedding = generate_embedding(openai_key, emb_text)
                    staged.append(build_record(row, embedding))
            except Exception as exc:  # pragma: no cover
                print(f"[WARN] Failed {paged_url}: {exc}")
                empty_pages += 1
                if empty_pages >= 2:
                    break
        print(f"[INFO] category complete {base_url} -> collected={total_for_category}")

    deduped = dedupe_records(staged)
    upsert_parts(supabase_url, service_role_key, deduped)
    dropped = len(staged) - len(deduped)
    print(f"[DONE] Upserted {len(deduped)} parts_catalog records (deduped {dropped})")


if __name__ == "__main__":
    main()
