#!/usr/bin/env python3
"""
Seed parts_catalog with curated Brooks Plumbing residential + water-heater parts.
"""

from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime, timezone
from typing import Any

import requests


def require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required env var: {name}")
    return value


def embed(openai_api_key: str, text: str) -> list[float]:
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


def make_id(brand: str, name: str, subcategory: str) -> str:
    raw = f"{brand.strip().lower()}|{name.strip().lower()}|{subcategory.strip().lower()}"
    token = hashlib.sha1(raw.encode("utf-8")).hexdigest()[:22]
    return f"prt_{token}"


def build_row(item: dict[str, Any], embedding: list[float]) -> dict[str, Any]:
    now = datetime.now(timezone.utc).isoformat()
    return {
        "id": make_id(item["brand"], item["name"], item["subcategory"]),
        "sku": item.get("sku"),
        "brand": item["brand"],
        "name": item["name"],
        "description": item.get("description"),
        "category": item["category"],
        "subcategory": item["subcategory"],
        "wholesale_price": item["wholesale_price"],
        "retail_price": item["retail_price"],
        "unit_of_measure": item.get("unit_of_measure", "each"),
        "specifications": item.get("specifications", {}),
        "source": "brooks_manual_seed",
        "source_url": item.get("source_url", "https://brooksplumbingtexas.com"),
        "embedding": embedding,
        "is_active": True,
        "date_scraped": now,
        "updated_at": now,
    }


def upsert_rows(supabase_url: str, service_role_key: str, rows: list[dict[str, Any]]) -> None:
    if not rows:
        return
    response = requests.post(
        f"{supabase_url}/rest/v1/parts_catalog?on_conflict=id",
        headers={
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates",
        },
        json=rows,
        timeout=90,
    )
    response.raise_for_status()


