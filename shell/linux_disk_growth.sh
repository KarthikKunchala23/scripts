#!/usr/bin/env bash
# linux_tenant_dir_growth_alert.sh
# Find per-tenant local filesystem directories whose usage increased month-over-month and email the tenant.
# Scans immediate children of each tenant path (tenant_path/*), stores monthly snapshots, compares and emails.
#
# Requirements:
#  - bash >=4 (associative arrays)
#  - coreutils: du, find, awk, sort, mktemp
#  - mailx or sendmail for email delivery
#
set -euo pipefail

#### CONFIG - edit these values ####
declare -A TENANT_DIRS=(
  ["ganga"]="/tmp/dev/ganga"
  ["yamuna"]="/tmp/dev/yamuna"
)

declare -A TENANT_EMAILS=(
  ["ganga"]="karthikkunchala07@gmail.com"
  ["yamuna"]="karthikkunchala07@gmail.com"
)

STORAGE_DIR="/var/log/linux_tenant_usage"    # store snapshots per tenant
FROM_EMAIL="disk-monitor@example.com"
SUBJECT_PREFIX="[Disk Dir Growth Alert]"

# Dry-run: set to "true" to print emails to stdout instead of sending
DRY_RUN="false"
#####################################

mkdir -p "$STORAGE_DIR"

# cleanup handler for temp files
TMP_FILES=()
cleanup() {
  for f in "${TMP_FILES[@]:-}"; do
    [ -n "$f" ] && rm -f "$f" || true
  done
}
trap cleanup EXIT

# human-readable bytes (single external call via awk)
human() {
  local b=$1
  awk -v b="$b" 'BEGIN{
    if (b>=1024^4) {printf "%.2f TB", b/(1024^4)}
    else if (b>=1024^3) {printf "%.2f GB", b/(1024^3)}
    else if (b>=1024^2) {printf "%.2f MB", b/(1024^2)}
    else if (b>=1024) {printf "%.2f KB", b/1024}
    else {printf "%d B", b}
  }'
}

CUR_KEY="$(date +%Y-%m)"
PREV_KEY="$(date -d "$(date +%Y-%m-15) -1 month" +%Y-%m)"

# detect mail program
MAIL_CMD=""
if command -v mailx >/dev/null 2>&1; then
  MAIL_CMD="mailx"
elif command -v sendmail >/dev/null 2>&1; then
  MAIL_CMD="sendmail"
fi

# iterate tenants
for tenant in "${!TENANT_DIRS[@]}"; do
  tenant_path="${TENANT_DIRS[$tenant]}"
  tenant_email="${TENANT_EMAILS[$tenant]:-}"

  tenant_dir="$STORAGE_DIR/$tenant"
  mkdir -p "$tenant_dir"
  CUR_FILE="$tenant_dir/usage_${CUR_KEY}.tsv"
  PREV_FILE="$tenant_dir/usage_${PREV_KEY}.tsv"

  echo "Processing tenant: $tenant -> $tenant_path"

  # ensure tenant path exists
  if [ ! -d "$tenant_path" ]; then
    echo "Warning: tenant path $tenant_path not found. Creating current snapshot as empty."
    : > "$CUR_FILE"
    # create prev baseline if missing so next month we don't alert on non-existent path
    if [ ! -f "$PREV_FILE" ]; then
      : > "$PREV_FILE"
    fi
    continue
  fi

  # Get immediate children (dirs and files) and their sizes in bytes.
  # Using find + xargs du avoids shell globbing issues and supports spaces in names.
  tmp_du="$(mktemp)"
  TMP_FILES+=("$tmp_du")
  # Find immediate children only (depth 1). If none exist, produce empty file.
  # We include files and directories; adapt with -type d if you want only directories.
  if find "$tenant_path" -mindepth 1 -maxdepth 1 -print0 | xargs -0 -r du -sb 2>/dev/null > "$tmp_du"; then
    # du -sb outputs: <bytes>\t<path>
    # Transform to: <path>\t<bytes> and sort by path
    awk '{print $2 "\t" $1}' "$tmp_du" | sort -k1,1 > "$CUR_FILE"
  else
    # If du failed (e.g., permission), write empty snapshot and continue
    echo "Warning: du failed for $tenant_path. Writing empty current snapshot."
    : > "$CUR_FILE"
    continue
  fi

  # First-run: if previous snapshot missing or empty -> create baseline mapping current paths -> 0 and skip alerts this month
