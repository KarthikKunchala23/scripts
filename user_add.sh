#!/bin/bash

#####################################################
# Bulk User Addition from CSV with Sudoers File Creation
# CSV format: username,group,is_sudo
# Example: alice,devs,yes
#####################################################

set -o errexit
set -o nounset
set -o pipefail

USAGE="Usage: sudo $0 <users.csv> [default_shell=/bin/bash]"

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Use: sudo $0"
    exit 1
fi

# Input CSV
CSV_FILE="${1:-}"
DEFAULT_SHELL="${2:-/bin/bash}"

if [[ -z "$CSV_FILE" ]]; then
    echo "Missing CSV file."
    echo "$USAGE"
    exit 2
fi

if [[ ! -f "$CSV_FILE" ]]; then
    echo "CSV file '$CSV_FILE' not found."
    exit 3
fi

log() {
    echo "[$(date +'%F %T')] $*"
}

# Trim whitespace
trim() {
    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

# Validate and install sudoers content safely
install_sudoers() {
    local username="$1"
    local mode="$2"  # "nopasswd" or "passwd"
    local sudofile="/etc/sudoers.d/${username}"
    local tmpfile

    tmpfile="$(mktemp)"
    if [[ "$mode" == "nopasswd" ]]; then
        printf '%s\n' "${username} ALL=(ALL) NOPASSWD:ALL" > "$tmpfile"
    else
        printf '%s\n' "${username} ALL=(ALL) ALL" > "$tmpfile"
    fi

    # Validate the sudoers snippet before moving it into place
    if visudo -cf "$tmpfile" >/dev/null 2>&1; then
        # Move into place atomically and set correct permissions
        install -m 0440 "$tmpfile" "$sudofile"
        log "Installed sudoers file: $sudofile (mode: $mode)"
    else
        log "ERROR: sudoers validation failed for user $username. Not installing file."
        rm -f "$tmpfile"
        return 1
    fi

    rm -f "$tmpfile"
    return 0
}

add_or_update_user() {
    local username="$1"
    local groupname="$2"
    local shell="$3"
    local home_dir="$4"
    local is_sudo="$5"

    # create group if missing
    if ! getent group "$groupname" >/dev/null 2>&1; then
        log "Group '$groupname' doesn't exist. Creating..."
        groupadd "$groupname"
        log "Group '$groupname' created."
    else
        log "Group '$groupname' already exists."
    fi

    # if user exists, ensure they are in the group; else create user
    if id -u "$username" >/dev/null 2>&1; then
        log "User '$username' already exists. Ensuring primary group is '$groupname'..."
        # Use usermod to set primary group and shell (if needed)
        usermod -g "$groupname" -s "$shell" -d "$home_dir" -m "$username" || {
            log "Warning: usermod for $username failed (maybe some settings unchanged)."
        }
        log "User '$username' updated (group/shell/home)."
    else
        log "Creating user '$username'..."
        useradd -m -d "$home_dir" -s "$shell" -g "$groupname" "$username"
        log "User '$username' created with home '$home_dir', shell '$shell', group '$groupname'."
    fi

    # Handle sudoers entry if requested
    # Normalize is_sudo (lowercase trim)
    local is_sudo_norm
    is_sudo_norm="$(trim "$is_sudo" | tr '[:upper:]' '[:lower:]')"
    if [[ "$is_sudo_norm" == "yes" || "$is_sudo_norm" == "true" || "$is_sudo_norm" == "1" || "$is_sudo_norm" == "nopasswd" ]]; then
        if [[ "$is_sudo_norm" == "nopasswd" ]]; then
            install_sudoers "$username" "nopasswd" || log "Failed to install nopasswd sudoers for $username"
        else
            install_sudoers "$username" "passwd" || log "Failed to install sudoers for $username"
        fi
    else
        log "No sudo entry requested for '$username'."
    fi
}

# Read CSV
# Skip blank lines and allow an optional header (if header contains 'username' we'll skip first line)
first_line=true
while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim the line
    line="$(trim "$line")"

    # Skip empty lines and comments
    [[ -z "$line" ]] && continue
    [[ "${line:0:1}" == "#" ]] && continue

    # Split CSV by commas (simple CSV; fields should not contain commas)
    IFS=, read -r raw_username raw_group raw_is_sudo <<< "$line"

    # Trim fields
    username="$(trim "${raw_username:-}")"
    groupname="$(trim "${raw_group:-}")"
    is_sudo="$(trim "${raw_is_sudo:-}")"

    # If first line looks like a header (contains 'username' or 'user'), skip it
    if $first_line; then
        first_line=false
        lc_header="$(echo "$username" | tr '[:upper:]' '[:lower:]')"
        if [[ "$lc_header" == "username" || "$lc_header" == "user" ]]; then
            log "Detected header line; skipping."
            continue
        fi
    fi

    # Basic validation
    if [[ -z "$username" || -z "$groupname" ]]; then
        log "Skipping invalid/empty line: $line"
        continue
    fi

    home_dir="/home/${username}"
    shell="${DEFAULT_SHELL}"

    add_or_update_user "$username" "$groupname" "$shell" "$home_dir" "$is_sudo"

done < "$CSV_FILE"

log "All entries processed."
