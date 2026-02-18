#!/usr/bin/env bash
# Azure-safe Automated Disk Mount Script
# Supports: auto-partition, auto-format, UUID-only fstab, reboot persistence

set -euo pipefail

DRY_RUN=false
AUTO_PARTITION=true
AUTO_FORMAT=true

log() { echo "[$(date +'%F %T')] $*"; }

usage() {
cat <<EOF
Usage:
  sudo $0 [--dry-run] <device> <mount_point> <fs_type>

Example:
  sudo $0 /dev/sda /data ext4
  sudo $0 --dry-run /dev/sda /data ext4
EOF
exit 1
}

# Root check
[[ "$EUID" -eq 0 ]] || { echo "Run as root"; exit 1; }

# Dry-run
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

[[ $# -eq 3 ]] || usage

DEVICE="$1"
MOUNT_POINT="$2"
FS_TYPE="$3"

# ---------------- SAFETY CHECKS ----------------

# Device exists
[[ -b "$DEVICE" ]] || { log "ERROR: $DEVICE not found"; exit 2; }

# Refuse /mnt (Azure resource disk)
if [[ "$MOUNT_POINT" == /mnt* ]]; then
    log "ERROR: /mnt is reserved for Azure resource disk. Use /data or /opt/data."
    exit 3
fi

# Refuse root disk
ROOT_SRC=$(findmnt -n -o SOURCE /)
if lsblk -no PKNAME "$ROOT_SRC" | grep -qw "$(basename "$DEVICE")"; then
    log "ERROR: $DEVICE contains root filesystem. Aborting."
    exit 4
fi

# ---------------- PARTITION HANDLING ----------------

PARTITION="$DEVICE"

if [[ "$(lsblk -no TYPE "$DEVICE")" == "disk" ]]; then
    PARTITION="${DEVICE}1"

    if ! lsblk "$DEVICE" | grep -q part; then
        if $AUTO_PARTITION; then
            log "Creating partition on $DEVICE"
            $DRY_RUN || (
                parted -s "$DEVICE" mklabel gpt
                parted -s "$DEVICE" mkpart primary 0% 100%
                partprobe "$DEVICE"
                sleep 2
            )
        else
            log "ERROR: No partition found and auto-partition disabled"
            exit 5
        fi
    fi
fi

# ---------------- FILESYSTEM HANDLING ----------------

FS_EXIST=$(blkid -s TYPE -o value "$PARTITION" 2>/dev/null || true)

if [[ -z "$FS_EXIST" ]]; then
    if $AUTO_FORMAT; then
        log "Formatting $PARTITION as $FS_TYPE"
        $DRY_RUN || mkfs -t "$FS_TYPE" "$PARTITION"
    else
        log "ERROR: No filesystem found on $PARTITION"
        exit 6
    fi
fi

# ---------------- UUID RESOLUTION ----------------

UUID=$(blkid -s UUID -o value "$PARTITION")
[[ -n "$UUID" ]] || { log "ERROR: UUID not found"; exit 7; }

ENTRY="UUID=$UUID $MOUNT_POINT $FS_TYPE defaults,nofail,x-systemd.device-timeout=30 0 2"

# ---------------- MOUNT POINT ----------------

[[ -d "$MOUNT_POINT" ]] || { log "Creating $MOUNT_POINT"; $DRY_RUN || mkdir -p "$MOUNT_POINT"; }

# ---------------- FSTAB UPDATE ----------------

FSTAB="/etc/fstab"
BACKUP="/etc/fstab.bak.$(date +%F-%H%M%S)"

log "Backing up fstab → $BACKUP"
$DRY_RUN || cp "$FSTAB" "$BACKUP"

# Remove any old entry for this mountpoint
$DRY_RUN || sed -i "\|[[:space:]]$MOUNT_POINT[[:space:]]|d" "$FSTAB"

log "Adding fstab entry:"
log "  $ENTRY"
$DRY_RUN || echo "$ENTRY" >> "$FSTAB"

# ---------------- APPLY ----------------

log "Reloading systemd"
$DRY_RUN || systemctl daemon-reload

log "Mounting all filesystems"
if ! $DRY_RUN && ! mount -a; then
    log "ERROR: mount failed, restoring fstab"
    cp "$BACKUP" "$FSTAB"
    systemctl daemon-reload
    exit 8
fi

log "SUCCESS: $PARTITION mounted at $MOUNT_POINT"
