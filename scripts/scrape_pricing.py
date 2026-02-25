#!/usr/bin/env python3
"""
Scrape plumbing pricing guide data from Angi, HomeGuide, and Housecall Pro.

Output:
  scripts/scraped_pricing_raw.json
"""

from __future__ import annotations

import json
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

from bs4 import BeautifulSoup


PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_PATH = PROJECT_ROOT / "scripts" / "scraped_pricing_raw.json"


SOURCE_URLS = {
    "angi": [
        "https://www.angi.com/articles/plumber-cost.htm",
        "https://www.angi.com/articles/plumber-cost-to-fix-leaky-faucet.htm",
        "https://www.angi.com/articles/how-much-does-water-heater-installation-cost.htm",
        "https://www.angi.com/articles/emergency-plumber-cost.htm",
        "https://angi.com/articles/burst-pipe-repair-cost.htm",
        "https://www.angi.com/articles/what-cost-replace-water-shut-valve-supplies-water-refrigerator.htm",
        "https://angi.com/articles/how-much-does-installing-or-replacing-plumbing-pipes-cost.htm",
        "https://www.angi.com/articles/how-much-does-toilet-installation-cost.htm",
        "https://www.angi.com/articles/cost-to-replace-drain-pipes-in-house.htm",
        "https://angi.com/articles/sink-installation-cost.htm",
    ],
    "homeguide": [
        "https://homeguide.com/costs/plumber-cost",
        "https://homeguide.com/costs/water-heater-installation-cost",
        "https://homeguide.com/costs/tankless-water-heater-installation-cost",
        "https://homeguide.com/costs/garbage-disposal-installation-cost",
        "https://homeguide.com/costs/faucet-installation-cost",
        "https://homeguide.com/costs/toilet-installation-cost",
        "https://homeguide.com/costs/cost-to-unclog-snake-a-drain",
        "https://homeguide.com/costs/sump-pump-installation-cost",
        "https://homeguide.com/costs/burst-pipe-repair-cost",
        "https://homeguide.com/costs/emergency-plumber-cost",
        "https://homeguide.com/costs/water-heater-repair-cost",
        "https://homeguide.com/costs/toilet-repair-cost",
    ],
    "housecallpro": [
        "https://www.housecallpro.com/resources/marketing/how-to/how-to-price-plumbing-jobs/",
    ],
}


RANGE_RE = re.compile(
    r"\$\s*(\d{1,3}(?:,\d{3})*(?:\.\d+)?)\s*(?:-|–|to)\s*\$?\s*(\d{1,3}(?:,\d{3})*(?:\.\d+)?)"
)
SINGLE_PRICE_RE = re.compile(r"\$\s*(\d{1,3}(?:,\d{3})*(?:\.\d+)?)")
MULTISPACE_RE = re.compile(r"\s+")


@dataclass(frozen=True)
class PriceRow:
    service: str
    source: str
    source_url: str
    price_low: float
    price_high: float
    price_avg: float | None
    raw_text: str


def normalize_text(value: str) -> str:
    return MULTISPACE_RE.sub(" ", value).strip()


def parse_number(value: str) -> float:
    return float(value.replace(",", ""))


def extract_prices(text: str) -> tuple[float | None, float | None, float | None]:
    """
    Extract low/high and optional average from free text.
    """
    cleaned = normalize_text(text)
    range_match = RANGE_RE.search(cleaned)
    if range_match:
        low = parse_number(range_match.group(1))
        high = parse_number(range_match.group(2))
        midpoint = round((low + high) / 2.0, 2)
        return low, high, midpoint

    singles = SINGLE_PRICE_RE.findall(cleaned)
    if len(singles) == 1:
        value = parse_number(singles[0])
        return value, value, value
    if len(singles) >= 2:
        low = parse_number(singles[0])
        high = parse_number(singles[1])
        if low > high:
            low, high = high, low
        return low, high, round((low + high) / 2.0, 2)

    return None, None, None


def fetch_html(url: str, retries: int = 3, timeout_sec: int = 30) -> str:
    last_error: Exception | None = None
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/125.0.0.0 Safari/537.36"
        ),
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
        "Cache-Control": "no-cache",
    }
    last_status_403 = False
    for attempt in range(1, retries + 1):
        try:
            req = Request(url=url, headers=headers)
            with urlopen(req, timeout=timeout_sec) as response:
                return response.read().decode("utf-8", errors="ignore")
        except HTTPError as exc:
            if exc.code == 403:
                last_status_403 = True
            last_error = exc
            if attempt < retries:
                time.sleep(attempt * 1.5)
        except (URLError, TimeoutError) as exc:
            last_error = exc
            if attempt < retries:
                time.sleep(attempt * 1.5)
    if last_status_403:
        # Some sites block direct script traffic. Jina's reader endpoint often
        # provides a plaintext mirror that still includes pricing tables.
        fallback_url = f"https://r.jina.ai/http://{url.replace('https://', '').replace('http://', '')}"
        req = Request(url=fallback_url, headers=headers)
        with urlopen(req, timeout=timeout_sec) as response:
            return response.read().decode("utf-8", errors="ignore")
    raise RuntimeError(f"Failed to fetch {url}: {last_error}")


