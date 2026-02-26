# Scotty — NAS Backup & Config Sync

Backup and configuration management for a Synology NAS running Paperless-ngx.

## Architecture

```
Mac (this machine)                     Synology NAS
┌─────────────────────┐               ┌──────────────────────────┐
│ scotty/ (git repo)  │──rsync/SSH──▶ │ /volume1/docker/paperless│
│  docker-compose.yml │   (push)      │  docker-compose.yml      │
│  docker-compose.env │               │  docker-compose.env      │
│  scripts/           │               │                          │
│  Makefile           │               │ /volume1/photo/          │
└────────┬────────────┘               │ /volume1/docker/paperless│
         │                            │ /volume1/backups/        │
         │ pull (selective:           │  dsm-config-*.dss        │
         │ docs + config only)        └──┬──────────┬────────────┘
         ◀──────────────────────────────┘│          │
                                         │          │ push (cron, nightly)
┌───────────────────┐                    │          ▼
│ Desktop Linux     │◀───pull (full)─────┘   ┌──────────────────┐
│ (cron, when on)   │  photos + docs +       │ Fritz!Box ext HDD│
│ PRIMARY BACKUP    │  DSM config            │ (SMB mount)      │
└───────────────────┘                        └──────────────────┘
```

**Key decisions:**
- **Push to Fritz!Box** — always-on, NAS cron job rsyncs nightly
- **Pull from Mac/Desktop** — intermittent, these machines pull when they're on
- **rsync everywhere** — plain files, no proprietary format
- **Git for config only** — docker-compose files version-controlled, deployed via rsync

## Prerequisites

### SSH key auth (Mac → NAS)

The NAS must be reachable via `ssh nas` (configured in `~/.ssh/config`).

```bash
make ssh-setup
```

This generates an ed25519 key (if needed) and copies it to the NAS.

Synology requires strict permissions for SSH key auth. Fix on the NAS if needed:

```bash
ssh nas "chmod 755 ~ && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

> **Note:** DSM config backups do not include home directory contents or permissions.
> After a DSM restore, re-run `make ssh-setup` and fix permissions.

#### TODO
- setup SSH config via nix: https://github.com/nix-community/home-manager/blob/master/modules/programs/ssh.nix

### SSH key auth (Desktop Linux → NAS)

On the Desktop Linux machine:

1. Generate key: `ssh-keygen -t ed25519`
2. Add to `~/.ssh/config`:
   ```
   Host nas
       HostName <NAS-IP-or-hostname>
       User <your-user>
   ```
3. Copy key: `ssh-copy-id nas`
4. Verify: `ssh nas "echo ok"`

## Quick Start

```bash
# 1. Set up SSH key auth
make ssh-setup

# 2. Deploy docker-compose files to NAS
make deploy

# 3. Deploy backup scripts to NAS
make deploy-scripts

# 4. Pull a selective backup (docs + DSM config)
make pull-selective

# 5. Check backup status
make status
```

## Makefile Targets

| Target              | Description                                              |
|---------------------|----------------------------------------------------------|
| `make deploy`       | Push docker-compose files to NAS                         |
| `make deploy-scripts` | Push NAS-side backup scripts to NAS                   |
| `make pull-full`    | Full backup: photos + docs + DSM config (for Desktop)    |
| `make pull-selective` | Selective backup: docs + DSM config only (for Mac)     |
| `make status`       | Check NAS connectivity + backup freshness                |
| `make install-launchd` | Install macOS scheduled backup (every 6h)            |
| `make uninstall-launchd` | Remove macOS scheduled backup                      |
| `make install-cron` | Print cron line for Desktop Linux                        |
| `make ssh-setup`    | Copy SSH key to NAS (one-time)                           |

## NAS Setup: Synology Task Scheduler

After `make deploy-scripts`, set up nightly backups in DSM:

1. Open **Control Panel → Task Scheduler**
2. **Create → Scheduled Task → User-defined script**
3. Name: `Scotty Backup`
4. User: `root`
5. Schedule: Daily at 02:00
6. Command:
   ```bash
   /volume1/scripts/scotty/export-dsm-config.sh && /volume1/scripts/scotty/backup-db.sh && /volume1/scripts/scotty/backup-to-fritzbox.sh
   ```
7. Enable email notification on abnormal termination

## Fritz!Box External HDD Setup

1. Attach external HDD (ext4 or NTFS) to Fritz!Box USB port
2. Fritz!Box UI → **Heimnetz → USB / Speicher → USB-Speicher aktivieren**
3. Enable SMB share (NAS-Funktion)
4. Create a user for SMB access (or use existing Fritz!Box user)
5. Note the share path — typically `//fritz.box/FRITZ.NAS/USB-Stick`
6. Test from NAS: `smbclient -L //fritz.box -U <user>`
7. Update `FRITZBOX_SHARE` and `FRITZBOX_USER` in `config.env`
8. Run `make deploy-scripts` to push updated config to NAS

