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
Google Drive/My Drive/Health Auto Export/S400 Health Data/s400_measurements.csv
```

## Background Capture

Install and start the LaunchAgent:

```bash
./scripts/install_s400_launch_agent.sh
```

By default the background watcher is active only from 05:00 to 09:00 local time. The scanner app is configured as a background-only app, so it should not bounce in the Dock during scan windows.

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

Check whether the local CSV and Google Drive CSV are in sync:

```bash
./scripts/check_sync_health.sh
```

If background Google Drive sync repeatedly fails while manual sync works, grant
Full Disk Access to `/bin/zsh` in macOS System Settings. The scheduled watcher
runs through `/bin/zsh`.

## Backup And Restore

The private GitHub repo restores the project code, but private local state is
kept out of Git. Create an encrypted private-state backup for new-Mac restore:

```bash
./scripts/backup_private_state.sh
```

On a new Mac:

```bash
./scripts/bootstrap_new_machine.sh
./scripts/restore_private_state.sh /path/to/s400-private-state-YYYYMMDD-HHMMSS.tar.gz.enc
```

See `docs/RESTORE.md`.

## Privacy

These are intentionally ignored by Git:

- `config.json`
- `profiles.local.csv`
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

For official Xiaomi Home report screenshots, place long screenshots in:

```text
Google Drive/My Drive/Health Auto Export/s400 图片报告/
```

Extract the screenshot report into CSV:

```bash
./scripts/extract_xiaomi_report_images.py
```

The extracted CSV is written to:

```text
data/exports/s400_official_reports.csv
Google Drive/My Drive/Health Auto Export/S400 Health Data/s400_official_reports.csv
```

This is a semi-automatic OCR route. It captures Xiaomi Home's displayed report
values from screenshots; it does not call Xiaomi Cloud APIs.

Recommended calibration workflow:

1. Fill `templates/user_profiles.example.csv`.
2. Record same-session Xiaomi Home official values in `templates/xiaomi_official_25_metrics.example.csv`.
3. Compare local estimates against official values only after collecting paired samples.

## Household Profile Matching

Measurements can be assigned to household members by weight ranges. Start with:

```bash
cp profiles.local.example.csv profiles.local.csv
```

Example:

```csv
person_label,min_weight_kg,max_weight_kg,notes
adult-1,65,100,Around 80 kg.
adult-2,40,65,Around 50 kg.
child,20,40,Around 30 kg.
```

The cumulative CSV includes `person_label`, `person_match_method`, and `person_match_confidence`.
