#!/usr/bin/env bash

# ============================================================
# AWS EKS Developer / Platform Setup
#
# Supported OS:
#   - Amazon Linux / RHEL
#   - Ubuntu / Debian
#
# Installs:
#   - AWS CLI v2
#   - kubectl
#   - k9s
#
# Configures:
#   - AWS SSO
#   - DEV / STAGE / PROD AWS profiles
#   - EKS kubeconfig
#
# User input:
#   - SSO role name for each environment
#
# Everything else is predefined by the platform team.
# ============================================================

set -Eeuo pipefail

# ============================================================
# Configuration
# ============================================================

SCRIPT_NAME="$(basename "$0")"

AWS_CONFIG="${HOME}/.aws/config"
KUBECONFIG="${HOME}/.kube/config"

# ------------------------------------------------------------
# AWS SSO configuration
# ------------------------------------------------------------

SSO_START_URL="https://company.awsapps.com/start"
SSO_REGION="ap-south-1"

# ------------------------------------------------------------
# AWS Accounts
# These should normally be maintained by the platform team.
# ------------------------------------------------------------

DEV_ACCOUNT_ID=""
STAGE_ACCOUNT_ID=""
PROD_ACCOUNT_ID=""

# ------------------------------------------------------------
# EKS configuration
# ------------------------------------------------------------

DEV_CLUSTER="gp-dev-eks"
STAGE_CLUSTER="gp-stage-eks"
PROD_CLUSTER="gp-prod-eks"

DEV_REGION="ap-south-1"
STAGE_REGION="ap-south-1"
PROD_REGION="ap-south-1"

# ------------------------------------------------------------
# Profile names
# ------------------------------------------------------------

DEV_PROFILE="dev"
STAGE_PROFILE="stage"
PROD_PROFILE="prod"

# ------------------------------------------------------------
# Wait time between environments when ALL is selected
# ------------------------------------------------------------

ENV_WAIT_SECONDS=5

# ============================================================
# Logging
# ============================================================

log() {
    echo
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

success() {
    echo
    echo "✅ $*"
}

warning() {
    echo
    echo "⚠️  $*"
}

error() {
    echo
    echo "❌ $*" >&2
}

# ============================================================
# Error handling
# ============================================================

on_error() {
    local exit_code=$?
    local line_no=$1

    error "Script failed at line ${line_no} with exit code ${exit_code}."
    exit "$exit_code"
}

trap 'on_error $LINENO' ERR

# ============================================================
# Cleanup
# ============================================================

cleanup() {
    rm -f /tmp/awscliv2.zip
    rm -rf /tmp/aws
    rm -f /tmp/kubectl
    rm -f /tmp/k9s.tar.gz
    rm -rf /tmp/k9s
}

trap cleanup EXIT

# ============================================================
# Banner
# ============================================================

show_banner() {

    echo
    echo "============================================================"
    echo "              AWS EKS DEVELOPER SETUP"
    echo "============================================================"
    echo
    echo "This script will:"
    echo
    echo "  • Detect operating system"
    echo "  • Install AWS CLI"
    echo "  • Install kubectl"
    echo "  • Install k9s"
    echo "  • Configure AWS SSO"
    echo "  • Configure EKS kubeconfig"
    echo "  • Verify Kubernetes access"
    echo
    echo "============================================================"
}

# ============================================================
# Check root
# ============================================================

check_sudo() {

    if ! command -v sudo >/dev/null 2>&1; then
        error "sudo is required."
        exit 1
    fi

    if ! sudo -n true >/dev/null 2>&1; then
        warning "sudo password may be required during installation."
    fi
}

# ============================================================
# Detect operating system
# ============================================================

detect_os() {

    if [[ ! -f /etc/os-release ]]; then
        error "Unable to detect operating system."
        exit 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    case "${ID:-}" in

        amzn)
            OS="amazon"
            PACKAGE_MANAGER="yum"
            ;;

        rhel)
            OS="rhel"
            PACKAGE_MANAGER="yum"
            ;;

        ubuntu)
            OS="ubuntu"
            PACKAGE_MANAGER="apt"
            ;;

        debian)
            OS="debian"
            PACKAGE_MANAGER="apt"
            ;;

        *)
            error "Unsupported operating system: ${ID:-unknown}"
            exit 1
            ;;
    esac

    log "Detected OS: ${PRETTY_NAME:-$ID}"
}

# ============================================================
# Detect architecture
# ============================================================

detect_architecture() {

    ARCH="$(uname -m)"

    case "$ARCH" in

        x86_64)
            ARCH="amd64"
            ;;

        aarch64|arm64)
            ARCH="arm64"
            ;;

        *)
            error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    log "Detected architecture: $ARCH"
}

# ============================================================
# Install required OS packages
# ============================================================

