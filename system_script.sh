#!/bin/bash
  

#####################################################
# Description: System Resource Monitoring Script
# Author: Karthik Kunchala
# Date: 2025-12-01
#####################################################

# This script checks disk,cpu and memory usage and sends an alert if usage exceeds a specified threshold.
set -e
set -o pipefail

# Disk Usage Check
THRESHOLD=80
ALERT_EMAIL="karthikkunchala07@gmail.com"
USAGE=$(df -h / | grep '/' | awk '{print $5}' | sed 's/%//g')

if [ "$USAGE" -gt "$THRESHOLD" ]; then
    echo "Disk usage is at ${USAGE}%, which exceeds the threshold of ${THRESHOLD}%." | \
    echo "Disk usage is at ${USAGE}%, which exceeds the threshold of ${THRESHOLD}%." >> /var/log/system_alert.log
    mail -s "Disk Usage Alert" "$ALERT_EMAIL" <<< "Disk usage is at ${USAGE}%, which exceeds the threshold of ${THRESHOLD}%."
else
    echo "Disk usage is at ${USAGE}%, which is within the safe limit."
    mail -s "Disk Usage Status" "$ALERT_EMAIL" <<< "Disk usage is at ${USAGE}%, which is within the safe limit."
fi

# Memory Usage Check
MEMORY_THRESHOLD=80
MEMORY_USAGE=$(free | grep Mem | awk '{print $3/$2 * 100.0}' | cut -d. -f1)

if [ "$MEMORY_USAGE" -gt "$MEMORY_THRESHOLD" ]; then
    echo "Memory usage is at ${MEMORY_USAGE}%, which exceeds the threshold of ${MEMORY_THRESHOLD}%." | \
    echo "Memory usage is at ${MEMORY_USAGE}%, which exceeds the threshold of ${MEMORY_THRESHOLD}%." >> /var/log/system_alert.log
    mail -s "Memory Usage Alert" "$ALERT_EMAIL" <<< "Memory usage is at ${MEMORY_USAGE}%, which exceeds the threshold of ${MEMORY_THRESHOLD}%."
else
    echo "Memory usage is at ${MEMORY_USAGE}%, which is within the safe limit."
    mail -s "Memory Usage Status" "$ALERT_EMAIL" <<< "Memory usage is at ${MEMORY_USAGE}%, which is within the safe limit."
fi

# CPU Load Check
CPU_THRESHOLD=75
CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}' | cut -d. -f1)

if [ "$CPU_LOAD" -gt "$CPU_THRESHOLD" ]; then
    echo "CPU load is at ${CPU_LOAD}%, which exceeds the threshold of ${CPU_THRESHOLD}%." | \
    # write to log file
    echo "CPU load is at ${CPU_LOAD}%, which exceeds the threshold of ${CPU_THRESHOLD}%." >> /var/log/system_alert.log 
    mail -s "CPU Load Alert" "$ALERT_EMAIL" <<< "CPU load is at ${CPU_LOAD}%, which exceeds the threshold of ${CPU_THRESHOLD}%."
else
    echo "CPU load is at ${CPU_LOAD}%, which is within the safe limit."
    mail -s "CPU Load Status" "$ALERT_EMAIL" <<< "CPU load is at ${CPU_LOAD}%, which is within the safe limit."
fi

# uptime of the system
echo "System Uptime:"
uptime_status=$(uptime)
echo "$uptime_status" >> /var/log/system_alert.log

# top 5 memory consuming processes
echo "Top 5 Memory Consuming Processes:"
mem_top_5=$(ps aux --sort=-%mem | head -n 6)
echo "$mem_top_5" >> /var/log/system_alert.log

