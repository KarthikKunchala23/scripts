#!/bin/bash

############################################################################################################
# Description: This script executes a specified command on a list of servers defined in a text file
# Usage: ./systems_automation.sh [-nsv] [-f server_list_file] COMMAND
# Options:
#   -f FILE   Specify a custom server list file (default: servers.txt)
#   -n        Dry run mode. Show commands without executing
#   -s        Run commands with sudo
#   -v        Enable verbose output
# Example:
#   ./systems_automation.sh -f my_servers.txt "df -h"
#   ./systems_automation.sh -nsv "systemctl restart apache2"
############################################################################################################

set -euo pipefail

# A list of servers one per line
SERVER_LIST="servers.txt"

SSH_OPTIONS="-o BatchMode=yes -o ConnectTimeout=5"

usage() {
    # Display usage information
    echo "Usage: ${0} [-nsv] [-f server_list_file] COMMAND" >&2
    echo "Executes COMMAND on each server in SERVER_LIST" >&2
    echo "  -f FILE   Specify a custom server list file (default: ${SERVER_LIST})" >&2 
    echo "  -n        Dry run mode. Show commands without executing" >&2
    echo "  -s        Run commands with sudo" >&2
    echo "  -v        Enable verbose output" >&2
    exit 1
}

# Make Sure the script is not beign run as root
if [[ "${EUID}" -eq 0 ]]
then
  echo "Please do not run as root. Use the -s option instead" >&2
  usage
fi

# Parse options
while getopts f:nsv OPTION
do
    case ${OPTION} in
        f) SERVER_LIST="${OPTARG}" ;;
        n) DRY_RUN=true ;;
        s) SUDO="sudo" ;;
        v) VERBOSE=true ;;
        *) usage ;;
    esac
done

# Remove parsed options from arguments
shift $((OPTIND -1))

# if no command is provided, show usage
if [[ "${#}" -eq 0 ]]
then
    usage
fi

#Anything after options is treated as the command to run
COMMAND="${@}"

# Check if server list file exists
if [[ ! -f "${SERVER_LIST}" ]]
then
    echo "Server list file ${SERVER_LIST} not found" >&2
    exit 1
fi

# Loop through each server in the list
for SERVER in $(cat "${SERVER_LIST}")
do
    if [[ "${VERBOSE}" == true ]]
    then
        echo "Processing server: ${SERVER}"
    fi

    SSH_COMMAND="ssh ${SSH_OPTIONS} ${SERVER} '${SUDO} ${COMMAND}'"

    # If dry run, just print the command
    if [[ "${DRY_RUN}" == true ]]
    then
        echo "DRY RUN: ${SSH_COMMAND}"
    else
        # Execute the command on the remote server
        ${SSH_COMMAND}
        SSH_EXIT_CODE=$?

        # Check if the SSH command was successful
        if [[ ${SSH_EXIT_CODE} -ne 0 ]]
        then
            EXIT_STATUS="${SSH_EXIT_CODE}"
            echo "Command failed on ${SERVER}" >&2
        fi
    fi
done

exit ${EXIT_STATUS:-0}