## Desktop Linux Setup

Clone this repo on the Desktop, then:

```bash
# Copy and edit config
cp config.env.example config.env
vim config.env

# Test a full pull
make pull-full

# Set up cron (every 4 hours)
make install-cron
# Then add the printed line to crontab: crontab -e
```

## Mac Scheduled Backup

```bash
# Install launchd plist (runs every 6 hours)
make install-launchd

# Check it's running
launchctl list | grep scotty

# View logs
cat /tmp/scotty-backup.log

# Remove
make uninstall-launchd
```

## Restore Procedures

### Restore Paperless documents

Copy exported documents back to NAS and re-import:

```bash
# From local backup to NAS
rsync -avz ~/NAS-Backup/paperless/export/ nas:/volume1/docker/paperless/export/

# Then trigger Paperless import via the web UI or:
ssh nas "cd /volume1/docker/paperless && docker compose exec webserver document_importer ../export"
```

### Restore Paperless database

```bash
# Copy dump to NAS
scp ~/NAS-Backup/paperless-db/paperless-db-YYYY-MM-DD_HHMMSS.sql.gz nas:/tmp/

# Restore on NAS
ssh nas "gunzip -c /tmp/paperless-db-*.sql.gz | docker compose -f /volume1/docker/paperless/docker-compose.yml --env-file /volume1/docker/paperless/env.txt exec -T db psql -U paperless paperless"
```

### Restore DSM configuration

1. Copy `.dss` file to a machine with browser access to DSM
2. DSM → **Control Panel → Update & Restore → Configuration Backup → Restore**
3. Upload the `.dss` file

### Restore photos

```bash
rsync -avz ~/NAS-Backup/photos/ nas:/volume1/photo/
```

### Restore from Fritz!Box HDD

If the NAS is lost, mount the Fritz!Box HDD directly:

```bash
# On any Linux machine
mount -t cifs //fritz.box/FRITZ.NAS/USB-Stick /mnt/recovery -o username=<user>
# Files are in /mnt/recovery/nas-backup/
```

## Troubleshooting

**NAS unreachable:**
- Check `ssh nas "echo ok"` — if it fails, verify `~/.ssh/config` and network
- Ensure NAS SSH service is enabled (DSM → Control Panel → Terminal & SNMP)

**Fritz!Box mount fails:**
- Check `ping fritz.box` from NAS
- Verify SMB credentials: `smbclient -L //fritz.box -U <user>`
- Check USB storage is enabled in Fritz!Box UI
- Try `vers=2.0` instead of `vers=3.0` in mount options

**Pull backup hangs:**
- Check `rsync` isn't stuck on a large file — use `--progress` to see
- Kill and re-run; `--partial` ensures interrupted files resume

**Launchd not running:**
- `launchctl list | grep scotty` — should show `com.scotty.nas-backup`
- Check `/tmp/scotty-backup.log` for errors
- Reinstall: `make uninstall-launchd && make install-launchd`
