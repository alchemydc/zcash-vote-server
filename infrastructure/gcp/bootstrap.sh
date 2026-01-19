#!/bin/bash
set -euo pipefail

##########
# GCP Bootstrap Script for zcash-vote-server Validators
# 
# This script prepares a GCP project for deploying validators:
# - Creates a new GCP project (optional) OR uses existing project
# - Enables required APIs
# - Creates Terraform service account with minimal permissions
# - Configures short-lived access tokens
# - Optionally creates GCS bucket for Terraform state
#
# Prerequisites:
# - gcloud CLI installed and authenticated
# - For new projects: Organization access and billing account
# - For existing projects: Project Owner or Editor role
#
# Usage:
#   ./bootstrap.sh [--create-project] [--with-state-bucket]
##########

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GCLOUD_ENV_FILE="${SCRIPT_DIR}/gcloud.env"
BACKEND_FILE="${SCRIPT_DIR}/backend.tf"
CREATE_PROJECT=false
CREATE_STATE_BUCKET=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --create-project)
            CREATE_PROJECT=true
            shift
            ;;
        --with-state-bucket)
            CREATE_STATE_BUCKET=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--create-project] [--with-state-bucket]"
            echo ""
            echo "Options:"
            echo "  --create-project      Create a new GCP project (requires org access)"
            echo "  --with-state-bucket   Create GCS bucket for Terraform remote state"
            echo "  -h, --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  # Use existing project with local state:"
            echo "  ./bootstrap.sh"
            echo ""
            echo "  # Create new project with remote state:"
            echo "  ./bootstrap.sh --create-project --with-state-bucket"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

echo "============================================"
echo "GCP Bootstrap for zcash-vote-server"
echo "============================================"
echo ""

# Check for terraform or tofu installation
if command -v tofu >/dev/null 2>&1; then
    TERRAFORM_CMD="tofu"
elif command -v terraform >/dev/null 2>&1; then
    TERRAFORM_CMD="terraform"
else
    echo "Error: Neither terraform nor tofu is installed"
    echo "Please install OpenTofu (recommended) or Terraform:"
    echo "  brew install opentofu"
    exit 1
fi

echo "✓ Using ${TERRAFORM_CMD} as Terraform provider"

# Check for gcloud CLI
if ! command -v gcloud >/dev/null 2>&1; then
    echo "Error: gcloud CLI is not installed"
    echo "Please install the gcloud CLI:"
    echo "  brew install google-cloud-sdk"
    exit 1
fi

echo "✓ gcloud CLI found"

# Source or create gcloud.env
echo ""
echo "Checking for gcloud.env configuration..."
if [ -f "$GCLOUD_ENV_FILE" ]; then
    echo "✓ Found existing gcloud.env, sourcing..."
    source "$GCLOUD_ENV_FILE"
else
    echo "Creating gcloud.env template..."
    if [ "$CREATE_PROJECT" = true ]; then
        cat > "$GCLOUD_ENV_FILE" << 'EOF'
# GCP Bootstrap Configuration for NEW Project
# Fill in these values before running bootstrap.sh --create-project

# Organization ID (get with: gcloud organizations list --format="value(ID)")
export TF_VAR_org_id="YOUR_ORG_ID"

# Billing account (get with: gcloud billing accounts list --format="value(name)")
export TF_VAR_billing_account="YOUR_BILLING_ACCOUNT_ID"

# New project ID (must be globally unique, 6-30 chars, lowercase, numbers, hyphens)
export TF_VAR_project_id="zcash-vote-prod-001"

# GCP region and zone for validator deployment
export TF_VAR_region="us-central1"
export TF_VAR_zone="us-central1-a"

# These will be added by bootstrap.sh:
# export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token --impersonate-service-account terraform@${TF_VAR_project_id}.iam.gserviceaccount.com)
EOF
    else
        cat > "$GCLOUD_ENV_FILE" << 'EOF'
# GCP Bootstrap Configuration for EXISTING Project
# Fill in these values before running bootstrap.sh

# Your existing GCP project ID
export TF_VAR_project_id="your-existing-project-id"

# GCP region and zone for validator deployment
export TF_VAR_region="us-central1"
export TF_VAR_zone="us-central1-a"

# These will be added by bootstrap.sh:
# export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token --impersonate-service-account terraform@${TF_VAR_project_id}.iam.gserviceaccount.com)
EOF
    fi
    echo ""
    echo "ERROR: gcloud.env template created but not configured"
    echo "Please edit ${GCLOUD_ENV_FILE} and set the required variables"
    if [ "$CREATE_PROJECT" = true ]; then
        echo "  For new project, you need:"
        echo "  - TF_VAR_org_id"
        echo "  - TF_VAR_billing_account"
        echo "  - TF_VAR_project_id (new unique project ID)"
    else
        echo "  For existing project, you need:"
        echo "  - TF_VAR_project_id (your existing project)"
    fi
    echo "  - TF_VAR_region"
    echo "  - TF_VAR_zone"
    echo ""
    echo "Then run this script again."
    exit 1