install_required_packages() {

    log "Checking required OS packages..."

    if [[ "$PACKAGE_MANAGER" == "yum" ]]; then

        if ! command -v curl >/dev/null 2>&1; then
            sudo yum install -y curl
        fi

        if ! command -v unzip >/dev/null 2>&1; then
            sudo yum install -y unzip
        fi

        if ! command -v tar >/dev/null 2>&1; then
            sudo yum install -y tar
        fi

    elif [[ "$PACKAGE_MANAGER" == "apt" ]]; then

        sudo apt-get update -y

        if ! command -v curl >/dev/null 2>&1; then
            sudo apt-get install -y curl
        fi

        if ! command -v unzip >/dev/null 2>&1; then
            sudo apt-get install -y unzip
        fi

        if ! command -v tar >/dev/null 2>&1; then
            sudo apt-get install -y tar
        fi

    fi

    success "Required packages are available."
}

# ============================================================
# Install AWS CLI
# ============================================================

install_aws_cli() {

    if command -v aws >/dev/null 2>&1; then

        success "AWS CLI already installed."

        aws --version

        return
    fi

    log "Installing AWS CLI v2..."

    case "$ARCH" in

        amd64)
            AWS_ARCH="x86_64"
            ;;

        arm64)
            AWS_ARCH="aarch64"
            ;;

    esac

    curl -fsSL \
        "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" \
        -o /tmp/awscliv2.zip

    unzip -q /tmp/awscliv2.zip -d /tmp

    sudo /tmp/aws/install

    rm -rf /tmp/aws
    rm -f /tmp/awscliv2.zip

    if ! command -v aws >/dev/null 2>&1; then
        error "AWS CLI installation failed."
        exit 1
    fi

    success "AWS CLI installed."

    aws --version
}

# ============================================================
# Install kubectl
# ============================================================

install_kubectl() {

    if command -v kubectl >/dev/null 2>&1; then

        success "kubectl already installed."

        kubectl version --client --output=yaml 2>/dev/null || \
            kubectl version --client

        return
    fi

    log "Installing kubectl..."

    KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"

    case "$ARCH" in
        amd64)
            KUBE_ARCH="amd64"
            ;;
        arm64)
            KUBE_ARCH="arm64"
            ;;
    esac

    curl -fsSL \
        -o /tmp/kubectl \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBE_ARCH}/kubectl"

    chmod +x /tmp/kubectl

    sudo mv /tmp/kubectl /usr/local/bin/kubectl

    if ! command -v kubectl >/dev/null 2>&1; then
        error "kubectl installation failed."
        exit 1
    fi

    success "kubectl installed."

    kubectl version --client
}

# ============================================================
# Install k9s
# ============================================================

install_k9s() {

    if command -v k9s >/dev/null 2>&1; then

        success "k9s already installed."

        k9s version || true

        return
    fi

    log "Installing k9s..."

    case "$ARCH" in
        amd64)
            K9S_ARCH="amd64"
            ;;
        arm64)
            K9S_ARCH="arm64"
            ;;
    esac

    K9S_VERSION="$(curl -fsSL \
        https://api.github.com/repos/derailed/k9s/releases/latest |
        grep '"tag_name":' |
        head -1 |
        cut -d '"' -f4)"

    if [[ -z "$K9S_VERSION" ]]; then
        error "Unable to determine latest k9s version."
        exit 1
    fi

    K9S_URL="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${K9S_ARCH}.tar.gz"

    log "Downloading k9s ${K9S_VERSION}..."

    curl -fL \
        "$K9S_URL" \
        -o /tmp/k9s.tar.gz

    # --------------------------------------------------------
    # Validate archive before extracting
    # --------------------------------------------------------

    if ! gzip -t /tmp/k9s.tar.gz >/dev/null 2>&1; then

        error "Downloaded k9s file is not a valid gzip archive."
        error "URL: $K9S_URL"

        exit 1
    fi

    mkdir -p /tmp/k9s

    tar -xzf /tmp/k9s.tar.gz -C /tmp/k9s

    if [[ ! -f /tmp/k9s/k9s ]]; then
        error "k9s binary was not found after extraction."
        exit 1
    fi

    chmod +x /tmp/k9s/k9s

    sudo mv /tmp/k9s/k9s /usr/local/bin/k9s

    success "k9s installed."

    k9s version || true
}

# ============================================================
# Prepare AWS configuration
# ============================================================

prepare_aws_directory() {

    mkdir -p "$HOME/.aws"
    chmod 700 "$HOME/.aws"

    mkdir -p "$HOME/.kube"
    chmod 700 "$HOME/.kube"

    touch "$AWS_CONFIG"

    chmod 600 "$AWS_CONFIG"

    log "AWS and Kubernetes directories prepared."
}

# ============================================================
# Validate role input
# ============================================================

