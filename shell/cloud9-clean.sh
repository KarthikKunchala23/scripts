#!/bin/bash

# Configuration
DAYS_INACTIVE=120
DRY_RUN=true # Set to false to actually delete environments

# Calculate the cutoff timestamp in seconds (Unix Epoch)
CUTOFF_DATE=$(date -d "$DAYS_INACTIVE days ago" +%s 2>/dev/null || date -v -${DAYS_INACTIVE}d +%s)

echo "--------------------------------------------------------"
echo "Scanning for Cloud9 environments inactive for > $DAYS_INACTIVE days..."
echo "Cutoff Timestamp: $CUTOFF_DATE ($(date -d @$CUTOFF_DATE 2>/dev/null || date -r $CUTOFF_DATE))"
if [ "$DRY_RUN" = true ]; then
    echo "⚠️  DRY RUN MODE ENABLED. No environments will be deleted."
else
    echo "🚨 ACTION REQUIRED: Deleting environments permanently."
fi
echo "--------------------------------------------------------"

# 1. Fetch all environment IDs
ENV_IDS=$(aws cloud9 list-environments --query "environmentIds[]" --output text)

for ENV_ID in $ENV_IDS; do
    # 2. Get environment details (to print the name)
    ENV_NAME=$(aws cloud9 describe-environments --environment-ids "$ENV_ID" --query "environments[0].name" --output text)
    
    # 3. Get the latest lastAccess timestamp among all members of this environment
    LAST_ACCESS=$(aws cloud9 describe-environment-memberships --environment-id "$ENV_ID" \
        --query "memberships[].lastAccess" --output json | jq 'max // 0')

    # If lastAccess is 0, it means it has never been accessed since tracking began
    if [ "$LAST_ACCESS" -eq 0 ]; then
        echo "❔ Env: $ENV_NAME ($ENV_ID) - No login history found. Skipping to be safe."
        continue
    fi

    # 4. Check if the last access is older than the 4-month cutoff date
    if [ "$LAST_ACCESS" -lt "$CUTOFF_DATE" ]; then
        HUMAN_DATE=$(date -d @"$LAST_ACCESS" 2>/dev/null || date -r "$LAST_ACCESS")
        
        if [ "$DRY_RUN" = true ]; then
            echo "🔍 [WOULD DELETE] Env: '$ENV_NAME' ($ENV_ID) | Last Access: $HUMAN_DATE"
        else
            echo "❌ [DELETING] Env: '$ENV_NAME' ($ENV_ID) | Last Access: $HUMAN_DATE"
            aws cloud9 delete-environment --environment-id "$ENV_ID"
            sleep 0.5 # Small pause to prevent rate limiting
        fi
    fi
done

echo "Done."
