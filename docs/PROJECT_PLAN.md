# Project Plan

## Goal

Build a small, local-first pipeline for Xiaomi Body Composition Scale S400:

1. Scan S400 BLE advertisements on a Mac that is always on.
2. Decode encrypted `FE95` MiBeacon payloads with a local BLE bind key.
3. Store raw observations locally for debugging.
4. Append sanitized measurements to a cumulative CSV ledger.
5. Optionally copy the sanitized CSV to a local Google Drive desktop folder.

The daily path does not depend on Xiaomi Cloud. Xiaomi Cloud is only used during setup to obtain the device MAC and BLE bind key after the scale has been paired in Xiaomi Home.

## MVP Scope

Included:

- macOS Swift/CoreBluetooth scanner.
- Xiaomi S400 FE95 decoding through the `xiaomi-ble` Python library.
- Local JSONL/CSV outputs.
- Deduplicated cumulative CSV ledger.
- Optional local Google Drive desktop sync.
- macOS LaunchAgent background loop.
- Local cleanup, log rotation, status, and verification scripts.

Not included:

- Native Google Sheets API sync.
- Xiaomi Cloud polling.
- Xiaomi Home official 25-metric report replication.
- Web UI.
- Medical or diagnostic advice.

## Data Model

The sanitized cumulative ledger contains:

```text
measurement_id
measured_at_local
device_label
profile_id
weight_kg
impedance_ohm
impedance_low_ohm
heart_rate_bpm
rssi
packet_count
completeness_score
device_model
parser
```

Raw BLE observations and parsed debug JSONL are kept under `data/` and are not copied to Google Drive by this project.

## Privacy Boundaries

Do not commit or share:

- `config.json`
- `secrets.local.json`
- `data/`
- `logs/`
- `tools/`
- `bin/`

Only `data/exports/s400_measurements.csv` is intended for Google Drive sync. The sync safety script checks that the target Google Drive folder only contains the sanitized CSV and that the CSV header does not contain sensitive fields.

## Official 25 Metrics

The scale broadcasts reliable raw values such as weight, impedance, low-frequency impedance, heart rate, and profile id. Xiaomi Home's complete 25-metric report is likely generated from raw values plus user profile data and Xiaomi's private algorithm.

The recommended next step is calibration, not guessing:

1. Fill `templates/user_profiles.example.csv` with profile id, height, birth date, and formula sex.
2. Record Xiaomi Home official values for the same weighing session in `templates/xiaomi_official_25_metrics.example.csv`.
3. Collect 10-20 paired samples per user.
4. Only then decide which metrics can be estimated locally and which should be marked as Xiaomi-official-only.

## Operational Checks

Use:

```bash
./scripts/status_s400_project.sh
./scripts/verify_s400_project.sh
./scripts/check_google_drive_sync_safety.sh
```

The verification script is a maintenance command. It builds the scanner, checks local config, syncs the ledger, runs cleanup, checks duplicate protection, and confirms the LaunchAgent status.