def catalog_items() -> list[dict[str, Any]]:
    return [
        # Tank water heaters
        {"brand": "Rheem", "name": "Performance 40 Gal Natural Gas Water Heater", "category": "Water Heater", "subcategory": "Tank Water Heater", "wholesale_price": 499.0, "retail_price": 699.0},
        {"brand": "Rheem", "name": "Performance 50 Gal Natural Gas Water Heater", "category": "Water Heater", "subcategory": "Tank Water Heater", "wholesale_price": 629.0, "retail_price": 849.0},
        {"brand": "A.O. Smith", "name": "Signature 40 Gal Electric Water Heater", "category": "Water Heater", "subcategory": "Tank Water Heater", "wholesale_price": 399.0, "retail_price": 579.0},
        {"brand": "A.O. Smith", "name": "Signature 50 Gal Electric Water Heater", "category": "Water Heater", "subcategory": "Tank Water Heater", "wholesale_price": 519.0, "retail_price": 739.0},
        {"brand": "Bradford White", "name": "Defender 40 Gal Natural Gas Water Heater", "category": "Water Heater", "subcategory": "Tank Water Heater", "wholesale_price": 589.0, "retail_price": 799.0},
        # Tankless
        {"brand": "Rinnai", "name": "RU199iN Condensing Tankless Water Heater", "category": "Water Heater", "subcategory": "Tankless Water Heater", "wholesale_price": 999.0, "retail_price": 1399.0},
        {"brand": "Navien", "name": "NPE-240A2 Condensing Tankless Water Heater", "category": "Water Heater", "subcategory": "Tankless Water Heater", "wholesale_price": 1149.0, "retail_price": 1549.0},
        {"brand": "Rheem", "name": "RTEX-18 Electric Tankless Water Heater", "category": "Water Heater", "subcategory": "Tankless Water Heater", "wholesale_price": 429.0, "retail_price": 629.0},
        # Water-heater parts
        {"brand": "Watts", "name": "5 Gallon Thermal Expansion Tank", "category": "Water Heater", "subcategory": "Expansion Tank", "wholesale_price": 45.0, "retail_price": 79.0},
        {"brand": "Cash Acme", "name": "3/4 in TPR Valve", "category": "Water Heater", "subcategory": "TPR Valve", "wholesale_price": 19.0, "retail_price": 39.0},
        {"brand": "Camco", "name": "4500W Screw-In Heating Element", "category": "Water Heater", "subcategory": "Heating Element", "wholesale_price": 18.0, "retail_price": 34.0},
        {"brand": "Honeywell", "name": "Gas Water Heater Control Valve", "category": "Water Heater", "subcategory": "Gas Control Valve", "wholesale_price": 119.0, "retail_price": 199.0},
        {"brand": "Rheem", "name": "Upper Water Heater Thermostat", "category": "Water Heater", "subcategory": "Thermostat", "wholesale_price": 24.0, "retail_price": 45.0},
        {"brand": "Rheem", "name": "Magnesium Anode Rod 44 in", "category": "Water Heater", "subcategory": "Anode Rod", "wholesale_price": 29.0, "retail_price": 59.0},
        {"brand": "SharkBite", "name": "3/4 in x 18 in Flexible Water Connector", "category": "Water Heater", "subcategory": "Connector", "wholesale_price": 14.0, "retail_price": 29.0},
        {"brand": "Jones Stephens", "name": "24 in Water Heater Drain Pan", "category": "Water Heater", "subcategory": "Drain Pan", "wholesale_price": 22.0, "retail_price": 44.0},
        # Fixtures
        {"brand": "Moen", "name": "Single-Handle Pull-Down Kitchen Faucet", "category": "Fixtures", "subcategory": "Kitchen Faucet", "wholesale_price": 129.0, "retail_price": 239.0},
        {"brand": "Delta", "name": "Single-Handle Bathroom Faucet", "category": "Fixtures", "subcategory": "Bathroom Faucet", "wholesale_price": 89.0, "retail_price": 169.0},
        {"brand": "Kohler", "name": "2-Piece Comfort Height Toilet", "category": "Fixtures", "subcategory": "Toilet", "wholesale_price": 229.0, "retail_price": 379.0},
        {"brand": "American Standard", "name": "Round Front 2-Piece Toilet", "category": "Fixtures", "subcategory": "Toilet", "wholesale_price": 169.0, "retail_price": 299.0},
        {"brand": "InSinkErator", "name": "Badger 5 1/2 HP Garbage Disposal", "category": "Fixtures", "subcategory": "Garbage Disposal", "wholesale_price": 95.0, "retail_price": 169.0},
        {"brand": "InSinkErator", "name": "Evolution 3/4 HP Garbage Disposal", "category": "Fixtures", "subcategory": "Garbage Disposal", "wholesale_price": 189.0, "retail_price": 299.0},
        {"brand": "Moen", "name": "Posi-Temp Shower Valve", "category": "Fixtures", "subcategory": "Shower Valve", "wholesale_price": 79.0, "retail_price": 149.0},
        {"brand": "Delta", "name": "Multi-Function Shower Head", "category": "Fixtures", "subcategory": "Shower Head", "wholesale_price": 32.0, "retail_price": 69.0},
        {"brand": "Woodford", "name": "12 in Frost-Free Sillcock", "category": "Fixtures", "subcategory": "Outdoor Faucet", "wholesale_price": 31.0, "retail_price": 69.0},
        # Repair parts
        {"brand": "Fluidmaster", "name": "Universal Toilet Fill Valve", "category": "Fixtures", "subcategory": "Toilet Repair Part", "wholesale_price": 9.0, "retail_price": 19.0},
        {"brand": "Korky", "name": "Universal Toilet Flapper", "category": "Fixtures", "subcategory": "Toilet Repair Part", "wholesale_price": 6.0, "retail_price": 14.0},
        {"brand": "Oatey", "name": "Standard Wax Ring", "category": "Fixtures", "subcategory": "Toilet Repair Part", "wholesale_price": 4.0, "retail_price": 9.0},
        {"brand": "SharkBite", "name": "1/2 in Push-to-Connect Coupling", "category": "Pipe Repair", "subcategory": "Pipe Fitting", "wholesale_price": 10.0, "retail_price": 19.0},
        {"brand": "BrassCraft", "name": "1/4-Turn Angle Stop Valve", "category": "Pipe Repair", "subcategory": "Shutoff Valve", "wholesale_price": 10.0, "retail_price": 21.0},
        {"brand": "BrassCraft", "name": "3/8 in x 20 in Braided Supply Line", "category": "Pipe Repair", "subcategory": "Supply Line", "wholesale_price": 9.0, "retail_price": 19.0},
        {"brand": "Sioux Chief", "name": "Compression Straight Stop Valve", "category": "Pipe Repair", "subcategory": "Shutoff Valve", "wholesale_price": 12.0, "retail_price": 24.0},
        {"brand": "Apollo", "name": "1/2 in Ball Valve", "category": "Pipe Repair", "subcategory": "Ball Valve", "wholesale_price": 13.0, "retail_price": 29.0},
        {"brand": "NIBCO", "name": "3/4 in Ball Valve", "category": "Pipe Repair", "subcategory": "Ball Valve", "wholesale_price": 17.0, "retail_price": 34.0},
        {"brand": "SharkBite", "name": "3/4 in Push Coupling", "category": "Pipe Repair", "subcategory": "Pipe Fitting", "wholesale_price": 14.0, "retail_price": 27.0},
        {"brand": "Oatey", "name": "Pipe Joint Compound 8 oz", "category": "Pipe Repair", "subcategory": "Sealant", "wholesale_price": 5.0, "retail_price": 11.0},
        {"brand": "RectorSeal", "name": "PTFE Thread Seal Tape", "category": "Pipe Repair", "subcategory": "Sealant", "wholesale_price": 2.0, "retail_price": 5.0},
        {"brand": "General Wire", "name": "Hand Auger 25 ft", "category": "Drain Services", "subcategory": "Drain Tool", "wholesale_price": 39.0, "retail_price": 69.0},
        {"brand": "Ridgid", "name": "Closet Auger 3 ft", "category": "Drain Services", "subcategory": "Drain Tool", "wholesale_price": 34.0, "retail_price": 59.0},
        {"brand": "Hercules", "name": "Drain Cleaning Crystals", "category": "Drain Services", "subcategory": "Drain Consumable", "wholesale_price": 8.0, "retail_price": 16.0},
        {"brand": "Moen", "name": "Garbage Disposal Flange Kit", "category": "Fixtures", "subcategory": "Garbage Disposal Part", "wholesale_price": 18.0, "retail_price": 34.0},
        {"brand": "InSinkErator", "name": "Garbage Disposal Power Cord Kit", "category": "Fixtures", "subcategory": "Garbage Disposal Part", "wholesale_price": 14.0, "retail_price": 29.0},
        {"brand": "Fernco", "name": "2 in Flexible Coupling", "category": "Pipe Repair", "subcategory": "Pipe Fitting", "wholesale_price": 7.0, "retail_price": 15.0},
        {"brand": "Charlotte Pipe", "name": "3 in PVC Repair Coupling", "category": "Pipe Repair", "subcategory": "Pipe Fitting", "wholesale_price": 6.0, "retail_price": 13.0},
    ]


def main() -> None:
    supabase_url = require_env("SUPABASE_URL")
    service_role_key = require_env("SUPABASE_SERVICE_ROLE_KEY")
    openai_api_key = require_env("OPENAI_API_KEY")

    prepared: list[dict[str, Any]] = []
    for item in catalog_items():
        text = " | ".join(
            [
                f"brand={item['brand']}",
                f"name={item['name']}",
                f"category={item['category']}",
                f"subcategory={item['subcategory']}",
                f"wholesale={item['wholesale_price']}",
                f"retail={item['retail_price']}",
            ]
        )
        prepared.append(build_row(item, embed(openai_api_key, text)))

    upsert_rows(supabase_url, service_role_key, prepared)
    print(json.dumps({"seeded_rows": len(prepared), "target_table": "parts_catalog"}))


if __name__ == "__main__":
    main()
