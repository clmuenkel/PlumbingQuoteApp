#!/usr/bin/env python3
"""
Scrape DFW slab leak and leak-detection pricing sources into competitor_pricing.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

import requests


SLAB_LEAK_DFW_URLS = [
    "https://mrrogersplumbing.com/slab-leak-repair-cost-analysis-2025/",
    "https://pieceofmindplumbing.com/blog/plumber-cost-in-dfw/",
    "https://www.powerplumbingtx.com/slab-leak-repair-cost/",
    "https://fnffoundation.com/how-much-does-slab-leak-repair-cost-2025-data/",
]


@dataclass
class PricingRow:
    service_type: str
    price_low: float | None
    price_avg: float | None
    price_high: float | None
    unit: str
    notes: str
    source_url: str


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


def parse_with_claude(anthropic_api_key: str, markdown: str, source_url: str) -> list[PricingRow]:
    prompt = f"""Extract Dallas-Fort Worth slab leak and plumbing leak pricing entries from this page.
Return STRICT JSON only. No markdown.
Schema:
[
  {{
    "service_type": "string",
    "price_low": 0,
    "price_avg": 0,
    "price_high": 0,
    "unit": "job|hour|service_call|linear_foot",
    "notes": "short context"
  }}
]

Rules:
- Focus on slab leak detection, slab leak repair, pipe leak repair, and leak-related plumbing services.
- Keep DFW/Texas-specific values when available.
- If only one value exists, set low=avg=high.
- Exclude unrelated values.

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
    text = ""
    content = payload.get("content", [])
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                text = str(block.get("text", "")).strip()
                break
    cleaned = text.replace("```json", "").replace("```", "").strip()
    parsed = json.loads(cleaned) if cleaned else []

    rows: list[PricingRow] = []
    for entry in parsed if isinstance(parsed, list) else []:
        if not isinstance(entry, dict):
            continue
        service_type = str(entry.get("service_type", "")).strip()
        if not service_type:
            continue
        low = normalize_price(entry.get("price_low"))
        avg = normalize_price(entry.get("price_avg"))
        high = normalize_price(entry.get("price_high"))
        values = [v for v in [low, avg, high] if v is not None]
        if not values:
            continue
        if low is None:
            low = min(values)
        if high is None:
            high = max(values)
        if avg is None:
            avg = sum(values) / len(values)
        rows.append(
            PricingRow(
                service_type=service_type,
                price_low=round(low, 2) if low is not None else None,
                price_avg=round(avg, 2) if avg is not None else None,
                price_high=round(high, 2) if high is not None else None,
                unit=str(entry.get("unit", "job")).strip() or "job",
                notes=str(entry.get("notes", "")).strip(),
                source_url=source_url,
            )
        )
    return rows


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


def deterministic_id(service_type: str, source: str, region: str) -> str:
    token = hashlib.sha1(f"{service_type.lower()}|{source.lower()}|{region.lower()}".encode("utf-8")).hexdigest()[:22]
    return f"cmp_{token}"


def build_record(row: PricingRow, embedding: list[float]) -> dict[str, Any]:
    now = datetime.now(timezone.utc)
    source = "slab_leak_dfw"
    region = "DFW"
    return {
        "id": deterministic_id(row.service_type, source, region),
        "service_type": row.service_type,
        "source": source,
        "source_url": row.source_url,
        "region": region,
        "price_low": row.price_low,
        "price_avg": row.price_avg,
        "price_high": row.price_high,
        "data_type": "crawled",
        "raw_text": row.notes or None,
        "date_scraped": now.isoformat(),
        "expires_at": (now + timedelta(days=14)).isoformat(),
        "is_active": True,
        "embedding": embedding,
    }


def upsert_rows(supabase_url: str, service_role_key: str, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    headers = {
        "apikey": service_role_key,
        "Authorization": f"Bearer {service_role_key}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates",
    }
    requests.delete(
        f"{supabase_url}/rest/v1/competitor_pricing?source=eq.slab_leak_dfw&region=eq.DFW",
        headers=headers,
        timeout=60,
    ).raise_for_status()
    response = requests.post(
        f"{supabase_url}/rest/v1/competitor_pricing",
        headers=headers,
        json=rows,
        timeout=90,
    )
    response.raise_for_status()


def dedupe_records(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    deduped: dict[str, dict[str, Any]] = {}
    for record in records:
        record_id = str(record.get("id", "")).strip()
        if record_id:
            deduped[record_id] = record
    return list(deduped.values())


def main() -> None:
    parser = argparse.ArgumentParser(description="Scrape DFW slab leak pricing into competitor_pricing")
    parser.add_argument("--url", action="append", default=[], help="Override/add target URL(s)")
    args = parser.parse_args()

    firecrawl_key = require_env("FIRECRAWL_API_KEY")
    anthropic_key = require_env("ANTHROPIC_API_KEY")
    openai_key = require_env("OPENAI_API_KEY")
    supabase_url = require_env("SUPABASE_URL")
    service_role_key = require_env("SUPABASE_SERVICE_ROLE_KEY")

    urls = args.url if args.url else SLAB_LEAK_DFW_URLS
    staged: list[dict[str, Any]] = []
    for url in urls:
        try:
            markdown = firecrawl_scrape(firecrawl_key, url)
            if not markdown:
                print(f"[WARN] Empty markdown: {url}")
                continue
            parsed_rows = parse_with_claude(anthropic_key, markdown, url)
            print(f"[INFO] {url} -> extracted {len(parsed_rows)} rows")
            for row in parsed_rows:
                emb_text = (
                    f"source=slab_leak_dfw; service_type={row.service_type}; unit={row.unit}; "
                    f"prices={row.price_low},{row.price_avg},{row.price_high}; notes={row.notes}"
                )
                embedding = generate_embedding(openai_key, emb_text)
                staged.append(build_record(row, embedding))
        except Exception as exc:  # pragma: no cover
            print(f"[WARN] Failed {url}: {exc}")

    deduped = dedupe_records(staged)
    upsert_rows(supabase_url, service_role_key, deduped)
    dropped = len(staged) - len(deduped)
    print(f"[DONE] Upserted {len(deduped)} competitor_pricing records (deduped {dropped})")


if __name__ == "__main__":
    main()
