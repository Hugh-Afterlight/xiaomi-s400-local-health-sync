#!/usr/bin/env python3
"""Export parsed S400 measurement JSONL to a simple CSV file."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


FIELDNAMES = [
    "measured_at_local",
    "device_label",
    "profile_id",
    "person_label",
    "person_match_method",
    "person_match_confidence",
    "weight_kg",
    "impedance_ohm",
    "impedance_low_ohm",
    "heart_rate_bpm",
    "rssi",
    "packet_count",
    "completeness_score",
    "device_model",
    "parser",
]

PROFILE_FIELDS = ["person_label", "min_weight_kg", "max_weight_kg"]


def latest_parsed() -> Path | None:
    files = sorted(Path("data/parsed_measurements").glob("s400_measurements_*.jsonl"))
    return files[-1] if files else None


def load_weight_profiles(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if not reader.fieldnames:
            return []
        missing = [field for field in PROFILE_FIELDS if field not in reader.fieldnames]
        if missing:
            raise SystemExit(f"Profile file {path} is missing columns: {', '.join(missing)}")
        return [row for row in reader if row.get("person_label")]


def row_score(row: dict[str, Any]) -> int:
    if row.get("completeness_score") is not None:
        return int(row["completeness_score"])
    fields = ["weight_kg", "impedance_ohm", "impedance_low_ohm", "heart_rate_bpm", "profile_id"]
    return sum(1 for field in fields if row.get(field) is not None)


def numeric_value(value: Any) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def classify_person(row: dict[str, Any], profiles: list[dict[str, str]]) -> dict[str, str]:
    weight = numeric_value(row.get("weight_kg"))
    if weight is None or not profiles:
        return {"person_label": "unknown", "person_match_method": "none", "person_match_confidence": "low"}

    matches: list[dict[str, str]] = []
    for profile in profiles:
        min_weight = numeric_value(profile.get("min_weight_kg"))
        max_weight = numeric_value(profile.get("max_weight_kg"))
        if min_weight is not None and max_weight is not None and min_weight <= weight < max_weight:
            matches.append(profile)
    if len(matches) == 1:
        return {
            "person_label": str(matches[0].get("person_label") or "unknown"),
            "person_match_method": "weight_range",
            "person_match_confidence": "high",
        }
    if len(matches) > 1:
        return {"person_label": "ambiguous", "person_match_method": "weight_range_overlap", "person_match_confidence": "low"}
    return {"person_label": "unknown", "person_match_method": "weight_range_miss", "person_match_confidence": "low"}


def group_key(row: dict[str, Any]) -> tuple[Any, ...]:
    return (
        row.get("device_label"),
        row.get("profile_id"),
        row.get("weight_kg"),
        row.get("impedance_ohm"),
    )


def choose_best(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    best: dict[tuple[Any, ...], dict[str, Any]] = {}
    for row in rows:
        key = group_key(row)
        current = best.get(key)
        if current is None or row_score(row) > row_score(current) or row.get("packet_count", 0) > current.get("packet_count", 0):
            best[key] = row
    return list(best.values())


def main() -> int:
    parser = argparse.ArgumentParser(description="Export parsed S400 measurements to CSV.")
    parser.add_argument("--input", help="Parsed JSONL file. Defaults to latest parsed measurement file.")
    parser.add_argument("--output-dir", default="data/exports")
    parser.add_argument("--profiles", default="profiles.local.csv", help="Optional local CSV with person_label,min_weight_kg,max_weight_kg")
    parser.add_argument("--all-rows", action="store_true", help="Export every parsed row instead of the best row per measurement.")
    args = parser.parse_args()

    input_path = Path(args.input) if args.input else latest_parsed()
    if input_path is None or not input_path.exists():
        raise SystemExit("No parsed measurement JSONL found.")

    rows = [json.loads(line) for line in input_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    profiles = load_weight_profiles(Path(args.profiles))
    rows_to_write = rows if args.all_rows else choose_best(rows)

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{input_path.stem}.csv"

    with output_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, extrasaction="ignore")
        writer.writeheader()
        for row in rows_to_write:
            row = dict(row)
            row.update(classify_person(row, profiles))
            row["completeness_score"] = row_score(row)
            writer.writerow(row)

    print(f"Input rows: {len(rows)}")
    print(f"CSV rows: {len(rows_to_write)}")
    print(f"Output: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
