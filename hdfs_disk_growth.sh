#!/usr/bin/env bash
# hdfs_disk_growth.sh
# Monthly HDFS directory growth alert script (single-node / pseudo-distributed).
# Requires: bash >=4, hdfs CLI, python SMTP sender at /opt/hdfs_mail/send_mail_smtp.py (port 587), sendmail (fallback)
set -euo pipefail

#### CONFIG - edit these ####
declare -A TENANT_DIRS=(
  ["stallions"]="/data/dev/stallions"
  ["tfi"]="/data/dev/tfi"
)

declare -A TENANT_EMAILS=(
  ["stallions"]="karthikkunchala2398@gmail.com"
  ["tfi"]="karthikkunchala2307@gmail.com"
)

STORAGE_DIR="/var/log/hdfs_tenant_usage"      # snapshot store
FROM_EMAIL="karthikkunchala07@gmail.com"
SUBJECT_PREFIX="[HDFS Dir Growth Alert]"

# Kerberos (optional): if KRB_PRINCIPAL set, script will kinit with KEYTAB
KRB_PRINCIPAL=""               # e.g. monitor@EXAMPLE.COM (leave empty if not using)
KRB_KEYTAB="/etc/security/monitor.keytab"

# Dry-run: set "true" to see output on stdout and not send mail
DRY_RUN="false"
###########################

# ensure storage/log dir
mkdir -p "$STORAGE_DIR"
touch "$STORAGE_DIR/hdfs_alert_send.log" 2>/dev/null || true

# HDFS command detection (allows overriding with env HDFS_CMD)
: "${HDFS_CMD:=/opt/hadoop/bin/hdfs}"
if [ ! -x "$HDFS_CMD" ]; then
  for p in /usr/local/hadoop/bin/hdfs /usr/bin/hdfs /usr/hdp/current/hadoop-client/bin/hdfs /opt/hadoop/bin/hdfs; do
    if [ -x "$p" ]; then
      HDFS_CMD="$p"
      break
    fi
  done
fi
if [ ! -x "$HDFS_CMD" ]; then
  echo "Error: hdfs CLI not found. Set HDFS_CMD to full path (e.g. /opt/hadoop/bin/hdfs) and retry." >&2
  exit 1
fi
echo "Using HDFS command: $HDFS_CMD" >&2

# helpers
human() {
  local b=${1:-0}
  if [ -z "$b" ]; then
    printf "0 B"
    return
  fi
  if [ "$b" -ge $((1024**4)) ]; then
    awk -v x="$b" 'BEGIN{printf "%.2f TB", x/(1024^4)}'
  elif [ "$b" -ge $((1024**3)) ]; then
    awk -v x="$b" 'BEGIN{printf "%.2f GB", x/(1024^3)}'
  elif [ "$b" -ge $((1024**2)) ]; then
    awk -v x="$b" 'BEGIN{printf "%.2f MB", x/(1024^2)}'
  elif [ "$b" -ge 1024 ]; then
    awk -v x="$b" 'BEGIN{printf "%.2f KB", x/1024}'
  else
    printf "%d B" "$b"
  fi
}

# month keys
CUR_KEY="$(date +%Y-%m)"
PREV_KEY="$(date -d "$(date +%Y-%m-15) -1 month" +%Y-%m)"

# optional kinit
if [ -n "$KRB_PRINCIPAL" ]; then
  if [ ! -f "$KRB_KEYTAB" ]; then
    echo "Kerberos keytab $KRB_KEYTAB not found but KRB_PRINCIPAL set. Aborting." >&2
    exit 2
  fi
  kinit -kt "$KRB_KEYTAB" "$KRB_PRINCIPAL"
fi

# ensure mktemp
if ! command -v mktemp >/dev/null 2>&1; then
  echo "Error: mktemp required but not found. Aborting." >&2
  exit 4
fi

