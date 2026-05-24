#!/usr/bin/env python3
"""Validate local S400 secrets without printing secret values."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


HEX_RE = re.compile(r"^[0-9a-fA-F]+$")


def short_fingerprint(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:10]


def masked_mac(value: str) -> str:
    suffix = value.replace(":", "")[-4:].upper()
    return f"***:{suffix}" if suffix else "missing"


def validate_hex(value: str, length: int, label: str) -> list[str]:
    errors: list[str] = []
    if len(value) != length:
        errors.append(f"{label} must be {length} hex characters, got {len(value)}")
    if not HEX_RE.match(value):
        errors.append(f"{label} must contain only hex characters")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate secrets.local.json without revealing secrets.")
    parser.add_argument("--path", default="secrets.local.json", help="Path to local secrets file")
    args = parser.parse_args()

    path = Path(args.path)
    if not path.exists():
        print(f"Missing {path}. Create it from secrets.local.example.json.")
        return 2

    try:
        data: dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"Invalid JSON: {exc}", file=sys.stderr)
        return 2

    devices = data.get("devices")
    if not isinstance(devices, list) or not devices:
        print("No devices found in secrets file.", file=sys.stderr)
        return 2

    all_errors: list[str] = []
    for index, device in enumerate(devices, 1):
        if not isinstance(device, dict):
            all_errors.append(f"device {index}: must be an object")
            continue

        label = str(device.get("label") or f"device-{index}")
        bind_key = str(device.get("bind_key_hex") or "")
        token = str(device.get("login_token_hex") or "")
        real_mac = str(device.get("real_mac") or "")

        errors = []
        errors.extend(validate_hex(bind_key, 32, "bind_key_hex"))
        if token:
            errors.extend(validate_hex(token, 24, "login_token_hex"))
        if not real_mac or real_mac == "AA:BB:CC:DD:EE:FF":
            errors.append("real_mac must be filled from Xiaomi Cloud Tokens Extractor")

        if errors:
            for error in errors:
                all_errors.append(f"{label}: {error}")
            continue

        print(
            f"{label}: OK "
            f"(mac={masked_mac(real_mac)}, bind_key_fp={short_fingerprint(bind_key)}, "
            f"token_fp={short_fingerprint(token) if token else 'missing'})"
        )

    if all_errors:
        print("\nProblems:", file=sys.stderr)
        for error in all_errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
