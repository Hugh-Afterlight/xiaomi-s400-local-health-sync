#!/usr/bin/env python3
"""Append best parsed S400 measurements into a cumulative CSV ledger."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any


FIELDNAMES = [
    "measurement_id",
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


def row_score(row: dict[str, Any]) -> int:
    if row.get("completeness_score") is not None:
        return int(row["completeness_score"])
    fields = ["weight_kg", "impedance_ohm", "impedance_low_ohm", "heart_rate_bpm", "profile_id"]
    return sum(1 for field in fields if row.get(field) is not None)


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
        if current is None or row_score(row) > row_score(current) or int(row.get("packet_count") or 0) > int(current.get("packet_count") or 0):
            best[key] = row
    return list(best.values())


def measurement_id(row: dict[str, Any]) -> str:
    payload = "|".join(
        str(row.get(field) or "")
        for field in [
            "measured_at_utc",
            "device_label",
            "profile_id",
            "weight_kg",
            "impedance_ohm",
            "impedance_low_ohm",
            "heart_rate_bpm",
        ]
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]


def load_existing_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


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


def parse_timestamp(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def comparable_value(value: Any) -> str:
    if value is None:
        return ""
    return str(value)


def numeric_value(value: Any) -> float | None:
    if value in (None, ""):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def close_enough(left: Any, right: Any, tolerance: float) -> bool:
    left_number = numeric_value(left)
    right_number = numeric_value(right)
    if left_number is None or right_number is None:
        return comparable_value(left) == comparable_value(right)
    return abs(left_number - right_number) <= tolerance


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


def has_same_measurement_signature(left: dict[str, Any], right: dict[str, Any]) -> bool:
    if comparable_value(left.get("device_label")) != comparable_value(right.get("device_label")):
        return False
    if comparable_value(left.get("profile_id")) != comparable_value(right.get("profile_id")):
        return False
    return (
        close_enough(left.get("weight_kg"), right.get("weight_kg"), 0.1)
        and close_enough(left.get("impedance_ohm"), right.get("impedance_ohm"), 3.0)
        and close_enough(left.get("impedance_low_ohm"), right.get("impedance_low_ohm"), 3.0)
        and close_enough(left.get("heart_rate_bpm"), right.get("heart_rate_bpm"), 3.0)
    )


def is_near_duplicate(row: dict[str, Any], existing_rows: list[dict[str, Any]], window: timedelta) -> bool:
    measured_at = parse_timestamp(row.get("measured_at_local"))
    if measured_at is None:
        return False
    for existing in existing_rows:
        existing_at = parse_timestamp(existing.get("measured_at_local"))
        if existing_at is None:
            continue
        if abs(measured_at - existing_at) <= window and has_same_measurement_signature(row, existing):
            return True
    return False


def rewrite_ledger_if_needed(path: Path, rows: list[dict[str, Any]], profiles: list[dict[str, str]]) -> None:
    if not path.exists():
        return
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle)
        current_header = next(reader, [])
    if current_header == FIELDNAMES:
        return

    backup_path = path.with_suffix(path.suffix + ".bak")
    path.replace(backup_path)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            enriched = dict(row)
            enriched.update(classify_person(enriched, profiles))
            writer.writerow(enriched)


def main() -> int:
    parser = argparse.ArgumentParser(description="Append parsed S400 measurements into cumulative CSV ledger.")
    parser.add_argument("--input", required=True, help="Parsed measurement JSONL file")
    parser.add_argument("--ledger", default="data/exports/s400_measurements.csv")
    parser.add_argument("--profiles", default="profiles.local.csv", help="Optional local CSV with person_label,min_weight_kg,max_weight_kg")
    parser.add_argument("--dedupe-window-minutes", type=float, default=5.0)
    args = parser.parse_args()

    input_path = Path(args.input)
    ledger_path = Path(args.ledger)
    profiles = load_weight_profiles(Path(args.profiles))
    rows = [json.loads(line) for line in input_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    rows = choose_best(rows)

    existing_rows = load_existing_rows(ledger_path)
    rewrite_ledger_if_needed(ledger_path, existing_rows, profiles)
    existing_rows = load_existing_rows(ledger_path)
    existing_ids = {row["measurement_id"] for row in existing_rows if row.get("measurement_id")}
    dedupe_window = timedelta(minutes=args.dedupe_window_minutes)
    ledger_path.parent.mkdir(parents=True, exist_ok=True)
    should_write_header = not ledger_path.exists()
    appended = 0

    with ledger_path.open("a", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES, extrasaction="ignore")
        if should_write_header:
            writer.writeheader()
        for row in rows:
            row = dict(row)
            row.update(classify_person(row, profiles))
            row["measurement_id"] = measurement_id(row)
            row["completeness_score"] = row_score(row)
            if row["measurement_id"] in existing_ids:
                continue
            if is_near_duplicate(row, existing_rows, dedupe_window):
                continue
            writer.writerow(row)
            existing_ids.add(row["measurement_id"])
            existing_rows.append({field: comparable_value(row.get(field)) for field in FIELDNAMES})
            appended += 1

    print(f"Candidate rows: {len(rows)}")
    print(f"Appended rows: {appended}")
    print(f"Ledger: {ledger_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
