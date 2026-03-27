#!/usr/bin/env bash

# service_health.sh --- Check health of system services and report via email
# Usage:
#   service_health.sh
#   service_health.sh nginx
#   service_health.sh nginx ssh docker
#   service_health.sh --prompt

set -o errexit
set -o nounset
set -o pipefail
set -u

DRY_RUN=false
PROMPT_MODE=false

# Handle flags
while [[ "${1:-}" =~ ^-- ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --prompt)  PROMPT_MODE=true ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

# Default services if none provided
DEFAULT_SERVICES=("nginx" "ssh" "docker")

# Services from arguments
SERVICES=("$@")

# Prompt user if requested
if [[ "$PROMPT_MODE" == "true" ]]; then
    read -rp "Enter services to check (space-separated, e.g. nginx ssh docker): " -a SERVICES
fi

# If still empty, use defaults
if [[ "${#SERVICES[@]}" -eq 0 ]]; then
    SERVICES=("${DEFAULT_SERVICES[@]}")
fi

# Email config
HEALTH_REPORT_TO="${HEALTH_REPORT_TO:-karthikkunchala2307@gmail.com}"

REPORT_FILE="/tmp/service_health_report.txt"
LOG_FILE="/tmp/service_health_mailer.log"

log() {
    echo "[$(date +'%F %T')] $*"
}

check_service_health() {
    local svc="$1"

    if systemctl list-unit-files | grep -qw "$svc.service"; then
        if systemctl is-active --quiet "$svc"; then
            echo "✔ Service $svc is RUNNING"
            return 0
        else
            echo "✖ Service $svc is NOT running"
            systemctl status "$svc" --no-pager || true
            return 1
        fi
    else
        echo "⚠ Service $svc does NOT exist on this system"
        return 2
    fi
}

send_email_report() {
    local subject="$1"
    local body_file="$2"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would send email to $HEALTH_REPORT_TO"
        return 0
    fi

    python3 "$PYTHON_SMTP_SCRIPT" \
        --to "$HEALTH_REPORT_TO" \
        --subject "$subject" \
        --body-file "$body_file" \
        >> "$LOG_FILE" 2>&1
}

main() {
    log "Starting service health check"
    log "Services to check: ${SERVICES[*]}"

    {
        echo "Service Health Report"
        echo "====================="
        echo "Host      : $(hostname)"
        echo "Timestamp : $(date +'%F %T')"
        echo ""

        FAILED=0

        for svc in "${SERVICES[@]}"; do
            if ! check_service_health "$svc"; then
                FAILED=1
            fi
            echo ""
        done

        if [[ "$FAILED" -eq 1 ]]; then
            echo "Overall Status: ❌ ISSUES DETECTED"
        else
            echo "Overall Status: ✅ ALL SERVICES RUNNING"
        fi

    } > "$REPORT_FILE"

    log "Report generated at $REPORT_FILE"
    sed 's/^/    /' "$REPORT_FILE"

    SUBJECT="Service Health Report: $(hostname)"
    send_email_report "$SUBJECT" "$REPORT_FILE"

    log "Service health check completed"
}

main