def parse_table_rows(source: str, source_url: str, soup: BeautifulSoup) -> Iterable[PriceRow]:
    for table in soup.find_all("table"):
        for tr in table.find_all("tr"):
            cells = [normalize_text(td.get_text(" ", strip=True)) for td in tr.find_all(["td", "th"])]
            if len(cells) < 2:
                continue
            joined = " | ".join([c for c in cells if c])
            low, high, avg = extract_prices(joined)
            if low is None or high is None:
                continue

            non_price_cells = [c for c in cells if not RANGE_RE.search(c) and len(SINGLE_PRICE_RE.findall(c)) < 2]
            service = non_price_cells[0] if non_price_cells else cells[0]
            if not service or service.lower() in {"job", "repair", "installation", "price range", "average cost"}:
                continue

            yield PriceRow(
                service=service,
                source=source,
                source_url=source_url,
                price_low=round(low, 2),
                price_high=round(high, 2),
                price_avg=round(avg, 2) if avg is not None else None,
                raw_text=joined[:500],
            )


def parse_pipe_lines(source: str, source_url: str, text: str) -> Iterable[PriceRow]:
    """
    Parse markdown-like rows from rendered article text.
    """
    for line in text.splitlines():
        line = normalize_text(line)
        if "|" not in line or "$" not in line:
            continue
        if line.startswith("| ---"):
            continue
        if line.lower().startswith("http"):
            continue

        parts = [normalize_text(part) for part in line.split("|") if normalize_text(part)]
        if len(parts) < 2:
            continue
        low, high, avg = extract_prices(line)
        if low is None or high is None:
            continue
        service = parts[0]
        if service.lower() in {"job", "service type", "plumbing labor price list", "plumbing services price list"}:
            continue

        yield PriceRow(
            service=service,
            source=source,
            source_url=source_url,
            price_low=round(low, 2),
            price_high=round(high, 2),
            price_avg=round(avg, 2) if avg is not None else None,
            raw_text=line[:500],
        )


def infer_source(url: str) -> str:
    host = urlparse(url).netloc.lower()
    if "angi.com" in host:
        return "angi"
    if "homeguide.com" in host:
        return "homeguide"
    if "housecallpro.com" in host:
        return "housecallpro"
    return "unknown"


def scrape_url(source: str, url: str) -> tuple[list[PriceRow], str | None]:
    try:
        html = fetch_html(url)
        soup = BeautifulSoup(html, "html.parser")
        visible_text = soup.get_text("\n", strip=True)

        rows = list(parse_table_rows(source, url, soup))
        rows.extend(parse_pipe_lines(source, url, visible_text))

        # Deduplicate within a page.
        deduped: dict[tuple[str, float, float, str], PriceRow] = {}
        for row in rows:
            key = (row.service.lower(), row.price_low, row.price_high, row.raw_text.lower())
            deduped[key] = row
        return list(deduped.values()), None
    except Exception as exc:  # noqa: BLE001
        return [], str(exc)


def main() -> int:
    all_rows: list[PriceRow] = []
    errors: list[dict[str, str]] = []

    total_urls = sum(len(urls) for urls in SOURCE_URLS.values())
    print(f"Scraping {total_urls} URLs...")

    for source, urls in SOURCE_URLS.items():
        for index, url in enumerate(urls, start=1):
            normalized_source = infer_source(url) if source == "unknown" else source
            print(f"[{normalized_source}] ({index}/{len(urls)}) {url}")
            rows, error = scrape_url(normalized_source, url)
            if error:
                print(f"  ! error: {error}")
                errors.append({"source": normalized_source, "url": url, "error": error})
            else:
                print(f"  + extracted rows: {len(rows)}")
                all_rows.extend(rows)
            time.sleep(2.0)

    # Deduplicate globally.
    deduped_rows: dict[tuple[str, str, str, float, float], PriceRow] = {}
    for row in all_rows:
        key = (
            row.source,
            row.source_url,
            row.service.lower(),
            row.price_low,
            row.price_high,
        )
        deduped_rows[key] = row

    serialized_rows = [
        {
            "service": row.service,
            "source": row.source,
            "source_url": row.source_url,
            "price_low": row.price_low,
            "price_high": row.price_high,
            "price_avg": row.price_avg,
            "raw_text": row.raw_text,
        }
        for row in sorted(
            deduped_rows.values(),
            key=lambda r: (r.source, r.service.lower(), r.price_low, r.price_high),
        )
    ]

    payload = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "sources": SOURCE_URLS,
        "row_count": len(serialized_rows),
        "error_count": len(errors),
        "errors": errors,
        "rows": serialized_rows,
    }

    OUTPUT_PATH.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    counts_by_source: dict[str, int] = {}
    for row in serialized_rows:
        counts_by_source[row["source"]] = counts_by_source.get(row["source"], 0) + 1

    print(f"\nWrote {OUTPUT_PATH}")
    print(f"Rows: {len(serialized_rows)}")
    print(f"Counts by source: {counts_by_source}")
    print(f"Errors: {len(errors)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
