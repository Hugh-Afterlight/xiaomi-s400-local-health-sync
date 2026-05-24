# Dual Repository Workflow

This project uses two GitHub remotes:

- `private`: personal working repository.
- `origin`: public sanitized repository for sharing.

## Daily Private Work

Use the private repository for normal project history:

```bash
git status
git add <public-safe project files>
git commit -m "Describe the change"
git push private main
```

The local `main` branch tracks `private/main`, so plain `git push` goes to the private repository.

## Public Sharing

Only push to the public repository after a sanitization check:

```bash
git status --short --ignored
git grep --cached -n -I -E '(/Users/hugh|GoogleDrive-|real_mac|bind_key|token|secrets.local|data/private)' || true
git push origin main
```

Public pushes must not include:

- `config.json`
- `profiles.local.csv`
- `secrets.local.json`
- `data/`
- `logs/`
- `tools/`
- `bin/`
- machine-specific paths, IDs, tokens, account names, or health records

## Private-Only Changes

If a change is useful only for this Mac or household, keep it private and do not push it to `origin`.

For sensitive local values, prefer ignored files instead of commits:

- `config.json`
- `profiles.local.csv`
- `secrets.local.json`
- `data/`

Even in the private repository, do not commit Xiaomi account passwords, BLE keys, tokens, raw health data, or Google account credentials.

## Current Remotes

```text
origin  -> public sanitized repository
private -> personal private repository
```
