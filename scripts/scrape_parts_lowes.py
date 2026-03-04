#!/usr/bin/env python3
"""
Scrape Lowe's plumbing catalog pages into parts_catalog with embeddings.
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


LOWES_CATEGORY_URLS = [
    "https://www.lowes.com/pl/Water-heaters-Plumbing/4294822261",
    "https://www.lowes.com/pl/Tankless-water-heaters-Water-heaters-Plumbing/4294822262",
    "https://www.lowes.com/pl/Toilets-Toilets-toilet-seats-Bathroom/4294857241",
    "https://www.lowes.com/pl/Kitchen-faucets-Kitchen/4294857933",
    "https://www.lowes.com/pl/Bathroom-faucets-Bathroom/4294857993",
    "https://www.lowes.com/pl/Garbage-disposals-Appliances/4294857992",
    "https://www.lowes.com/pl/Sump-pumps-Water-pumps-tanks-Plumbing/4294857681",
    "https://www.lowes.com/pl/Water-softeners-Water-filtration-water-softeners-Plumbing/4294857485",
    "https://www.lowes.com/pl/Shower-heads-Shower-faucets-shower-heads-Bathroom/4294857999",
    "https://www.lowes.com/pl/Pex-pipe-Pipe-fittings-Plumbing/4294512217",
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


def firecrawl_scrape(api_key: str, url: str) -> str:
    response = requests.post(
        "https://api.firecrawl.dev/v1/scrape",
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        json={"url": url, "formats": ["markdown"], "onlyMainContent": True, "timeout": 120000},
        timeout=90,
    )
    response.raise_for_status()
    payload = response.json()
    return str(payload.get("data", {}).get("markdown", "")).strip()


def parse_products_with_claude(
    anthropic_api_key: str, markdown: str, source_url: str, max_rows: int
) -> list[dict[str, Any]]:
    prompt = f"""Extract Lowe's plumbing products from this category listing page.
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
- Keep at most {max_rows} products for this page.
- Use null when a value is unavailable.

URL: {source_url}
TEXT:
{markdown[:115000]}
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
    category = str(raw.get("category", "")).strip() or "Plumbing Supplies"
    subcategory = str(raw.get("subcategory", "")).strip() or None
    sku = str(raw.get("sku", "")).strip() or None
    source_url = str(raw.get("url", "")).strip() or fallback_url
    specs = raw.get("specifications", {})
    if not isinstance(specs, dict):
        specs = {}
    price = normalize_price(raw.get("price"))
    list_price = normalize_price(raw.get("list_price"))
    return ProductRow(
        sku=sku,
        brand=brand,
        name=name,
        description=description,
        category=category,
        subcategory=subcategory,
        wholesale_price=price,
        retail_price=list_price if list_price is not None else price,
        source_url=source_url,
        specs=specs,
    )


def generate_embedding(openai_api_key: str, text: str) -> list[float]:
    response = requests.post(
        "https://api.openai.com/v1/embeddings",
        headers={"Authorization": f"Bearer {openai_api_key}", "Content-Type": "application/json"},
        json={"model": "text-embedding-3-small", "dimensions": 1536, "input": text},
        timeout=45,
    )
    response.raise_for_status()
    payload = response.json()
    return payload["data"][0]["embedding"]


def deterministic_id(row: ProductRow) -> str:
    basis = f"lowes|{row.brand.lower()}|{row.name.lower()}|{row.sku or ''}"
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
        "source": "lowes",
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
        timeout=120,
    )
    response.raise_for_status()


def dedupe_records(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    deduped: dict[str, dict[str, Any]] = {}
    for record in records:
        record_id = str(record.get("id", "")).strip()
        if record_id:
            deduped[record_id] = record
    return list(deduped.values())


def with_page(url: str, page: int) -> str:
    if page <= 1:
        return url
    sep = "&" if "?" in url else "?"
    return f"{url}{sep}page={page}"


def main() -> None:
    parser = argparse.ArgumentParser(description="Scrape Lowe's parts into parts_catalog")
    parser.add_argument("--url", action="append", default=[], help="Override/add category URL(s)")
    parser.add_argument("--max-per-page", type=int, default=35, help="Cap products per page")
    parser.add_argument("--max-pages", type=int, default=2, help="Max paginated pages per category")
    args = parser.parse_args()

    firecrawl_key = require_env("FIRECRAWL_API_KEY")
    anthropic_key = require_env("ANTHROPIC_API_KEY")
    openai_key = require_env("OPENAI_API_KEY")
    supabase_url = require_env("SUPABASE_URL")
    service_role_key = require_env("SUPABASE_SERVICE_ROLE_KEY")

    target_urls = args.url if args.url else LOWES_CATEGORY_URLS
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
                        f"source=lowes; brand={row.brand}; name={row.name}; category={row.category}; "
                        f"subcategory={row.subcategory or ''}; wholesale={row.wholesale_price}; retail={row.retail_price}; "
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
