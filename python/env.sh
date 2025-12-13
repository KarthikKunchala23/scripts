#!/usr/bin/env bash
# wrapper to set SMTP env & run the monitor
export SMTP_HOST="smtp.gmail.com"
export SMTP_PORT="587"
export SMTP_USER="karthikkunchala07@gmail.com"
export SMTP_PASS="yevw swdh dxqz lrsy"
export SMTP_FROM="karthikkunchala07@gmail.com"
export SMTP_STARTTLS="true"



# export HDFS_CMD=/opt/hadoop/bin/hdfs
export USE_PYTHON_SMTP=true
export PYTHON_SMTP_SCRIPT=/home/karthik/scripts/python/mailer.py
export DRY_RUN=false

exec /home/karthik/scripts/service_health.sh "$@"  # pass all args to service_health.sh

# note: to debug SMTP, you can run a local SMTP server using:
# python -m smtpd -c DebuggingServer -n localhost:1025

# then set:
# export SMTP_HOST=localhost
# export SMTP_PORT=1025
# export SMTP_STARTTLS=false

# Run the script like:
# ./env.sh --dry-run
# ./env.sh nginx ssh docker
# ./env.sh --prompt
# ./env.sh --dry-run --prompt