#   if [ ! -s "$PREV_FILE" ]; then
#     echo "NOTICE: previous snapshot missing/empty for tenant $tenant. Creating baseline and skipping alerts for first-run."
#     awk -F'\t' '{print $1 "\t0"}' "$CUR_FILE" > "$PREV_FILE" || true
#     continue
#   fi

  # Use awk to join prev and cur into a single stream and compute increases.
  # Format expected: files with lines path<TAB>bytes (sorted by path not required)
  joined="$(mktemp)"
  TMP_FILES+=("$joined")

  # Build associative maps in awk and output rows for increases: path prev cur abs pct
  awk -F'\t' '
  BEGIN { OFS="\t" }
  FNR==NR { prev[$1] = $2 + 0; next }   # first file: previous
  { cur[$1] = $2 + 0 }
  END {
    # union of keys from prev and cur
    for (p in prev) seen[p]=1
    for (p in cur) seen[p]=1
    for (p in seen) {
      pv = (p in prev) ? prev[p] : 0
      cv = (p in cur) ? cur[p] : 0
      if (cv > pv) {
        abs = cv - pv
        if (pv == 0) pct = "N/A"; else {
          pct_val = (abs * 100) / pv
          # format to two decimals
          pct = sprintf("%.2f", pct_val)
        }
        printf "%s\t%d\t%d\t%d\t%s\n", p, pv, cv, abs, pct
      }
    }
  }
  ' "$PREV_FILE" "$CUR_FILE" > "$joined"

  # If no increases, skip emailing
  if [ ! -s "$joined" ]; then
    echo "No directory increases for tenant $tenant."
    continue
  fi

  # Sort by absolute increase (4th column) descending and prepare mail body
  sorted="$(mktemp)"
  TMP_FILES+=("$sorted")
  sort -t$'\t' -k4,4nr "$joined" > "$sorted"

  mail_body="$(mktemp)"
  TMP_FILES+=("$mail_body")
  {
    echo "Tenant: $tenant"
    echo "Local path: $tenant_path"
    echo "Report: $PREV_KEY -> $CUR_KEY"
    echo
    printf "%-12s %-12s %-12s %-12s %s\n" "ABS" "PREV" "CUR" "PERCENT" "PATH"
    while IFS=$'\t' read -r path prev cur abs pct; do
      prev_h="$(human "$prev")"
      cur_h="$(human "$cur")"
      abs_h="$(human "$abs")"
      printf "%-12s %-12s %-12s %-12s %s\n" "$abs_h" "$prev_h" "$cur_h" "$pct" "$path"
    done < "$sorted"
    echo
    echo "Notes:"
    echo " - List above contains immediate children of $tenant_path that increased in bytes since previous month."
    echo " - If a path had prev=0 and cur>0, percent is shown as N/A (new data)."
    echo
    echo "This notification was generated automatically by the disk monthly directory growth script."
  } > "$mail_body"

  subject="${SUBJECT_PREFIX} ${tenant} directories increased: ${PREV_KEY} -> ${CUR_KEY}"

  if [ "$DRY_RUN" = "true" ] || [ -z "$MAIL_CMD" ]; then
    echo "DRY/TEST MODE or no mail program: would send mail to ${tenant_email:-<no-email>} with subject: $subject"
    cat "$mail_body"
  else
    if [ -z "$tenant_email" ]; then
      echo "Warning: no email configured for tenant $tenant; printing message instead."
      cat "$mail_body"
    else
      if [ "$MAIL_CMD" = "mailx" ]; then
        # some mailx versions accept -r for From header; ignore errors
        if mailx -V >/dev/null 2>&1; then
          mailx -r "$FROM_EMAIL" -s "$subject" "$tenant_email" < "$mail_body" || true
        else
          mailx -s "$subject" "$tenant_email" < "$mail_body" || true
        fi
      else
        # sendmail
        {
          echo "To: $tenant_email"
          echo "From: $FROM_EMAIL"
          echo "Subject: $subject"
          echo
          cat "$mail_body"
        } | sendmail -t || true
      fi
    fi
  fi

done

# exit normally
exit 0
