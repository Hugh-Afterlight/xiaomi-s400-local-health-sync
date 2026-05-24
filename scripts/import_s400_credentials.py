#!/usr/bin/env python3
"""Import S400 credentials from Xiaomi Cloud Tokens Extractor JSON output."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
from datetime import date
from pathlib import Path
from typing import Any


HEX_RE = re.compile(r"^[0-9a-fA-F]+$")


def fp(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:10]


def normalize_mac(value: str) -> str:
    cleaned = re.sub(r"[^0-9a-fA-F]", "", value)
    if len(cleaned) != 12:
        return value.upper()
    return ":".join(cleaned[i : i + 2] for i in range(0, 12, 2)).upper()


def iter_devices(raw: Any) -> list[dict[str, Any]]:
    roots = raw if isinstance(raw, list) else [raw]
    found: list[dict[str, Any]] = []
    for server_block in roots:
        if not isinstance(server_block, dict):
            continue
        server = server_block.get("server", "")
        for home in server_block.get("homes", []) or []:
            for device in home.get("devices", []) or []:
                if isinstance(device, dict):
                    item = dict(device)
                    item["_server"] = server
                    found.append(item)
    return found


def score_device(device: dict[str, Any], suffix: str) -> int:
    name = str(device.get("name") or "").casefold()
    model = str(device.get("model") or "").casefold()
    mac = str(device.get("mac") or "").replace(":", "").casefold()
    did = str(device.get("did") or "").casefold()
    score = 0
    if "s400" in name:
        score += 5
    if "s400" in model or "mjtzc01ym" in model or "yunmai.scales.ms103" in model or "yunmai.scales.ms104" in model:
        score += 5
    if suffix and suffix.casefold() in name:
        score += 3
    if suffix and mac.endswith(suffix.casefold()):
        score += 4
    if did.startswith("blt"):
        score += 1
    if (device.get("BLE_DATA") or {}).get("beaconkey"):
        score += 5
    return score


def validate_hex(value: str, length: int, label: str) -> None:
    if len(value) != length or not HEX_RE.match(value):
        raise ValueError(f"{label} must be {length} hex characters")


def main() -> int:
    parser = argparse.ArgumentParser(description="Create secrets.local.json from Xiaomi token extractor output.")
    parser.add_argument("--input", required=True, help="Path to token extractor JSON output")
    parser.add_argument("--output", default="secrets.local.json", help="Where to write local secrets")
    parser.add_argument("--name-suffix", default="", help="Optional S400 name/MAC suffix observed by scanner")
    parser.add_argument("--corebluetooth-id", default="", help="Optional macOS CoreBluetooth identifier for this Mac")
    args = parser.parse_args()

    raw_path = Path(args.input)
    if not raw_path.exists():
        print(f"Missing input file: {raw_path}", file=sys.stderr)
        return 2

    raw = json.loads(raw_path.read_text(encoding="utf-8"))
    devices = iter_devices(raw)
    candidates = sorted(
        ((score_device(device, args.name_suffix), device) for device in devices),
        key=lambda item: item[0],
        reverse=True,
    )
    candidates = [item for item in candidates if item[0] > 0]
    if not candidates:
        print("No likely S400 device found in extractor output.", file=sys.stderr)
        return 1

    score, device = candidates[0]
    beaconkey = str((device.get("BLE_DATA") or {}).get("beaconkey") or "")
    if not beaconkey:
        print("Selected S400 candidate does not include BLE_DATA.beaconkey.", file=sys.stderr)
        return 1
    validate_hex(beaconkey, 32, "BLE KEY")

    mac = normalize_mac(str(device.get("mac") or ""))
    token = str(device.get("token") or "")
    if token and (len(token) != 24 or not HEX_RE.match(token)):
        token = ""

    output = {
        "schema_version": 1,
        "devices": [
            {
                "label": "s400-main",
                "model": str(device.get("model") or "MJTZC01YM"),
                "real_mac": mac,
                "corebluetooth_id": args.corebluetooth_id,
                "name_suffix": args.name_suffix,
                "bind_key_hex": beaconkey.lower(),
                "login_token_hex": token.lower(),
                "did": str(device.get("did") or ""),
                "server": str(device.get("_server") or ""),
                "source": "xiaomi-cloud-tokens-extractor",
                "created_at": date.today().isoformat(),
            }
        ],
    }

    out_path = Path(args.output)
    out_path.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.chmod(out_path, stat.S_IRUSR | stat.S_IWUSR)

    masked_mac = f"***:{mac.replace(':', '')[-4:].upper()}"
    print(
        "Imported S400 credentials: "
        f"mac={masked_mac}, bind_key_fp={fp(beaconkey)}, "
        f"token_fp={fp(token) if token else 'not-imported'}, "
        f"server={output['devices'][0]['server']}"
    )
    print(f"Wrote private file: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
