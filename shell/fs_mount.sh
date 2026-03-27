#!/bin/bash

# This script mounts a filesystem to a specified mount point.
# Usage: ./fs_mount.sh <device> <mount_point> <filesystem_type> [options]
set -e
set -o errexit
set -o nounset
set -o pipefail

DEVICE="$1"
MOUNT_POINT="$2"
FS_TYPE="$3"
OPTIONS="${4:-}"    

if [ -z "$DEVICE" ] || [ -z "$MOUNT_POINT" ] || [ -z "$FS_TYPE" ]; then
    echo "Usage: $0 <device> <mount_point> <filesystem_type> [options]"
    exit 1
fi

# Create mount point if it doesn't exist
if [ ! -d "$MOUNT_POINT" ]; then
    echo "Creating mount point at $MOUNT_POINT"
    mkdir -p "$MOUNT_POINT"
fi

# Mount the filesystem
echo "Mounting $DEVICE to $MOUNT_POINT with filesystem type $FS_TYPE"
if [ -n "$OPTIONS" ]; then
    mount -t "$FS_TYPE" -o "$OPTIONS" "$DEVICE" "$MOUNT_POINT"
else
    mount -t "$FS_TYPE" "$DEVICE" "$MOUNT_POINT"
fi

echo "Successfully mounted $DEVICE to $MOUNT_POINT"

# Verify the mount
if mountpoint -q "$MOUNT_POINT"; then
    echo "$MOUNT_POINT is a valid mount point."
else
    echo "Failed to mount $DEVICE to $MOUNT_POINT"
    exit 1
fi