validate_role() {

    local environment="$1"
    local role="$2"

    if [[ -z "$role" ]]; then

        error "${environment} SSO role cannot be empty."

        exit 1
    fi
}

# ============================================================
# Add / Update AWS SSO profile
# ============================================================

configure_profile() {

    local profile="$1"
    local account_id="$2"
    local role="$3"
    local region="$4"

    log "Configuring AWS profile: $profile"

    # --------------------------------------------------------
    # Remove existing profile block if present.
    #
    # This avoids duplicate/stale values if the script is
    # executed again with a different role.
    # --------------------------------------------------------

    if grep -q "^\[profile ${profile}\]" "$AWS_CONFIG"; then

        log "Updating existing ${profile} profile..."

        awk -v profile="$profile" '
            BEGIN {
                skip=0
            }

            $0 == "[profile " profile "]" {
                skip=1
                next
            }

            /^\[profile / {
                skip=0
            }

            !skip {
                print
            }
        ' "$AWS_CONFIG" > "${AWS_CONFIG}.tmp"

        mv "${AWS_CONFIG}.tmp" "$AWS_CONFIG"
    fi

    cat >> "$AWS_CONFIG" <<EOF

[profile ${profile}]
sso_session = company-sso
sso_account_id = ${account_id}
sso_role_name = ${role}
region = ${region}
output = json
EOF

    chmod 600 "$AWS_CONFIG"

    success "AWS profile '${profile}' configured."
}

# ============================================================
# Configure AWS SSO session
# ============================================================

configure_sso_session() {

    if grep -q "^\[sso-session company-sso\]" "$AWS_CONFIG"; then

        log "AWS SSO session already configured."

        return
    fi

    log "Creating AWS SSO session configuration..."

    cat >> "$AWS_CONFIG" <<EOF

[sso-session company-sso]
sso_start_url = ${SSO_START_URL}
sso_region = ${SSO_REGION}
sso_registration_scopes = sso:account:access
EOF

    chmod 600 "$AWS_CONFIG"

    success "AWS SSO session configured."
}

# ============================================================
# Login to AWS SSO
# ============================================================

aws_sso_login() {

    local profile="$1"

    log "Logging in to AWS SSO using profile: $profile"

    aws sso login \
        --profile "$profile" \
        --use-device-code

    success "AWS SSO login successful for ${profile}."
}

# ============================================================
# Verify AWS identity
# ============================================================

verify_aws_identity() {

    local profile="$1"

    log "Verifying AWS identity..."

    local identity

    identity="$(aws sts get-caller-identity \
        --profile "$profile" \
        --output json)"

    if [[ -z "$identity" ]]; then

        error "Unable to verify AWS identity."

        return 1
    fi

    echo "$identity"

    success "AWS identity verified."
}

# ============================================================
# Configure EKS kubeconfig
# ============================================================

configure_eks() {

    local profile="$1"
    local cluster="$2"
    local region="$3"

    log "Configuring EKS kubeconfig..."

    aws eks update-kubeconfig \
        --name "$cluster" \
        --region "$region" \
        --profile "$profile" \
        --alias "$profile"

    success "Kubeconfig configured for ${cluster}."
}

# ============================================================
# Verify EKS
# ============================================================

verify_eks() {

    local profile="$1"
    local cluster="$2"

    log "Verifying Kubernetes access..."

    echo
    echo "AWS Profile : $profile"
    echo "EKS Cluster : $cluster"
    echo

    if ! kubectl --context "$profile" cluster-info; then

        error "Unable to connect to EKS cluster."
        error "Profile : $profile"
        error "Cluster : $cluster"

        return 1
    fi

    echo
    echo "Kubernetes nodes:"

    kubectl --context "$profile" get nodes \
        --request-timeout=30s || \
        warning "Connected to cluster, but 'get nodes' may not be permitted by RBAC."

    echo
    echo "Kubernetes contexts:"

    kubectl config get-contexts

    success "EKS access verified."
}

# ============================================================
# Setup one environment
# ============================================================

setup_environment() {

    local ENVIRONMENT="$1"
    local PROFILE="$2"
    local ACCOUNT_ID="$3"
    local ROLE="$4"
    local CLUSTER="$5"
    local REGION="$6"

    echo
    echo "============================================================"
    echo "             ${ENVIRONMENT} ENVIRONMENT"
    echo "============================================================"
    echo
    echo "AWS Profile : $PROFILE"
    echo "AWS Account : $ACCOUNT_ID"
    echo "EKS Cluster : $CLUSTER"
    echo "AWS Region  : $REGION"
    echo "SSO Role    : $ROLE"
    echo
    echo "============================================================"

    validate_role "$ENVIRONMENT" "$ROLE"

    configure_profile \
        "$PROFILE" \
        "$ACCOUNT_ID" \
        "$ROLE" \
        "$REGION"

    aws_sso_login "$PROFILE"

    verify_aws_identity "$PROFILE"

    configure_eks \
        "$PROFILE" \
        "$CLUSTER" \
        "$REGION"

    verify_eks \
        "$PROFILE" \
        "$CLUSTER"

    success "${ENVIRONMENT} environment setup completed."
}

# ============================================================
# Collect SSO Roles
# ============================================================

collect_roles() {

    echo
    echo "============================================================"
    echo "                 SSO ROLE CONFIGURATION"
    echo "============================================================"
    echo
    echo "Only the SSO role names are required."
    echo

    read -r -p "DEV SSO Role Name   : " DEV_ROLE

    read -r -p "STAGE SSO Role Name : " STAGE_ROLE

    read -r -p "PROD SSO Role Name  : " PROD_ROLE

    validate_role "DEV" "$DEV_ROLE"
    validate_role "STAGE" "$STAGE_ROLE"
    validate_role "PROD" "$PROD_ROLE"
}

# ============================================================
# Select environments
# ============================================================

select_environment() {

    echo
    echo "============================================================"
    echo "                 SELECT ENVIRONMENT"
    echo "============================================================"
    echo
    echo "1) DEV"
    echo "2) STAGE"
    echo "3) PROD"
    echo "4) ALL ENVIRONMENTS"
    echo

    while true; do

        read -r -p "Enter choice [1-4]: " CHOICE

        case "$CHOICE" in

            1)
                SELECTED_ENVIRONMENTS=("dev")
                break
                ;;

            2)
                SELECTED_ENVIRONMENTS=("stage")
                break
                ;;

            3)
                SELECTED_ENVIRONMENTS=("prod")
                break
                ;;

            4)
                SELECTED_ENVIRONMENTS=("dev" "stage" "prod")
                break
                ;;

            *)
                warning "Invalid choice. Please enter 1, 2, 3 or 4."
                ;;

        esac
    done
}

