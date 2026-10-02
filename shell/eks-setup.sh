#!/bin/bash

set -e

# ============================================================
# AWS EKS Developer Setup
# Supports:
#   - RHEL / Amazon Linux
#   - Debian / Ubuntu
# ============================================================

AWS_CONFIG="$HOME/.aws/config"
KUBECONFIG="$HOME/.kube/config"

echo
echo "=============================================="
echo "       AWS EKS Developer Setup"
echo "=============================================="
echo


# ============================================================
# Detect OS
# ============================================================

if [ -f /etc/redhat-release ]; then
    OS="rhel"
elif [ -f /etc/debian_version ]; then
    OS="debian"
else
    echo "Unsupported operating system."
    exit 1
fi

echo "Detected OS: $OS"


# ============================================================
# Check sudo
# ============================================================

if ! command -v sudo >/dev/null 2>&1; then
    echo "ERROR: sudo is required."
    exit 1
fi


# ============================================================
# Install required packages
# ============================================================

echo
echo "Checking required packages..."

if [ "$OS" = "rhel" ]; then

    if ! command -v curl >/dev/null 2>&1; then
        sudo yum install -y curl
    fi

    if ! command -v unzip >/dev/null 2>&1; then
        sudo yum install -y unzip
    fi

else

    if ! command -v curl >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y curl
    fi

    if ! command -v unzip >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y unzip
    fi

fi


# ============================================================
# AWS CLI
# ============================================================

if command -v aws >/dev/null 2>&1; then

    echo "✓ AWS CLI already installed"

else

    echo "Installing AWS CLI..."

    curl -sSL \
        "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
        -o /tmp/awscliv2.zip

    rm -rf /tmp/aws

    unzip -q /tmp/awscliv2.zip -d /tmp

    sudo /tmp/aws/install

    rm -rf /tmp/aws /tmp/awscliv2.zip

    echo "✓ AWS CLI installed"

fi


# ============================================================
# kubectl
# ============================================================

if command -v kubectl >/dev/null 2>&1; then

    echo "✓ kubectl already installed"

else

    echo "Installing kubectl..."

    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)

    curl -LO \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

    chmod +x kubectl

    sudo mv kubectl /usr/local/bin/kubectl

    rm -f kubectl

    echo "✓ kubectl installed"

fi


# ============================================================
# k9s
# ============================================================

if command -v k9s >/dev/null 2>&1; then

    echo "✓ k9s already installed"

else

    echo "Installing k9s..."

    K9S_VERSION=$(curl -s \
        https://api.github.com/repos/derailed/k9s/releases/latest \
        | grep '"tag_name":' \
        | cut -d '"' -f4)

    curl -L \
        "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" \
        -o /tmp/k9s.tar.gz

    tar -xzf /tmp/k9s.tar.gz -C /tmp

    sudo mv /tmp/k9s /usr/local/bin/k9s

    rm -f /tmp/k9s.tar.gz

    echo "✓ k9s installed"

fi


# ============================================================
# AWS configuration
# ============================================================

mkdir -p "$HOME/.aws"
chmod 700 "$HOME/.aws"

touch "$AWS_CONFIG"
chmod 600 "$AWS_CONFIG"


# ============================================================
# Common SSO configuration
# ============================================================

echo
echo "=============================================="
echo " AWS SSO Configuration"
echo "=============================================="
echo

read -p "AWS SSO Start URL: " SSO_START_URL
read -p "AWS SSO Region [ap-south-1]: " SSO_REGION

SSO_REGION=${SSO_REGION:-ap-south-1}


# ============================================================
# DEV
# ============================================================

echo
echo "----------- DEV Environment -----------"

read -p "DEV AWS Account ID: " DEV_ACCOUNT_ID
read -p "DEV SSO Role Name: " DEV_ROLE
read -p "DEV EKS Cluster Name: " DEV_CLUSTER
read -p "DEV AWS Region [ap-south-1]: " DEV_REGION

DEV_REGION=${DEV_REGION:-ap-south-1}


# ============================================================
# STAGE
# ============================================================

echo
echo "----------- STAGE Environment -----------"

