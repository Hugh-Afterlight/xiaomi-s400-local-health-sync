# Xiaomi S400 Local Health Sync

Local-first data capture for Xiaomi Body Composition Scale S400 on macOS.

The project scans encrypted BLE advertisements from the scale, decodes the core raw measurements locally, appends them to a sanitized CSV ledger, and can copy that CSV into a local Google Drive desktop folder.

Daily capture does not use Xiaomi Cloud. Xiaomi Cloud is only used once during setup to retrieve the scale MAC address and BLE bind key after pairing the scale in Xiaomi Home.

## What It Captures

Verified local fields:

- weight
- impedance
- low-frequency impedance
- heart rate
- profile id
- RSSI and packet metadata

It does not claim to reproduce Xiaomi Home's official 25-metric report. See `templates/` for the recommended calibration workflow.

## Requirements

- macOS with Bluetooth access
- Python 3
- Xcode Command Line Tools or Swift toolchain
- Xiaomi S400 already paired in Xiaomi Home
- Optional: Google Drive desktop app for CSV sync

## Setup

Create local config files:

```bash
cp config.example.json config.json
cp secrets.local.example.json secrets.local.json
```

Build the BLE scanner:

```bash
./scripts/build_scanner.sh
```

Install the token extractor helper:

```bash
./scripts/setup_token_extractor.sh
```

Run the extractor locally and import the S400 credentials:

```bash
./scripts/run_token_extractor.sh
./scripts/import_s400_credentials.py --input data/private/xiaomi_tokens.json
./scripts/check_secrets.py
```

Do not paste Xiaomi passwords, BLE keys, tokens, or generated `secrets.local.json` into chat or issues.

## Manual Capture

Start a one-shot scan, then step on the scale and wait until body composition / heart rate measurement finishes:

```bash
./scripts/capture_s400_once.sh
```

The cumulative local ledger is:

```text
data/exports/s400_measurements.csv
```

If Google Drive desktop is installed, the sanitized CSV is copied to:

```text
Google Drive/My Drive/S400 Health Data/s400_measurements.csv
```

## Background Capture

Install and start the LaunchAgent:

```bash
./scripts/install_s400_launch_agent.sh
```

Stop it:

```bash
./scripts/uninstall_s400_launch_agent.sh
```

Check status:

```bash
./scripts/status_s400_project.sh
```

Run maintenance verification:

```bash
./scripts/verify_s400_project.sh
```

## Privacy

These are intentionally ignored by Git:

- `config.json`
- `secrets.local.json`
- `data/`
- `logs/`
- `tools/`
- `bin/`

Only the sanitized cumulative CSV is intended for Google Drive sync. Check the sync boundary with:

```bash
./scripts/check_google_drive_sync_safety.sh
```

## Official 25 Metrics

Xiaomi Home's full body composition report is likely generated from the raw measurements plus profile data and Xiaomi's private algorithm.

Recommended next step:

1. Fill `templates/user_profiles.example.csv`.
2. Record same-session Xiaomi Home official values in `templates/xiaomi_official_25_metrics.example.csv`.
3. Compare local estimates against official values only after collecting paired samples.
