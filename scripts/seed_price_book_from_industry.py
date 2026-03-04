#!/usr/bin/env python3
"""
Seed price_book_vectors from active industry_rates rows.

This gives the quote pipeline a deterministic baseline so vector lookup does not
fall back to sparse/empty sources.
"""

from __future__ import annotations

import json
import os
from typing import Any

import requests


def require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required env var: {name}")
    return value


def fetch_company_labor_rate(supabase_url: str, service_role_key: str) -> float:
    response = requests.get(
        f"{supabase_url}/rest/v1/company_settings",
        headers={
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
        },
        params={"select": "labor_rate_per_hour", "id": "eq.default", "limit": "1"},
        timeout=30,
    )
    response.raise_for_status()
    rows = response.json()
    if not isinstance(rows, list) or not rows:
        return 95.0
    return float(rows[0].get("labor_rate_per_hour") or 95.0)


def fetch_industry_rates(supabase_url: str, service_role_key: str) -> list[dict[str, Any]]:
    response = requests.get(
        f"{supabase_url}/rest/v1/industry_rates",
        headers={
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
        },
        params={
            "select": (
                "id,category,subcategory,display_name,description,"
                "price_good,price_better,price_best,"
                "labor_hours_good,labor_hours_better,labor_hours_best,"
                "solution_good,solution_better,solution_best,source,source_urls"
            ),
            "is_active": "eq.true",
            "order": "category.asc,subcategory.asc",
            "limit": "500",
        },
        timeout=45,
    )
    response.raise_for_status()
    payload = response.json()
    if not isinstance(payload, list):
        return []
    return payload


def openai_embedding(openai_api_key: str, text: str) -> list[float]:
    response = requests.post(
        "https://api.openai.com/v1/embeddings",
        headers={
            "Authorization": f"Bearer {openai_api_key}",
            "Content-Type": "application/json",
        },
        json={
            "model": "text-embedding-3-small",
            "dimensions": 1536,
            "input": text,
        },
        timeout=45,
    )
    response.raise_for_status()
    return response.json()["data"][0]["embedding"]


def safe_float(value: Any) -> float | None:
    try:
        if value is None:
            return None
        return float(value)
    except Exception:
        return None


def pick_labor_hours(row: dict[str, Any]) -> float | None:
    better = safe_float(row.get("labor_hours_better"))
    if better and better > 0:
        return better
    good = safe_float(row.get("labor_hours_good"))
    best = safe_float(row.get("labor_hours_best"))
    candidates = [v for v in [good, best] if v and v > 0]
    if candidates:
        return sum(candidates) / len(candidates)
    return None


def build_record(row: dict[str, Any], embedding: list[float], fallback_hourly_rate: float) -> dict[str, Any]:
    row_id = str(row.get("id") or "").strip() or "unknown"
    category = str(row.get("category") or "General").strip()
    subcategory = str(row.get("subcategory") or "General").strip()
    display_name = str(row.get("display_name") or "").strip()
    service_name = display_name or subcategory or category
    description = str(row.get("description") or "").strip()

    price_better = safe_float(row.get("price_better"))
    if not price_better or price_better <= 0:
        good = safe_float(row.get("price_good")) or 0
        best = safe_float(row.get("price_best")) or 0
        candidates = [v for v in [good, best] if v > 0]
        price_better = sum(candidates) / len(candidates) if candidates else None

    labor_hours = pick_labor_hours(row)
    source = str(row.get("source") or "industry_rates").strip()
    source_urls = row.get("source_urls")
    tags = [source, category.lower(), subcategory.lower()]
    if isinstance(source_urls, list):
        tags.extend([str(url).strip() for url in source_urls[:3] if str(url).strip()])

    return {
        "id": f"pbv_{row_id}",
        "category": category,
        "subcategory": subcategory,
        "service_name": service_name,
        "description": description,
        "flat_rate": price_better,
        "hourly_rate": fallback_hourly_rate,
        "estimated_labor_hours": labor_hours,
        "parts_list": [],
        "unit_of_measure": "job",
        "cost": None,
        "taxable": True,
        "warranty_tier": "better",
        "tags": tags,
        "embedding": embedding,
        "is_active": True,
    }


def upsert_records(supabase_url: str, service_role_key: str, records: list[dict[str, Any]]) -> None:
    if not records:
        return
    response = requests.post(
        f"{supabase_url}/rest/v1/price_book_vectors?on_conflict=id",
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


def main() -> None:
    supabase_url = require_env("SUPABASE_URL")
    service_role_key = require_env("SUPABASE_SERVICE_ROLE_KEY")
    openai_api_key = require_env("OPENAI_API_KEY")

    industry_rows = fetch_industry_rates(supabase_url, service_role_key)
    if not industry_rows:
        print("No active industry_rates rows found.")
        return

    labor_rate = fetch_company_labor_rate(supabase_url, service_role_key)
    records: list[dict[str, Any]] = []

    for row in industry_rows:
        seed_text = " | ".join(
            [
                f"Category: {row.get('category')}",
                f"Subcategory: {row.get('subcategory')}",
                f"Service: {row.get('display_name') or row.get('subcategory')}",
                f"Description: {row.get('description') or ''}",
                f"Good: {row.get('price_good')}",
                f"Better: {row.get('price_better')}",
                f"Best: {row.get('price_best')}",
                f"Labor hours better: {row.get('labor_hours_better')}",
                f"Solution better: {row.get('solution_better') or ''}",
                f"Source: {row.get('source') or 'industry_rates'}",
            ]
        )
        embedding = openai_embedding(openai_api_key, seed_text)
        records.append(build_record(row, embedding, labor_rate))

    upsert_records(supabase_url, service_role_key, records)
    print(json.dumps({"seeded_rows": len(records), "target_table": "price_book_vectors"}))


if __name__ == "__main__":
    main()