# Main loop: per tenant
for tenant in "${!TENANT_DIRS[@]}"; do
  tenant_path="${TENANT_DIRS[$tenant]}"
  tenant_email="${TENANT_EMAILS[$tenant]:-}"

  tenant_dir="$STORAGE_DIR/$tenant"
  mkdir -p "$tenant_dir"
  CUR_FILE="$tenant_dir/usage_${CUR_KEY}.tsv"
  PREV_FILE="$tenant_dir/usage_${PREV_KEY}.tsv"

  echo "Processing tenant: $tenant (path: $tenant_path)"

  # Gather immediate children sizes (robust to various hdfs du formats)
  set +e
  du_output="$($HDFS_CMD dfs -du -s "${tenant_path}"/* 2>&1)"
  du_rc=$?
  set -e

  if [ $du_rc -ne 0 ]; then
    echo "Warning: failed to list children for $tenant_path. hdfs output:"
    echo "$du_output"
    # write empty snapshot file and continue
    : > "$CUR_FILE"
    continue
  fi

  # Parse lines to "path<TAB>bytes"
  echo "$du_output" | awk '
  {
    bytes=""; path="";
    for(i=1;i<=NF;i++){
      if ($i ~ /^[0-9]+$/ && bytes=="") {
        bytes=$i
      } else {
        if (path=="") path=$i; else path=path " " $i
      }
    }
    if (bytes=="" && $NF ~ /^[0-9]+$/) {
      bytes=$NF; path=""; for(i=1;i<NF;i++){ if (path=="") path=$i; else path=path " " $i }
    }
    if (bytes!="" && path!="") {
      gsub(/^[ \t]+|[ \t]+$/, "", path)
      print path "\t" bytes
    }
  }' | sort -k1,1 > "$CUR_FILE"

  # If previous missing -> create baseline and skip emailing
  if [ ! -s "$PREV_FILE" ]; then
    echo "NOTICE: previous snapshot missing for tenant $tenant. Creating baseline and skipping alerts for first-run."
    if [ -s "$CUR_FILE" ]; then
      awk -F'\t' '{print $1 "\t0"}' "$CUR_FILE" > "$PREV_FILE" || true
    else
      : > "$PREV_FILE"
    fi
    continue
  fi

  # join prev and cur into path<TAB>prev<TAB>cur
  joined_tmp="$(mktemp /tmp/joined_${tenant}.XXXXXX)"
  awk -F'\t' '
    FNR==NR { prev[$1] = $2 + 0; next }
    { cur[$1] = $2 + 0 }
    END {
      for (p in prev) all[p]=1
      for (p in cur) all[p]=1
      for (p in all) {
        pv = (p in prev) ? prev[p] : 0
        cv = (p in cur) ? cur[p] : 0
        print p "\t" pv "\t" cv
      }
    }
  ' "$PREV_FILE" "$CUR_FILE" > "$joined_tmp"

  # compute increases
  incr_tmp="$(mktemp /tmp/incr_${tenant}.XXXXXX)"
  awk -F'\t' '{
    p=$1; prev=$2+0; cur=$3+0;
    if (cur>prev) {
      abs = cur - prev;
      if (prev==0) pct="N/A"; else pct = sprintf("%.2f", (abs * 100) / prev);
      print p "\t" prev "\t" cur "\t" abs "\t" pct;
    }
  }' "$joined_tmp" > "$incr_tmp"

  rm -f "$joined_tmp"

  if [ ! -s "$incr_tmp" ]; then
    echo "No directory increases for tenant $tenant."
    rm -f "$incr_tmp"
    continue
  fi

  # prepare email body
  mail_body="$(mktemp /tmp/mail_body_${tenant}.XXXXXX)"
  {
    echo "Tenant: $tenant"
    echo "HDFS path: $tenant_path"
    echo "Report period: $PREV_KEY -> $CUR_KEY"
    echo
    echo "Directories that increased in usage (sorted by absolute increase):"
    echo
    printf "%-12s %-14s %-14s %-10s %s\n" "ABS" "PREV" "CUR" "PCT" "PATH"
    sort -t$'\t' -k4,4nr "$incr_tmp" | while IFS=$'\t' read -r path prev cur abs pct; do
      prev_h="$(human "$prev")"
      cur_h="$(human "$cur")"
      abs_h="$(human "$abs")"
      printf "%-12s %-14s %-14s %-10s %s\n" "$abs_h" "$prev_h" "$cur_h" "$pct" "$path"
    done
    echo
    echo "Notes:"
    echo " - Any directory shown above had a month-over-month increase in used bytes."
    echo " - Please investigate large files, retention, or snapshots under the listed paths."
    echo
    echo "This message was generated automatically by the HDFS monthly directory growth alert."
  } > "$mail_body"

  # Send email (primary: Python SMTP sender on port 587, fallback: sendmail)
  subject="${SUBJECT_PREFIX} ${tenant} directories increased: ${PREV_KEY} -> ${CUR_KEY}"

  if [ "$DRY_RUN" = "true" ]; then
    echo "DRY-RUN: Mail to ${tenant_email:-<no-email>} subject: $subject"
    cat "$mail_body"
  else
    if [ -z "$tenant_email" ]; then
      echo "Warning: no email configured for tenant $tenant; logging message to stdout instead."
      cat "$mail_body"
    else
      # load SMTP creds if present
      if [ -f /etc/hdfs_mail/smtp.conf ]; then
        # shellcheck disable=SC1090
        . /etc/hdfs_mail/smtp.conf
      fi

      mkdir -p /var/log/hdfs_tenant_usage
      # Primary: python sender (uses SMTP over 587)
      if command -v python3 >/dev/null 2>&1 && [ -x /opt/hdfs_mail/send_mail_smtp.py ]; then
        /opt/hdfs_mail/send_mail_smtp.py "$FROM_EMAIL" "$tenant_email" "$subject" "$mail_body" >> /var/log/hdfs_tenant_usage/hdfs_alert_send.log 2>&1
        rc=$?
        echo "$(date -Iseconds) python-smtp exit code: $rc" >> /var/log/hdfs_tenant_usage/hdfs_alert_send.log
      else
        rc=127
        echo "$(date -Iseconds) python sender not found (rc=127)" >> /var/log/hdfs_tenant_usage/hdfs_alert_send.log
      fi

      # Fallback if python sender failed
      if [ "${rc:-1}" -ne 0 ]; then
        echo "$(date -Iseconds) python-smtp failed or not available, attempting local sendmail fallback" >> /var/log/hdfs_tenant_usage/hdfs_alert_send.log
        (
          echo "To: ${tenant_email}"
          echo "From: ${FROM_EMAIL}"
          echo "Subject: ${subject}"
          echo
          cat "${mail_body}"
        ) | /usr/sbin/sendmail -t -oi 2>>/var/log/hdfs_tenant_usage/hdfs_alert_send.log || echo "$(date -Iseconds) sendmail fallback failed" >> /var/log/hdfs_tenant_usage/hdfs_alert_send.log
      fi
    fi
  fi

  # cleanup per-tenant temps
  rm -f "$incr_tmp" "$mail_body"
done

exit 0
