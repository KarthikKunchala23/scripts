#!/usr/bin/env bash
# Automated Mount & /etc/fstab Validator
# Usage: sudo ./mount_fstab_validator.sh [--dry-run] <device> <mount_point> <fs_type> [mount_options] [dump] [pass]
#
# Examples:
#  sudo ./mount_fstab_validator.sh /dev/xvdf /mnt/data ext4 defaults 0 2
#  sudo ./mount_fstab_validator.sh --dry-run /dev/xvdf /mnt/data ext4 noatime,nodiratime 0 2

set -o errexit
set -o nounset
set -o pipefail

DRY_RUN=false

# simple logger
log() { echo "[$(date +'%F %T')] $*"; }

usage() {
    cat <<EOF
Usage: sudo $0 [--dry-run] <device> <mount_point> <fs_type> [mount_options] [dump] [pass]
 - device:       device node (e.g. /dev/xvdf) or label (e.g. /dev/sdb1)
 - mount_point:  directory to mount to (e.g. /mnt/data)
 - fs_type:      filesystem type (e.g. ext4,xfs)
 - mount_options: optional, defaults to "defaults"
 - dump:         optional, defaults to 0
 - pass:         optional, fsck pass (0,1,2), defaults to 2
 --dry-run:      print actions but don't modify /etc/fstab or mount
EOF
    exit 1
}

# ensure root
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root. Use: sudo $0"
    exit 1
fi

# parse optional --dry-run
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

# validate required args
if [[ $# -lt 3 ]]; then
    usage
fi

DEVICE="$1"
MOUNT_POINT="$2"
FS_TYPE="$3"
MOUNT_OPTS="${4:-defaults}"
DUMP="${5:-0}"
PASS="${6:-2}"

# helper: trim whitespace
trim() { local v="$*"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; printf '%s' "$v"; }

# resolve UUID if possible; fall back to device path
get_uuid_or_device() {
    local dev="$1"
    # try blkid; some systems may require /sbin/blkid in PATH, assume blkid is available
    if command -v blkid >/dev/null 2>&1; then
        uuid=$(blkid -s UUID -o value "$dev" 2>/dev/null || true)
        if [[ -n "$uuid" ]]; then
            echo "UUID=$uuid"
            return 0
        fi
    fi
    # fallback: return raw device path
    echo "$dev"
}

# check if device exists (block device or file)
if [[ ! -b "$DEVICE" && ! -e "$DEVICE" ]]; then
    log "ERROR: Device '$DEVICE' does not exist or is not a block device."
    exit 2
fi

# check mountpoint path validity
if [[ -e "$MOUNT_POINT" && ! -d "$MOUNT_POINT" ]]; then
    log "ERROR: Mount point '$MOUNT_POINT' exists but is not a directory."
    exit 3
fi

FSTAB="/etc/fstab"
BACKUP="${FSTAB}.bak.$(date +%F-%H%M%S)"

# compute entry identifier (use UUID if available)
ENTRY_DEVICE="$(get_uuid_or_device "$DEVICE")"
# example: UUID=xxxx or /dev/xvdf
log "Using device identifier: $ENTRY_DEVICE"

FSTAB_ENTRY="$ENTRY_DEVICE $MOUNT_POINT $FS_TYPE $MOUNT_OPTS $DUMP $PASS"

# show what would happen in dry-run
if $DRY_RUN; then
    log "[DRY-RUN] Would ensure mount point exists: $MOUNT_POINT"
    log "[DRY-RUN] Would ensure /etc/fstab contains entry: $FSTAB_ENTRY"
    log "[DRY-RUN] Would attempt to mount (read fstab) the mount point."
    exit 0
fi

# Create mount point if missing
if [[ ! -d "$MOUNT_POINT" ]]; then
    log "Creating mount point directory: $MOUNT_POINT"
    mkdir -p "$MOUNT_POINT"
    log "Mount point created."
fi

# Backup /etc/fstab before any change
log "Backing up $FSTAB -> $BACKUP"
cp --preserve=mode,ownership,timestamps "$FSTAB" "$BACKUP"

# Function to check if an fstab entry for the mount_point or device already exists
fstab_has_entry() {
    local device_ident="$1"
    local mp="$2"
    # Match lines that start with device ident (UUID=... or /dev/...) OR mountpoint field matches
    awk -v dev="$device_ident" -v mp="$mp" '
    BEGIN{ FS="[[:space:]]+" }
    /^[[:space:]]*#/ { next }
    NF >= 2 {
      if ($1 == dev || $2 == mp) {
        print $0; found=1
      }
    }
    END { exit !found }' "$FSTAB"
}

# if an entry exists for same device or same mountpoint, show and confirm/update
if fstab_has_entry "$ENTRY_DEVICE" "$MOUNT_POINT"; then
    log "An existing fstab entry for this device or mountpoint was found."
    log "Existing matching lines:"
    fstab_has_entry "$ENTRY_DEVICE" "$MOUNT_POINT" | sed 's/^/    /'
    # We'll replace existing entry if it references same mount point or same device with a new canonical entry
    # To be safe, create a temp file and perform replacement atomically
    TMPF="$(mktemp)"
    awk -v dev="$ENTRY_DEVICE" -v mp="$MOUNT_POINT" -v newentry="$FSTAB_ENTRY" '
    BEGIN{ FS="[[:space:]]+"; OFS="\t" }
    /^[[:space:]]*#/ { print $0; next }
    NF >= 2 {
      if ($1 == dev || $2 == mp) {
        if (!replaced) { print newentry; replaced=1; next }
        # skip duplicate matching entries
        next
      }
    }
    { print $0 }
    END {
      if (!replaced) {
        # append if no replacement occurred (safe fallback)
        print newentry
      }
    }' "$FSTAB" > "$TMPF"
    # validate new tmp fstab syntax with visudo-like tool for fstab? There is no standard validator for fstab,
    # so we'll test by trying to mount the single entry after replacing the file.
    log "Updating $FSTAB with new/updated entry..."
    cp --preserve=mode,ownership,timestamps "$TMPF" "$FSTAB"
    rm -f "$TMPF"
else
    # append new entry
    log "Appending new entry to $FSTAB:"
    log "    $FSTAB_ENTRY"
    printf '%s\n' "$FSTAB_ENTRY" >> "$FSTAB"
fi

# Try to mount the mount point using the fstab entry
log "Attempting to mount $MOUNT_POINT (reads /etc/fstab)..."
# Use mount <mount_point> which will read /etc/fstab for the mountpoint
if mount "$MOUNT_POINT"; then
    log "Mount successful: $(findmnt --target "$MOUNT_POINT" -o TARGET,SOURCE,FSTYPE,OPTIONS -n || true)"
    log "Done."
    exit 0
else
    log "ERROR: mount failed for $MOUNT_POINT. Reverting /etc/fstab to backup $BACKUP"
    cp --preserve=mode,ownership,timestamps "$BACKUP" "$FSTAB"
    # attempt to unmount if partially mounted
    if mountpoint -q "$MOUNT_POINT"; then
        log "Unmounting partially mounted $MOUNT_POINT"
        umount "$MOUNT_POINT" || log "Warning: umount of $MOUNT_POINT failed."
    fi
    log "Restored original /etc/fstab."
    exit 4
fi