# ============================================================
# Run selected environments
# ============================================================

run_environments() {

    local environment

    for environment in "${SELECTED_ENVIRONMENTS[@]}"; do

        case "$environment" in

            dev)

                setup_environment \
                    "DEV" \
                    "$DEV_PROFILE" \
                    "$DEV_ACCOUNT_ID" \
                    "$DEV_ROLE" \
                    "$DEV_CLUSTER" \
                    "$DEV_REGION"

                ;;

            stage)

                setup_environment \
                    "STAGE" \
                    "$STAGE_PROFILE" \
                    "$STAGE_ACCOUNT_ID" \
                    "$STAGE_ROLE" \
                    "$STAGE_CLUSTER" \
                    "$STAGE_REGION"

                ;;

            prod)

                setup_environment \
                    "PROD" \
                    "$PROD_PROFILE" \
                    "$PROD_ACCOUNT_ID" \
                    "$PROD_ROLE" \
                    "$PROD_CLUSTER" \
                    "$PROD_REGION"

                ;;

        esac

        # ----------------------------------------------------
        # Wait before next environment
        # ----------------------------------------------------

        if [[ "${#SELECTED_ENVIRONMENTS[@]}" -gt 1 ]]; then

            echo
            echo "------------------------------------------------------------"
            echo "Environment '${environment}' completed."
            echo "Waiting ${ENV_WAIT_SECONDS} seconds before next environment..."
            echo "------------------------------------------------------------"

            sleep "$ENV_WAIT_SECONDS"
        fi

    done
}

# ============================================================
# Final Summary
# ============================================================

show_summary() {

    echo
    echo "============================================================"
    echo "              SETUP COMPLETED SUCCESSFULLY"
    echo "============================================================"
    echo

    echo "Installed tools:"
    echo "  ✓ AWS CLI"
    echo "  ✓ kubectl"
    echo "  ✓ k9s"

    echo
    echo "Configured AWS profiles:"
    echo "  ✓ dev"
    echo "  ✓ stage"
    echo "  ✓ prod"

    echo
    echo "Configured Kubernetes contexts:"

    kubectl config get-contexts

    echo
    echo "============================================================"
    echo
    echo "Useful commands:"
    echo
    echo "  kubectl config get-contexts"
    echo
    echo "  kubectl --context dev get nodes"
    echo "  kubectl --context stage get nodes"
    echo "  kubectl --context prod get nodes"
    echo
    echo "  k9s --context dev"
    echo "  k9s --context stage"
    echo "  k9s --context prod"
    echo
    echo "============================================================"
}

# ============================================================
# MAIN
# ============================================================

main() {

    show_banner

    check_sudo

    detect_os

    detect_architecture

    install_required_packages

    install_aws_cli

    install_kubectl

    install_k9s

    prepare_aws_directory

    configure_sso_session

    collect_roles

    select_environment

    run_environments

    show_summary
}

main "$@"