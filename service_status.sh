#!/usr/bin/env bash

# service_health.sh --- Check health of various services and report via email
# Usage: service_health.sh
# Environment variables:
#   HEALTH_REPORT_TO (comma-separated email addresses)  
# Note: SMTP_* env variables are ignored in this version (we use system mail/sendmail)

set -o errexit
set -o nounset
set -o pipefail

DRY_RUN=false
# optional: allow first arg to be --dry-run
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

# Accept service name as first non-flag argument; default to nginx
SERVICE=${1:-nginx}

# HEALTH_REPORT_TO can be set in environment; fallback to your email
HEALTH_REPORT_TO="${HEALTH_REPORT_TO:-karthikkunchala07@gmail.com}"

REPORT_FILE="/tmp/service_health_report.txt"
LOG_FILE="/tmp/service_health_mailer.log"

log() {
    echo "[$(date +'%F %T')] $*"
}

check_service_health() {
    local svc="$1"
    if systemctl is-active --quiet "$svc"; then
        echo "Service $svc is running."
        return 0
    else
        echo "Service $svc is NOT running."
        # capture `systemctl status $svc --no-pager` for diagnostics
        systemctl status "$svc" --no-pager || true
        return 1
    fi
}

# new function: send report using `mail` (mailx) or fallback to sendmail
send_email_report() {
    local to_addresses="$1"
    local subject="$2"
    local body_file="$3"

    if [ "$DRY_RUN" = "true" ]; then
        log "[DRY-RUN] Would send email to: $to_addresses"
        log "[DRY-RUN] Subject: $subject"
        log "[DRY-RUN] Body file: $body_file"
        return 0
    fi

    # normalize recipients: convert commas to spaces, trim spaces
    IFS=',' read -r -a rec_array <<< "$to_addresses"
    # trim whitespace from each element and build space-separated list
    recipients=""
    for r in "${rec_array[@]}"; do
        # trim leading/trailing whitespace
        r="$(echo "$r" | awk '{$1=$1;print}')"
        [[ -z "$r" ]] && continue
        recipients="${recipients} ${r}"
    done
    recipients="$(echo "$recipients" | xargs)"  # final trim

    if [[ -z "$recipients" ]]; then
        log "ERROR: No recipients specified."
        return 6
    fi

    # If /usr/bin/mail or /bin/mail (mailx) exists, prefer it
    if command -v mail >/dev/null 2>&1; then
        log "Sending via mail: recipients=[$recipients]"
        # mail supports multiple recipients separated by spaces
        if mail -s "$subject" $recipients < "$body_file" >> "$LOG_FILE" 2>&1; then
            log "Mail command returned success."
            return 0
        else
            log "Mail command failed. Check $LOG_FILE for details."
            return 4
        fi
    fi

    # Fallback to sendmail if available
    if command -v sendmail >/dev/null 2>&1; then
        log "Using sendmail fallback to deliver message to: [$recipients]"
        {
            echo "To: $to_addresses"
            echo "Subject: $subject"
            echo "MIME-Version: 1.0"
            echo "Content-Type: text/plain; charset=UTF-8"
            echo ""
            cat "$body_file"
        } | sendmail -t >> "$LOG_FILE" 2>&1 || {
            log "sendmail failed. See $LOG_FILE"
            return 4
        }
        log "sendmail accepted the message (check system MTA queue for delivery)."
        return 0
    fi

    log "ERROR: Neither 'mail' nor 'sendmail' commands are available on this system."
    log "Install 'mailutils' (Deb/Ubuntu) or 'mailx' (RHEL/CentOS) and configure an MTA (postfix/sendmail) if you want delivery."
    return 5
}

main() {
    log "Starting service health check for $SERVICE"
    mkdir -p "$(dirname "$REPORT_FILE")"

    {
        echo "Service Health Report"
        echo "====================="
        echo ""
        check_service_health "$SERVICE"
    } > "$REPORT_FILE"

    log "Report content:"
    sed -n '1,200p' "$REPORT_FILE" | sed 's/^/    /'

    log "Sending health report email to $HEALTH_REPORT_TO"
    subject="Service Health Report for $SERVICE"

    if send_email_report "$HEALTH_REPORT_TO" "$subject" "$REPORT_FILE"; then
        log "Email step completed."
    else
        log "Email step failed (see logs)."
    fi

    log "Service health check completed."
}

main
