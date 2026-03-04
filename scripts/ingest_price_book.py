#!/usr/bin/env python3
"""
Price book ingestion pipeline (architecture-first implementation).

This script normalizes service/material rows from CSV/XLSX, generates embeddings
with OpenAI text-embedding-3-small, and upserts rows into Supabase
`price_book_vectors`.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import requests

try:
    import pandas as pd
except Exception:  # pragma: no cover
    pd = None


@dataclass
class PriceBookRow:
    category: str
    subcategory: str
    service_name: str
    description: str
    flat_rate: float | None
    hourly_rate: float | None
    estimated_labor_hours: float | None
    parts_list: list[dict[str, Any]]
    unit_of_measure: str
    cost: float | None
    taxable: bool
    warranty_tier: str | None
    tags: list[str]


def normalize_float(value: Any) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(str(value).replace("$", "").replace(",", "").strip())
    except Exception:
        return None


def normalize_bool(value: Any, default: bool = True) -> bool:
    if value is None:
        return default
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def row_to_embedding_text(row: PriceBookRow) -> str:
    return " | ".join([
        f"Category: {row.category}",
        f"Subcategory: {row.subcategory}",
        f"Service: {row.service_name}",
        f"Description: {row.description}",
        f"Flat rate: {row.flat_rate if row.flat_rate is not None else 'N/A'}",
        f"Hourly rate: {row.hourly_rate if row.hourly_rate is not None else 'N/A'}",
        f"Labor hours: {row.estimated_labor_hours if row.estimated_labor_hours is not None else 'N/A'}",
        f"Parts: {json.dumps(row.parts_list)}",
        f"Warranty tier: {row.warranty_tier or 'N/A'}",
        f"Tags: {', '.join(row.tags)}",
    ])


def load_rows(input_path: Path) -> list[PriceBookRow]:
    suffix = input_path.suffix.lower()
    if suffix == ".csv":
        with input_path.open("r", encoding="utf-8-sig") as f:
            raw_rows = list(csv.DictReader(f))
    elif suffix in {".xlsx", ".xls"}:
        if pd is None:
            raise RuntimeError("pandas/openpyxl required for XLSX ingestion")
        raw_rows = pd.read_excel(input_path).fillna("").to_dict(orient="records")
    elif suffix == ".pdf":
        raise RuntimeError(
            "PDF ingestion requires source cost data and extraction logic. "
            "Use CSV/XLSX for now, then add Claude PDF extraction when data is available."
        )
    else:
        raise RuntimeError(f"Unsupported file format: {suffix}")

    rows: list[PriceBookRow] = []
    for row in raw_rows:
        category = str(row.get("category") or row.get("Category") or "General").strip()
        subcategory = str(row.get("subcategory") or row.get("Subcategory") or "General").strip()
        service_name = str(row.get("service_name") or row.get("name") or row.get("Name") or "").strip()
        if not service_name:
            continue

        description = str(row.get("description") or row.get("Description") or "").strip()
        tags_raw = str(row.get("tags") or "").strip()
        tags = [t.strip() for t in tags_raw.split(",") if t.strip()] if tags_raw else []

        parts_list: list[dict[str, Any]] = []
        raw_parts = row.get("parts_list")
        if isinstance(raw_parts, str) and raw_parts.strip():
            try:
                parsed = json.loads(raw_parts)
                if isinstance(parsed, list):
                    parts_list = parsed
            except Exception:
                parts_list = [{"name": raw_parts.strip(), "cost": None, "quantity": 1}]

        rows.append(
            PriceBookRow(
                category=category,
                subcategory=subcategory,
                service_name=service_name,
                description=description,
                flat_rate=normalize_float(row.get("flat_rate") or row.get("price")),
                hourly_rate=normalize_float(row.get("hourly_rate")),
                estimated_labor_hours=normalize_float(row.get("estimated_labor_hours") or row.get("labor_hours")),
                parts_list=parts_list,
                unit_of_measure=str(row.get("unit_of_measure") or "each").strip(),
                cost=normalize_float(row.get("cost")),
                taxable=normalize_bool(row.get("taxable"), True),
                warranty_tier=str(row.get("warranty_tier") or "").strip() or None,
                tags=tags,
            )
        )
    return rows


def openai_embedding(api_key: str, text: str) -> list[float]:
    response = requests.post(
        "https://api.openai.com/v1/embeddings",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        json={
            "model": "text-embedding-3-small",
            "dimensions": 1536,
            "input": text,
        },
        timeout=30,
    )
    response.raise_for_status()
    payload = response.json()
    return payload["data"][0]["embedding"]


def supabase_upsert(
    supabase_url: str,
    service_role_key: str,
    record: dict[str, Any],
) -> None:
    response = requests.post(
        f"{supabase_url}/rest/v1/price_book_vectors",
        headers={
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates",
        },
        json=record,
        timeout=30,
    )
    response.raise_for_status()


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest client price book into Supabase pgvector")
    parser.add_argument("--input", required=True, help="Path to CSV/XLSX input")
    args = parser.parse_args()

    supabase_url = os.getenv("NEXT_PUBLIC_SUPABASE_URL") or os.getenv("SUPABASE_URL")
    service_role_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    openai_api_key = os.getenv("OPENAI_API_KEY")

    if not supabase_url or not service_role_key or not openai_api_key:
        raise RuntimeError("Missing required env vars: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, OPENAI_API_KEY")

    input_path = Path(args.input)
    rows = load_rows(input_path)
    if not rows:
        print("No valid rows found.")
        return

    for index, row in enumerate(rows):
        embedding_text = row_to_embedding_text(row)
        embedding = openai_embedding(openai_api_key, embedding_text)
        record = {
            "id": f"pbv_{index}_{row.service_name.lower().replace(' ', '_')}"[:120],
            "category": row.category,
            "subcategory": row.subcategory,
            "service_name": row.service_name,
            "description": row.description,
            "flat_rate": row.flat_rate,
            "hourly_rate": row.hourly_rate,
            "estimated_labor_hours": row.estimated_labor_hours,
            "parts_list": row.parts_list,
            "unit_of_measure": row.unit_of_measure,
            "cost": row.cost,
            "taxable": row.taxable,
            "warranty_tier": row.warranty_tier,
            "tags": row.tags,
            "embedding": embedding,
            "is_active": True,
        }
        supabase_upsert(supabase_url, service_role_key, record)

    print(f"Ingested {len(rows)} price book rows into price_book_vectors.")


if __name__ == "__main__":
    main()
