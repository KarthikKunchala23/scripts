#!/bin/bash 


set -o pipefail

# This script deletes, disable and archives users on the local system.
# It must be run with superuser privileges.
# Options:
#   -d  Delete accounts instead of disabling them.
#   -r  Remove home directories associated with the accounts.
#   -a  Archive the home directories associated with the accounts.
# Usage: ./delete_accounts.sh [-d] [-r] [-a] USER [USERNAMES...]
# Example: ./delete_accounts.sh -d -r john doe

ARCHIVE_DIR='/archive'

usage() {
    echo "Usage: sudo ${0} [-d] [-r] [-a] USER [USERNAMES...]" >&2
    echo "  -d  Delete accounts instead of disabling them." >&2
    echo "  -r  Remove home directories associated with the accounts." >&2
    echo "  -a  Archive the home directories associated with the accounts." >&2
    exit 1
}

# Make sure the script is being run with superuser privileges.
if [[ $EUID -ne 0 ]]
then
    echo "Please run this script with superuser privileges." >&2
    exit 1
fi

# Parse the command-line options.
while getopts "dra" OPTION
do
    case ${OPTION} in
        d)
            DELETE_USER='true'
            ;;
        r)
            REMOVE_HOME='-r'
            ;;
        a)
            ARCHIVE='true'
            ;;
        ?) 
            usage
            ;;
    esac
done

# Remove the options from the positional parameters.
shift "$(( OPTIND -1 ))"

# Make sure at least one username is supplied.
if [[ "${#}" -lt 1 ]]
then
    usage
fi

# Loop through all the usernames supplied as arguments.
for USERNAME in "${@}"
do
    echo "Processing user: ${USERNAME}"

    # Make sure the UID of the account is at least 1000.
    USERID=$(id -u ${USERNAME})
    if [[ "${USERID}" -lt 1000 ]]
    then
        echo "Refusing to remove the ${USERNAME} account with UID ${USERID}." >&2
        exit 1
    fi

    # Archive the home directory if requested to do so.
    if [[ "${ARCHIVE}" = 'true' ]]
    then
        if [[ ! -d "${ARCHIVE_DIR}" ]]
        then
            echo "Creating ${ARCHIVE_DIR} directory." >&2
            mkdir -p "${ARCHIVE_DIR}"
            if [[ "${?}" -ne 0 ]]
            then
                echo "The archive directory ${ARCHIVE_DIR} could not be created." >&2
                exit 1
            fi
        fi
        HOME_DIR="/home/${USERNAME}"
        ARCHIVE_FILE="${ARCHIVE_DIR}/${USERNAME}.tar.gz"
        if [[ -d "${HOME_DIR}" ]]
        then
            echo "Archiving ${HOME_DIR} to ${ARCHIVE_FILE}."
            tar -zcf "${ARCHIVE_FILE}" "${HOME_DIR}" &> /dev/null
            if [[ "${?}" -ne 0 ]]
            then
                echo "Could not create archive ${ARCHIVE_FILE}." >&2
                exit 1
            fi
        else
            echo "The home directory ${HOME_DIR} does not exist, so it will not be archived." >&2
            exit 1
        fi
    fi

    # Delete or disable the account.
    if [[ "${DELETE_USER}" = 'true' ]]
    then
        userdel ${REMOVE_HOME} "${USERNAME}"
        if [[ "${?}" -ne 0 ]]
        then
            echo "The account ${USERNAME} could not be deleted." >&2
            exit 1
        fi
        echo "The account ${USERNAME} has been deleted."
    else
        chage -E 0 "${USERNAME}"
        if [[ "${?}" -ne 0 ]]
        then
            echo "The account ${USERNAME} could not be disabled." >&2
            exit 1
        fi
        echo "The account ${USERNAME} has been disabled."
    fi
done

exit 0