fi

# Validate required variables
if [ -z "${TF_VAR_project_id:-}" ] || \
   [ "${TF_VAR_project_id}" = "your-existing-project-id" ] || \
   [ "${TF_VAR_project_id}" = "zcash-vote-prod-001" ]; then
    echo "ERROR: TF_VAR_project_id not set in gcloud.env"
    echo "Please edit ${GCLOUD_ENV_FILE} and set your GCP project ID"
    exit 1
fi

if [ "$CREATE_PROJECT" = true ]; then
    if [ -z "${TF_VAR_org_id:-}" ] || [ "${TF_VAR_org_id}" = "YOUR_ORG_ID" ]; then
        echo "ERROR: TF_VAR_org_id not set in gcloud.env"
        echo "Get your org ID with: gcloud organizations list --format=\"value(ID)\""
        exit 1
    fi
    
    if [ -z "${TF_VAR_billing_account:-}" ] || [ "${TF_VAR_billing_account}" = "YOUR_BILLING_ACCOUNT_ID" ]; then
        echo "ERROR: TF_VAR_billing_account not set in gcloud.env"
        echo "Get billing account with: gcloud billing accounts list --format=\"value(name)\""
        exit 1
    fi
fi

if [ -z "${TF_VAR_region:-}" ]; then
    echo "ERROR: TF_VAR_region not set in gcloud.env"
    exit 1
fi

if [ -z "${TF_VAR_zone:-}" ]; then
    echo "ERROR: TF_VAR_zone not set in gcloud.env"
    exit 1
fi

echo "✓ Configuration validated"
echo "  Project: ${TF_VAR_project_id}"
echo "  Region:  ${TF_VAR_region}"
echo "  Zone:    ${TF_VAR_zone}"

# Create new project if requested
if [ "$CREATE_PROJECT" = true ]; then
    echo ""
    echo "Creating new GCP project..."
    
    if gcloud projects describe "${TF_VAR_project_id}" >/dev/null 2>&1; then
        echo "✓ Project already exists: ${TF_VAR_project_id}"
    else
        echo "  Creating project: ${TF_VAR_project_id}"
        gcloud projects create "${TF_VAR_project_id}" \
            --organization="${TF_VAR_org_id}" \
            --set-as-default
        
        echo "  Linking billing account..."
        gcloud billing projects link "${TF_VAR_project_id}" \
            --billing-account="${TF_VAR_billing_account}"
        
        echo "✓ Created and configured new project"
    fi
fi

# Set active project
echo ""
echo "Setting active GCP project..."
gcloud config set project "${TF_VAR_project_id}"

# Enable required APIs
echo ""
echo "Enabling required GCP APIs..."
REQUIRED_APIS=(
    "compute.googleapis.com"
    "iam.googleapis.com"
    "cloudresourcemanager.googleapis.com"
    "logging.googleapis.com"
    "monitoring.googleapis.com"
)

for API in "${REQUIRED_APIS[@]}"; do
    echo "  Enabling ${API}..."
    gcloud services enable "${API}" --project="${TF_VAR_project_id}"
done

echo "✓ All required APIs enabled"

# Create Terraform service account
echo ""
echo "Creating Terraform service account..."
TERRAFORM_SA="terraform@${TF_VAR_project_id}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "${TERRAFORM_SA}" --project="${TF_VAR_project_id}" >/dev/null 2>&1; then
    echo "✓ Terraform service account already exists: ${TERRAFORM_SA}"
else
    gcloud iam service-accounts create terraform \
        --display-name="Terraform Service Account" \
        --description="Service account for OpenTofu/Terraform to manage validator infrastructure" \
        --project="${TF_VAR_project_id}"
    
    echo "✓ Created service account: ${TERRAFORM_SA}"
fi

# Wait for service account to propagate
echo ""
echo "Waiting for service account to propagate..."
start_time=$(date +%s)
max_wait=180  # 3 minutes
retry_interval=10

while true; do
    if gcloud auth print-access-token \
        --impersonate-service-account="${TERRAFORM_SA}" \
        --project="${TF_VAR_project_id}" >/dev/null 2>&1; then
        echo "✓ Service account is ready"
        break
    fi

    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    if [ $elapsed -ge $max_wait ]; then
        echo "ERROR: Service account not ready after ${max_wait} seconds"
        echo "This may be a temporary issue. Try running the script again."
        exit 1
    fi

    echo "  Waiting... (${elapsed}s elapsed)"
    sleep $retry_interval
done

