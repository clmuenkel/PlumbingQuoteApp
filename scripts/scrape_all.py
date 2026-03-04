#!/usr/bin/env python3
"""
Run all pricing ingestion scripts with error isolation and summary output.
"""

from __future__ import annotations

import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass
class ScriptResult:
    name: str
    command: list[str]
    ok: bool
    exit_code: int
    output_tail: str


def run_script(script_path: Path, extra_args: list[str] | None = None) -> ScriptResult:
    cmd = [sys.executable, str(script_path)]
    if extra_args:
        cmd.extend(extra_args)
    proc = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=os.environ.copy(),
    )
    lines = [ln for ln in proc.stdout.strip().splitlines() if ln.strip()]
    output_tail = "\n".join(lines[-12:]) if lines else ""
    return ScriptResult(
        name=script_path.name,
        command=cmd,
        ok=proc.returncode == 0,
        exit_code=proc.returncode,
        output_tail=output_tail,
    )


def main() -> None:
    script_dir = Path(__file__).resolve().parent
    scripts = [
        (script_dir / "scrape_angi_dfw.py", []),
        (script_dir / "scrape_slab_leak_dfw.py", []),
        # (script_dir / "scrape_supplyhouse.py", ["--max-pages", "2", "--max-per-page", "35"]),
        (script_dir / "scrape_parts_homedepot.py", ["--max-pages", "2", "--max-per-page", "35"]),
        (script_dir / "scrape_parts_lowes.py", ["--max-pages", "2", "--max-per-page", "35"]),
        (script_dir / "scrape_fixr.py", []),
        (script_dir / "scrape_homeguide.py", []),
        (script_dir / "scrape_costhelper.py", []),
        (script_dir / "scrape_promatcher.py", []),
        (script_dir / "fetch_bls_labor.py", []),
        (script_dir / "seed_price_book_from_industry.py", []),
    ]

    results: list[ScriptResult] = []
    for script_path, args in scripts:
        if not script_path.exists():
            results.append(
                ScriptResult(
                    name=script_path.name,
                    command=[sys.executable, str(script_path), *args],
                    ok=False,
                    exit_code=127,
                    output_tail="Script file not found.",
                )
            )
            continue
        print(f"\n[RUN] {script_path.name} {' '.join(args)}".strip())
        result = run_script(script_path, args)
        results.append(result)
        if result.output_tail:
            print(result.output_tail)
        print(f"[STATUS] {script_path.name} exit={result.exit_code}")

    ok_count = sum(1 for r in results if r.ok)
    fail_count = len(results) - ok_count
    print("\n=== INGEST SUMMARY ===")
    for r in results:
        status = "OK" if r.ok else "FAIL"
        print(f"{status}  {r.name} (exit={r.exit_code})")
    print(f"TOTAL: {len(results)} scripts, {ok_count} ok, {fail_count} failed")

    if fail_count:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
