#!/usr/bin/env bash
#####################################################
# System Resource Monitoring Script
# Author: Karthik Kunchala (improved)
# Date: 2025-12-04
#####################################################
set -o errexit
set -o nounset
set -o pipefail

# Configuration
THRESHOLD=80
MEMORY_THRESHOLD=80
CPU_THRESHOLD=75
ALERT_EMAIL="karthikkunchala07@gmail.com"
LOGFILE="/var/log/myapp/system_alert.log"
FALLBACK_LOG="/tmp/system_alert.log"

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

# Safe numeric compare helper (integers)
is_gt() {
    # usage: is_gt "$value" "$threshold"
    [ "$1" -gt "$2" ]
}

# Convert percent values safely (memory calculation uses awk)
get_disk_usage() {
    df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}'
}

get_memory_usage() {
    # print integer percentage
    free | awk '/Mem/ {printf("%d", ($3/$2)*100)}'
}

get_cpu_load_percent() {
    # Use 1-minute loadavg normalized to # of CPUs to give percent-like figure
    # loadavg / ncpus * 100
    local load
    local cpus
    load=$(cut -d' ' -f1 /proc/loadavg)
    cpus=$(nproc --all)
    # compute percentage with awk to avoid bash float issues
    awk -v l="$load" -v c="$cpus" 'BEGIN { printf("%d", (l / c) * 100) }'
}

# main
ensure_logfile

# Disk usage
USAGE=$(get_disk_usage)
if is_gt "$USAGE" "$THRESHOLD"; then
    msg="Disk usage is at ${USAGE}%, which exceeds the threshold of ${THRESHOLD}%."
    echo "$msg"
    log "$msg"
    # send alert email (only on exceed)
    printf '%s\n' "$msg" | mail -s "Disk Usage Alert" "$ALERT_EMAIL" || true
else
    echo "Disk usage is at ${USAGE}%, which is within the safe limit."
    log "Disk OK: ${USAGE}%"
fi

# Memory usage
MEMORY_USAGE=$(get_memory_usage)
if is_gt "$MEMORY_USAGE" "$MEMORY_THRESHOLD"; then
    msg="Memory usage is at ${MEMORY_USAGE}%, which exceeds the threshold of ${MEMORY_THRESHOLD}%."
    echo "$msg"
    log "$msg"
    printf '%s\n' "$msg" | mail -s "Memory Usage Alert" "$ALERT_EMAIL" || true
else
    echo "Memory usage is at ${MEMORY_USAGE}%, which is within the safe limit."
    log "Memory OK: ${MEMORY_USAGE}%"
fi

# CPU load
CPU_LOAD=$(get_cpu_load_percent)
if is_gt "$CPU_LOAD" "$CPU_THRESHOLD"; then
    msg="CPU load is at ${CPU_LOAD}%, which exceeds the threshold of ${CPU_THRESHOLD}%."
    echo "$msg"
    log "$msg"
    printf '%s\n' "$msg" | mail -s "CPU Load Alert" "$ALERT_EMAIL" || true
else
    echo "CPU load is at ${CPU_LOAD}%, which is within the safe limit."
    log "CPU OK: ${CPU_LOAD}%"
fi

# Uptime and top memory consumers - always appended to log
log "System Uptime: $(uptime -p)"
log "Top 5 memory-consuming processes:"
ps aux --sort=-%mem | awk 'NR<=6 {printf("%-8s %-6s %-6s %s\n",$1,$3,$4,$11)}' >> "$LOGFILE"

exit 0
