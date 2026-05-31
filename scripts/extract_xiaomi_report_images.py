#!/usr/bin/env python3
"""Extract Xiaomi Home S400 official report screenshots into CSV.

This is a semi-automatic path for reports that Xiaomi Home can show but the
scale does not expose directly over BLE. It uses macOS Vision OCR through the
companion Swift script, then parses the known Xiaomi S400 report layout.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


BASE = Path(__file__).resolve().parents[1]
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".heic", ".webp"}

FIELDNAMES = [
    "report_id",
    "source_file",
    "report_user_name",
    "measured_at_local",
    "matched_measurement_id",
    "matched_person_label",
    "match_confidence",
    "weight_kg",
    "heart_rate_bpm",
    "bmi",
    "body_score",
    "body_water_mass_kg",
    "body_water_pct",
    "body_fat_pct",
    "fat_mass_kg",
    "protein_mass_kg",
    "protein_pct",
    "muscle_mass_kg",
    "muscle_pct",
    "bone_mineral_mass_kg",
    "bone_mineral_pct",
    "visceral_fat_rating",
    "bmr_kcal",
    "lean_body_mass_kg",
    "body_type",
    "estimated_waist_hip_ratio",
    "body_age",
    "skeletal_muscle_mass_kg",
    "weight_control_kg",
    "muscle_control_kg",
    "fat_control_kg",
    "standard_weight_kg",
    "source",
    "notes",
]


@dataclass
class MatchResult:
    measurement_id: str = ""
    person_label: str = ""
    confidence: str = ""


def find_google_drive_root() -> Path | None:
    cloud = Path.home() / "Library" / "CloudStorage"
    for pattern in ("GoogleDrive-*/我的云端硬盘", "GoogleDrive-*/My Drive"):
        for candidate in cloud.glob(pattern):
            if candidate.is_dir():
                return candidate
    legacy = Path.home() / "Google Drive"
    if legacy.is_dir():
        return legacy
    return None


def default_input_dir() -> Path:
    root = find_google_drive_root()
    if root:
        return root / "Health Auto Export" / "s400 图片报告"
    return BASE / "data" / "official_report_images"


def default_drive_output() -> Path | None:
    root = find_google_drive_root()
    if root:
        return root / "Health Auto Export" / "S400 Health Data" / "s400_official_reports.csv"
    return None


def image_files(input_dir: Path) -> list[Path]:
    if not input_dir.is_dir():
        return []
    return sorted(
        path
        for path in input_dir.iterdir()
        if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS
    )


def ocr_image(image_path: Path) -> list[str]:
    script = BASE / "scripts" / "ocr_image_text.swift"
    result = subprocess.run(
        ["swift", str(script), str(image_path)],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"OCR failed for {image_path}")
    try:
        rows = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"OCR returned invalid JSON for {image_path}: {exc}") from exc
    return [row.get("text", "").strip() for row in rows if row.get("text", "").strip()]


def numbers(text: str) -> list[float]:
    cleaned = (
        text.replace("−", "-")
        .replace("一", "-")
        .replace("J", "↓")
        .replace("M", "↓")
        .replace("O", "0")
    )
    cleaned = re.sub(r"(?<=\d\.)[gG](?=$|[^0-9A-Za-z])", "9", cleaned)
    return [float(value) for value in re.findall(r"-?\d+(?:\.\d+)?", cleaned)]


def first_number(text: str) -> float | None:
    values = numbers(text)
    return values[0] if values else None


def value_near_label(lines: list[str], label: str, *, window: int = 3) -> float | None:
    for index, line in enumerate(lines):
        if label not in line:
            continue
        same_line = first_number(line)
        if same_line is not None:
            return same_line
        for back in range(1, window + 1):
            if index - back < 0:
                break
            value = first_number(lines[index - back])
            if value is not None:
                return value
        for forward in range(1, window + 1):
            if index + forward >= len(lines):
                break
            value = first_number(lines[index + forward])
            if value is not None:
                return value
    return None


def value_after_label(lines: list[str], label: str, *, window: int = 3) -> float | None:
    for index, line in enumerate(lines):
        if label not in line:
            continue
        same_line = first_number(line)
        if same_line is not None:
            return same_line
        for forward in range(1, window + 1):
            if index + forward >= len(lines):
                break
            value = first_number(lines[index + forward])
            if value is not None:
                return value
    return None


def text_near_label(lines: list[str], label: str) -> str:
    for line in lines:
        if label in line:
            parts = re.split(r"[:：]", line, maxsplit=1)
            if len(parts) == 2:
                return parts[1].strip()
    return ""


def parse_timestamp(lines: list[str]) -> tuple[str, str]:
    for index, line in enumerate(lines):
        match = re.search(r"(\d{4})/(\d{2})/(\d{2})\s+(\d{2}):(\d{2})", line)
        if match:
            year, month, day, hour, minute = match.groups()
            measured_at = f"{year}-{month}-{day}T{hour}:{minute}:00+08:00"
            user_name = lines[index - 1] if index > 0 else ""
            return measured_at, user_name
    return "", ""


def parse_weight(lines: list[str], measured_at: str) -> float | None:
    if not measured_at:
        return None
    timestamp_line = measured_at[:10].replace("-", "/")
    for index, line in enumerate(lines):
        if timestamp_line in line:
            for candidate in lines[index + 1 : index + 6]:
                value = first_number(candidate)
                if value is not None and 20 <= value <= 250:
                    return value
    return None


def derive_body_type(bmi: float | None, body_fat_pct: float | None) -> str:
    if bmi is None or body_fat_pct is None:
        return ""
    # Xiaomi's report chart uses BMI bands around 18.5/24 and body-fat bands
    # around 10%/20%. This keeps only the clear top-right case deterministic.
    if bmi >= 24 and body_fat_pct >= 20:
        return "肥胖"
    return ""


def parse_report(image_path: Path, lines: list[str], ledger_rows: list[dict[str, str]]) -> dict[str, str]:
    measured_at, user_name = parse_timestamp(lines)
    weight = parse_weight(lines, measured_at)
    body_fat_pct = value_near_label(lines, "体脂率")
    bmi = value_near_label(lines, "BMI")

    values: dict[str, float | None] = {
        "heart_rate_bpm": value_near_label(lines, "心率"),
        "bmi": bmi,
        "body_score": value_after_label(lines, "身体得分"),
        "body_water_mass_kg": value_near_label(lines, "体水分量"),
        "body_water_pct": value_near_label(lines, "身体水分"),
        "body_fat_pct": body_fat_pct,
        "fat_mass_kg": value_near_label(lines, "脂肪量"),
        "protein_mass_kg": value_near_label(lines, "蛋白质量"),
        "protein_pct": value_near_label(lines, "蛋白质率"),
        "muscle_mass_kg": value_near_label(lines, "肌肉量"),
        "muscle_pct": value_near_label(lines, "肌肉率"),
        "bone_mineral_mass_kg": value_near_label(lines, "骨盐量"),
        "bone_mineral_pct": value_near_label(lines, "骨盐率"),
        "visceral_fat_rating": value_near_label(lines, "内脏脂肪等级"),
        "bmr_kcal": value_near_label(lines, "基础代谢率"),
        "lean_body_mass_kg": value_near_label(lines, "去脂体重"),
        "estimated_waist_hip_ratio": value_near_label(lines, "推测腰臀比"),
        "body_age": value_near_label(lines, "身体年龄"),
        "skeletal_muscle_mass_kg": value_near_label(lines, "骨骼肌量"),
        "weight_control_kg": value_near_label(lines, "体重控制"),
        "fat_control_kg": value_near_label(lines, "脂肪控制"),
        "standard_weight_kg": value_near_label(lines, "标准体重"),
    }

    match = match_local_measurement(measured_at, weight, ledger_rows)
    digest = hashlib.sha256(image_path.read_bytes()).hexdigest()[:16]

    row = {field: "" for field in FIELDNAMES}
    row.update(
        {
            "report_id": digest,
            "source_file": image_path.name,
            "report_user_name": user_name,
            "measured_at_local": measured_at,
            "matched_measurement_id": match.measurement_id,
            "matched_person_label": match.person_label,
            "match_confidence": match.confidence,
            "weight_kg": format_number(weight),
            "body_type": derive_body_type(bmi, body_fat_pct),
            "muscle_control_kg": text_near_label(lines, "肌肉控制"),
            "source": "Xiaomi Home screenshot OCR",
        }
    )
    for key, value in values.items():
        row[key] = format_number(value)
    return row


def format_number(value: float | None) -> str:
    if value is None:
        return ""
    if float(value).is_integer():
        return str(int(value))
    return f"{value:.3f}".rstrip("0").rstrip(".")


def parse_dt(value: str) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None


def load_ledger_rows(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def normalize_report_row(row: dict[str, str]) -> dict[str, str]:
    return {field: row.get(field, "") for field in FIELDNAMES}


def load_existing_report_rows(local_output: Path, drive_output: Path | None) -> dict[str, dict[str, str]]:
    rows: dict[str, dict[str, str]] = {}
    for path in (drive_output, local_output):
        if not path or not path.is_file():
            continue
        with path.open(newline="", encoding="utf-8") as handle:
            for index, row in enumerate(csv.DictReader(handle)):
                source_file = row.get("source_file", "")
                fallback_key = row.get("report_id", "") or f"{path.name}:{index}"
                key = source_file or f"report:{fallback_key}"
                rows[key] = normalize_report_row(row)
    return rows


def match_local_measurement(
    measured_at: str, weight: float | None, ledger_rows: list[dict[str, str]]
) -> MatchResult:
    measured_dt = parse_dt(measured_at)
    if measured_dt is None or weight is None:
        return MatchResult()
    if measured_dt.tzinfo is None:
        measured_dt = measured_dt.replace(tzinfo=timezone.utc)

    best: tuple[float, dict[str, str]] | None = None
    for row in ledger_rows:
        local_dt = parse_dt(row.get("measured_at_local", ""))
        if local_dt is None:
            continue
        try:
            row_weight = float(row.get("weight_kg", ""))
        except ValueError:
            continue
        seconds = abs((local_dt - measured_dt).total_seconds())
        weight_diff = abs(row_weight - weight)
        if seconds <= 300 and weight_diff <= 0.5:
            score = seconds + weight_diff * 120
            if best is None or score < best[0]:
                best = (score, row)

    if best is None:
        return MatchResult()
    row = best[1]
    return MatchResult(
        measurement_id=row.get("measurement_id", ""),
        person_label=row.get("person_label", ""),
        confidence="high",
    )


def write_csv(path: Path, rows: Iterable[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)
    path.chmod(0o600)


def unique_archive_path(source_path: Path, archive_dir: Path) -> Path:
    target = archive_dir / source_path.name
    if not target.exists():
        return target

    digest = hashlib.sha256(source_path.read_bytes()).hexdigest()[:8]
    target = archive_dir / f"{source_path.stem}-{digest}{source_path.suffix}"
    if not target.exists():
        return target

    counter = 2
    while True:
        numbered = archive_dir / f"{source_path.stem}-{digest}-{counter}{source_path.suffix}"
        if not numbered.exists():
            return numbered
        counter += 1


def archive_images(image_paths: Iterable[Path], archive_dir: Path) -> list[Path]:
    archive_dir.mkdir(parents=True, exist_ok=True)
    archived: list[Path] = []
    for image_path in image_paths:
        if not image_path.exists():
            continue
        target = unique_archive_path(image_path, archive_dir)
        shutil.move(str(image_path), str(target))
        target.chmod(0o600)
        archived.append(target)
    return archived


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=Path, default=default_input_dir())
    parser.add_argument("--local-output", type=Path, default=BASE / "data" / "exports" / "s400_official_reports.csv")
    parser.add_argument("--drive-output", type=Path, default=default_drive_output())
    parser.add_argument("--ledger", type=Path, default=BASE / "data" / "exports" / "s400_measurements.csv")
    parser.add_argument("--archive-dir", type=Path, default=None)
    parser.add_argument("--no-archive", action="store_true")
    parser.add_argument("--dump-ocr", action="store_true")
    parser.add_argument(
        "--reprocess-all",
        action="store_true",
        help="Ignore existing source_file rows and OCR every image again.",
    )
    args = parser.parse_args()

    images = image_files(args.input_dir)
    if not images:
        print(f"No pending report images found in: {args.input_dir}")
        return 0

    existing_rows = {} if args.reprocess_all else load_existing_report_rows(args.local_output, args.drive_output)
    seen_source_files = {
        row["source_file"] for row in existing_rows.values() if row.get("source_file")
    }
    skipped_existing: list[Path] = []
    processed_new: list[Path] = []
    rows_by_key = dict(existing_rows)

    ledger_rows = load_ledger_rows(args.ledger)
    for image_path in images:
        if image_path.name in seen_source_files:
            skipped_existing.append(image_path)
            continue

        lines = ocr_image(image_path)
        if args.dump_ocr:
            print(f"--- {image_path.name} ---")
            for line in lines:
                print(line)
        row = parse_report(image_path, lines, ledger_rows)
        rows_by_key[image_path.name] = row
        processed_new.append(image_path)

    rows = list(rows_by_key.values())
    rows.sort(key=lambda item: item.get("measured_at_local", ""))
    write_csv(args.local_output, rows)
    print(f"Local official report CSV: {args.local_output}")

    if args.drive_output:
        write_csv(args.drive_output, rows)
        print(f"Google Drive official report CSV: {args.drive_output}")

    archived: list[Path] = []
    if not args.no_archive:
        archive_dir = args.archive_dir or (args.input_dir / "存档")
        archived = archive_images([*processed_new, *skipped_existing], archive_dir)
        print(f"Archived images: {len(archived)}")
        print(f"Archive folder: {archive_dir}")

    print(f"Total reports in CSV: {len(rows)}")
    print(f"New images processed: {len(processed_new)}")
    print(f"Existing images skipped by filename: {len(skipped_existing)}")
    for path in processed_new:
        print(f"Processed image: {path.name}")
    for path in skipped_existing[:20]:
        print(f"Skipped existing image: {path.name}")
    if len(skipped_existing) > 20:
        print(f"Skipped existing image: ... {len(skipped_existing) - 20} more")
    for path in archived[:20]:
        print(f"Archived image: {path.name}")
    if len(archived) > 20:
        print(f"Archived image: ... {len(archived) - 20} more")

    for row in rows:
        print(
            "Report: "
            f"{row['measured_at_local']} "
            f"weight={row['weight_kg']}kg "
            f"body_fat={row['body_fat_pct']}% "
            f"matched={row['matched_measurement_id'] or 'no'}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