# Grant required roles to Terraform service account
echo ""
echo "Granting roles to Terraform service account..."
TERRAFORM_ROLES=(
    "roles/compute.admin"                    # Create VMs, networks, firewall rules
    "roles/iam.serviceAccountAdmin"          # Create validator service accounts
    "roles/iam.serviceAccountUser"           # Assign service accounts to VMs
    "roles/resourcemanager.projectIamAdmin"  # Grant roles to validator service accounts
)

for ROLE in "${TERRAFORM_ROLES[@]}"; do
    echo "  Granting ${ROLE}..."
    gcloud projects add-iam-policy-binding "${TF_VAR_project_id}" \
        --member="serviceAccount:${TERRAFORM_SA}" \
        --role="${ROLE}" \
        --condition=None \
        >/dev/null
done

echo "✓ Granted all required roles"

# Configure short-lived token generation
echo ""
echo "Configuring automatic token generation in gcloud.env..."

# Remove old token line if it exists
if grep -q "GOOGLE_OAUTH_ACCESS_TOKEN" "$GCLOUD_ENV_FILE"; then
    # Create temp file without the old line
    grep -v "GOOGLE_OAUTH_ACCESS_TOKEN" "$GCLOUD_ENV_FILE" > "${GCLOUD_ENV_FILE}.tmp"
    mv "${GCLOUD_ENV_FILE}.tmp" "$GCLOUD_ENV_FILE"
fi

# Add new token generation line
cat >> "$GCLOUD_ENV_FILE" << EOF

# Auto-generated by bootstrap.sh - DO NOT EDIT
# This line generates a new short-lived access token each time gcloud.env is sourced
export GOOGLE_OAUTH_ACCESS_TOKEN=\$(gcloud auth print-access-token --impersonate-service-account ${TERRAFORM_SA})
EOF

echo "✓ Token generation configured"

# Create GCS state bucket (optional)
if [ "$CREATE_STATE_BUCKET" = true ]; then
    echo ""
    echo "Creating GCS bucket for Terraform state..."
    TF_STATE_BUCKET="${TF_VAR_project_id}-zcash-vote-tfstate"
    
    if gsutil ls -p "${TF_VAR_project_id}" "gs://${TF_STATE_BUCKET}" >/dev/null 2>&1; then
        echo "✓ State bucket already exists: ${TF_STATE_BUCKET}"
    else
        gsutil mb -p "${TF_VAR_project_id}" -l "${TF_VAR_region}" "gs://${TF_STATE_BUCKET}"
        gsutil versioning set on "gs://${TF_STATE_BUCKET}"
        
        # Grant Terraform SA access to state bucket
        gsutil iam ch "serviceAccount:${TERRAFORM_SA}:roles/storage.admin" "gs://${TF_STATE_BUCKET}"
        
        echo "✓ Created state bucket: ${TF_STATE_BUCKET}"
    fi
    
    # Create backend.tf
    echo ""
    echo "Creating backend.tf for remote state..."
    cat > "$BACKEND_FILE" << EOF
# Terraform backend configuration for GCS
# Auto-generated by bootstrap.sh

terraform {
  backend "gcs" {
    bucket = "${TF_STATE_BUCKET}"
    prefix = "validators"
  }
}
EOF
    echo "✓ Created backend.tf"
fi

# Source the updated environment
echo ""
echo "Loading credentials..."
source "$GCLOUD_ENV_FILE"

# Initialize Terraform
echo ""
echo "Initializing Terraform..."
cd "$SCRIPT_DIR"

if [ -f "$BACKEND_FILE" ]; then
    $TERRAFORM_CMD init -migrate-state
else
    $TERRAFORM_CMD init
fi

echo ""
echo "============================================"
echo "✓ Bootstrap Complete!"
echo "============================================"
echo ""
if [ "$CREATE_PROJECT" = true ]; then
    echo "Created new project: ${TF_VAR_project_id}"
fi
echo "Terraform service account: ${TERRAFORM_SA}"
if [ "$CREATE_STATE_BUCKET" = true ]; then
    echo "State bucket: gs://${TF_STATE_BUCKET}"
fi
echo ""
echo "Next steps:"
echo "1. Source the environment: source gcloud.env"
echo "2. Configure validator variables in gcloud.env:"
echo "   - TF_VAR_validator_name"
echo "   - TF_VAR_admin_ssh_key"
echo "   - TF_VAR_admin_ip_ranges"
echo "   (See gcloud.env.example for all options)"
echo ""
echo "3. Deploy a validator:"
echo "   ${TERRAFORM_CMD} plan"
echo "   ${TERRAFORM_CMD} apply"
echo ""
echo "Note: Access tokens expire after 1 hour."
echo "Re-source gcloud.env to get a new token: source gcloud.env"
echo ""
