# Disaster Recovery and New Mac Restore

This project is split into two parts:

- GitHub private repo: source code, scripts, and documentation.
- Encrypted private-state backup: local secrets, household profile ranges, and the sanitized measurement ledger.

The private repo alone is not enough to make a new Mac immediately usable. It intentionally excludes `secrets.local.json`, `profiles.local.csv`, `config.json`, and `data/` so private health and device data are not stored in Git.

## What The Backup Includes

`./scripts/backup_private_state.sh` includes:

- `config.json`
- `profiles.local.csv`
- `secrets.local.json`
- `data/exports/s400_measurements.csv` when present

It excludes:

- `data/private/`
- raw BLE observations
- logs
- token extractor tools
- built app output

## Create A Backup

Run from the project root:

```bash
./scripts/backup_private_state.sh
```

By default, the encrypted file is written to:

```text
Google Drive/My Drive/Health Auto Export/S400 Health Data/private-backups/
```

You can override the backup folder:

```bash
S400_BACKUP_DIR="/path/to/backup-folder" ./scripts/backup_private_state.sh
```

Store the passphrase in a password manager. Without the passphrase, the backup cannot be restored.

## Restore On A New Mac

Clone the private repo:

```bash
git clone git@github.com:Hugh-Afterlight/xiaomi-s400-local-health-sync-private.git
cd xiaomi-s400-local-health-sync-private
```

Prepare local folders and build the scanner:

```bash
./scripts/bootstrap_new_machine.sh
```

Restore the encrypted private-state backup:

```bash
./scripts/restore_private_state.sh /path/to/s400-private-state-YYYYMMDD-HHMMSS.tar.gz.enc
```

Then verify:

```bash
./scripts/verify_s400_project.sh
```

Install the scheduled background watcher when ready:

```bash
./scripts/install_s400_launch_agent.sh
```

## Expected Manual Steps

On a replacement Mac, macOS may still require a few local approvals:

- Grant Bluetooth permission to the scanner app when prompted.
- Confirm Google Drive Desktop is installed and the target folder exists.
- If the scale's CoreBluetooth identifier changes, run a one-shot scan and update `secrets.local.json`.
- Reinstall the LaunchAgent with `./scripts/install_s400_launch_agent.sh`.

## Routine Maintenance

After important local changes, especially a new bind key, profile range, or meaningful measurement history update, create a fresh private-state backup.