read -p "STAGE AWS Account ID: " STAGE_ACCOUNT_ID
read -p "STAGE SSO Role Name: " STAGE_ROLE
read -p "STAGE EKS Cluster Name: " STAGE_CLUSTER
read -p "STAGE AWS Region [ap-south-1]: " STAGE_REGION

STAGE_REGION=${STAGE_REGION:-ap-south-1}


# ============================================================
# PROD
# ============================================================

echo
echo "----------- PROD Environment -----------"

read -p "PROD AWS Account ID: " PROD_ACCOUNT_ID
read -p "PROD SSO Role Name: " PROD_ROLE
read -p "PROD EKS Cluster Name: " PROD_CLUSTER
read -p "PROD AWS Region [ap-south-1]: " PROD_REGION

PROD_REGION=${PROD_REGION:-ap-south-1}


# ============================================================
# Configure AWS SSO session
# ============================================================

if ! grep -q "^\[sso-session company-sso\]" "$AWS_CONFIG"; then

cat >> "$AWS_CONFIG" <<EOF

[sso-session company-sso]
sso_start_url = $SSO_START_URL
sso_region = $SSO_REGION
sso_registration_scopes = sso:account:access

EOF

fi


# ============================================================
# Add DEV profile
# ============================================================

if ! grep -q "^\[profile dev\]" "$AWS_CONFIG"; then

cat >> "$AWS_CONFIG" <<EOF

[profile dev]
sso_session = company-sso
sso_account_id = $DEV_ACCOUNT_ID
sso_role_name = $DEV_ROLE
region = $DEV_REGION
output = json

EOF

fi


# ============================================================
# Add STAGE profile
# ============================================================

if ! grep -q "^\[profile stage\]" "$AWS_CONFIG"; then

cat >> "$AWS_CONFIG" <<EOF

[profile stage]
sso_session = company-sso
sso_account_id = $STAGE_ACCOUNT_ID
sso_role_name = $STAGE_ROLE
region = $STAGE_REGION
output = json

EOF

fi


# ============================================================
# Add PROD profile
# ============================================================

if ! grep -q "^\[profile prod\]" "$AWS_CONFIG"; then

cat >> "$AWS_CONFIG" <<EOF

[profile prod]
sso_session = company-sso
sso_account_id = $PROD_ACCOUNT_ID
sso_role_name = $PROD_ROLE
region = $PROD_REGION
output = json

EOF

fi


echo
echo "✓ AWS SSO profiles configured"


# ============================================================
# Select environment
# ============================================================

echo
echo "=============================================="
echo " Select Environment"
echo "=============================================="
echo
echo "1) DEV"
echo "2) STAGE"
echo "3) PROD"
echo

read -p "Enter choice [1-3]: " CHOICE

case "$CHOICE" in

    1)
        PROFILE="dev"
        CLUSTER="$DEV_CLUSTER"
        REGION="$DEV_REGION"
        ;;

    2)
        PROFILE="stage"
        CLUSTER="$STAGE_CLUSTER"
        REGION="$STAGE_REGION"
        ;;

    3)
        PROFILE="prod"
        CLUSTER="$PROD_CLUSTER"
        REGION="$PROD_REGION"
        ;;

    *)
        echo "Invalid choice."
        exit 1
        ;;

esac


# ============================================================
# AWS SSO Login
# ============================================================

echo
echo "Logging in to AWS SSO..."

aws sso login --profile "$PROFILE"


# ============================================================
# Configure kubeconfig
# ============================================================

echo
echo "Configuring kubeconfig..."

mkdir -p "$HOME/.kube"

aws eks update-kubeconfig \
    --name "$CLUSTER" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --alias "$PROFILE"


# ============================================================
# Verify
# ============================================================

echo
echo "=============================================="
echo " Setup Completed Successfully"
echo "=============================================="
echo

echo "AWS Profile : $PROFILE"
echo "EKS Cluster : $CLUSTER"
echo "Region      : $REGION"

echo
echo "Available Kubernetes contexts:"
kubectl config get-contexts

echo
echo "Test Kubernetes access:"
echo
echo "    kubectl get nodes"

echo
echo "Start K9s:"
echo
echo "    k9s"

echo
echo "==============================================="