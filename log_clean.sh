#!/bin/bash

####################################################################
# Log Cleaning Script
#####################################################################
# Description: Cleans up log files older than a specified number of days.   
# Author: Karthik Kunchala
# Date: 2025-12-06
#####################################################################



set -o errexit
set -o nounset
set -e
set -o pipefail

# Configuration
LOG_DIR="/var/log/myapp"
DAYS_OLD=7
ARCHIVE_DIR="/var/log/myapp/archive"
CURRENT_DATE=$(date +%Y%m%d)
LOGFILE="/var/log/log_clean.log"
FALLBACK_LOG="/tmp/log_clean.log"

#create archive directory if it doesn't exist
mkdir -p "$ARCHIVE_DIR"

# Ensure a writable logfile (if /var/log isn't writable, fallback)
ensure_logfile() {
    if [ -e "$LOGFILE" ]; then
        if [ ! -w "$LOGFILE" ]; then
            if [ "$(id -u)" -eq 0 ]; then
                # root can fix perms
                chmod 0640 "$LOGFILE" || true
            else
                echo "Warning: $LOGFILE not writable by $(whoami). Falling back to $FALLBACK_LOG."
                LOGFILE="$FALLBACK_LOG"
            fi
        fi
    else
        if [ "$(id -u)" -eq 0 ]; then
            touch "$LOGFILE"
            chmod 0640 "$LOGFILE" || true
        else
            # create fallback in /tmp if not root
            echo "Info: Creating fallback log at $FALLBACK_LOG"
            LOGFILE="$FALLBACK_LOG"
            touch "$LOGFILE"
            chmod 0600 "$LOGFILE" || true
        fi
    fi
}   

log() {
    # timestamped append
    printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" >> "$LOGFILE"
}

ensure_logfile
log "Starting log cleanup in $LOG_DIR for files older than $DAYS_OLD days."

# Find and archive old logs
find "$LOG_DIR" -type f -name "*.log" -mtime +"$DAYS_OLD" | while read -r file; do
    basefile=$(basename "$file")
    gzip -c "$file" > "$ARCHIVE_DIR/${basefile}_${CURRENT_DATE}.gz"
    if [ $? -eq 0 ]; then
        rm -f "$file"
        log "Archived and removed $file"
    else
        log "Failed to archive $file"
    fi
done
log "Log cleanup completed."