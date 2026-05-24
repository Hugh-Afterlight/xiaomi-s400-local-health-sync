#!/usr/bin/env python3
"""Decode Xiaomi S400 FE95 observations with xiaomi-ble."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from collections import OrderedDict
from datetime import datetime
from pathlib import Path
from typing import Any


FE95_UUID = "0000fe95-0000-1000-8000-00805f9b34fb"


def short_hash(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:12]


def latest_observation() -> Path | None:
    files = sorted(Path("data/ble_observations").glob("*.jsonl"))
    return files[-1] if files else None


def load_secret(path: Path, label: str) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    for device in data.get("devices", []):
        if device.get("label") == label:
            return device
    raise ValueError(f"Device label not found in {path}: {label}")


def sensor_values(update: Any) -> dict[str, Any]:
    values: dict[str, Any] = {}
    for sensor in getattr(update, "entity_values", {}).values():
        name = str(getattr(sensor, "name", "") or "").casefold()
        native_value = getattr(sensor, "native_value", None)
        if name == "mass":
            values["weight_kg"] = native_value
        elif name == "impedance":
            values["impedance_ohm"] = native_value
        elif name == "impedance low":
            values["impedance_low_ohm"] = native_value
        elif name == "profile id":
            values["profile_id"] = native_value
        elif name == "heart rate":
            values["heart_rate_bpm"] = native_value
        elif name == "signal strength":
            values["rssi"] = native_value
    return values


def measurement_key(row: dict[str, Any]) -> tuple[Any, ...]:
    return (
        row.get("device_label"),
        row.get("weight_kg"),
        row.get("impedance_ohm"),
        row.get("impedance_low_ohm"),
        row.get("heart_rate_bpm"),
        row.get("profile_id"),
    )


def completeness_score(row: dict[str, Any]) -> int:
    fields = [
        "weight_kg",
        "impedance_ohm",
        "impedance_low_ohm",
        "heart_rate_bpm",
        "profile_id",
    ]
    return sum(1 for field in fields if row.get(field) is not None)


def main() -> int:
    parser = argparse.ArgumentParser(description="Decode S400 BLE observations into measurement JSONL.")
    parser.add_argument("--input", help="Observation JSONL file. Defaults to latest data/ble_observations/*.jsonl")
    parser.add_argument("--secrets", default="secrets.local.json")
    parser.add_argument("--device-label", default="s400-main")
    parser.add_argument("--output-dir", default="data/parsed_measurements")
    args = parser.parse_args()

    input_path = Path(args.input) if args.input else latest_observation()
    if input_path is None or not input_path.exists():
        print("No observation JSONL file found.", file=sys.stderr)
        return 2

    secret = load_secret(Path(args.secrets), args.device_label)
    bind_key = bytes.fromhex(str(secret["bind_key_hex"]))
    real_mac = str(secret["real_mac"])
    corebluetooth_id = str(secret.get("corebluetooth_id") or "")
    device_label = str(secret.get("label") or args.device_label)

    try:
        from home_assistant_bluetooth import BluetoothServiceInfo
        from xiaomi_ble.parser import XiaomiBluetoothDeviceData
    except ImportError as exc:
        print(f"Missing parser dependency: {exc}", file=sys.stderr)
        print("Install with: tools/xiaomi-cloud-tokens-extractor/.venv/bin/python -m pip install 'xiaomi-ble>=1.12,<2'", file=sys.stderr)
        return 2

    decoder = XiaomiBluetoothDeviceData(bind_key)
    decoded: OrderedDict[tuple[Any, ...], dict[str, Any]] = OrderedDict()
    packet_count = 0
    decoded_packet_count = 0

    for line_no, line in enumerate(input_path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        event = json.loads(line)
        device = event.get("device", {})
        advertisement = event.get("advertisement", {})
        if corebluetooth_id and device.get("id") != corebluetooth_id:
            continue
        service_data = advertisement.get("service_data") or {}
        payload_hex = service_data.get("fe95")
        if not payload_hex:
            continue

        packet_count += 1
        info = BluetoothServiceInfo(
            name=device.get("name") or "Mijia Scale S400",
            address=real_mac,
            rssi=int(advertisement.get("rssi") or 0),
            manufacturer_data={},
            service_data={FE95_UUID: bytes.fromhex(payload_hex)},
            service_uuids=[],
            source="local-jsonl",
        )
        update = decoder.update(info)
        values = sensor_values(update)
        if not values.get("weight_kg"):
            continue

        decoded_packet_count += 1
        row = {
            "schema_version": 1,
            "source_file": str(input_path),
            "source_line": line_no,
            "device_label": device_label,
            "device_model": getattr(decoder, "device_type", None),
            "measured_at_local": event.get("seen_at_local"),
            "measured_at_utc": event.get("seen_at_utc"),
            "real_mac": real_mac,
            "corebluetooth_id": device.get("id"),
            "parser": "xiaomi-ble",
            "parser_bind_key_fingerprint": short_hash(str(secret["bind_key_hex"])),
            **values,
        }
        key = measurement_key(row)
        if key in decoded:
            decoded[key]["last_seen_local"] = row["measured_at_local"]
            decoded[key]["packet_count"] += 1
        else:
            row["last_seen_local"] = row["measured_at_local"]
            row["packet_count"] = 1
            row["completeness_score"] = completeness_score(row)
            decoded[key] = row

    print(f"Input packets for S400: {packet_count}")
    print(f"Decoded measurement packets: {decoded_packet_count}")
    print(f"Unique measurements: {len(decoded)}")
    if not decoded:
        print("No decoded measurements found.")
        return 1

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    output_path = output_dir / f"s400_measurements_{stamp}.jsonl"
    with output_path.open("w", encoding="utf-8") as handle:
        for row in decoded.values():
            handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")
    print(f"Output: {output_path}")
    for row in decoded.values():
        print(
            "Measurement: "
            f"weight={row.get('weight_kg')}kg, "
            f"impedance={row.get('impedance_ohm')}ohm, "
            f"impedance_low={row.get('impedance_low_ohm')}ohm, "
            f"heart_rate={row.get('heart_rate_bpm')}, "
            f"profile={row.get('profile_id')}, "
            f"score={row.get('completeness_score')}, "
            f"packets={row.get('packet_count')}"
        )

    if not decoder.bindkey_verified:
        print("Warning: bind key was not verified by any encrypted payload.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
