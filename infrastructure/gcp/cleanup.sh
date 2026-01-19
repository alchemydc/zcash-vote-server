#!/bin/bash
set -euo pipefail

##########
# GCP Cleanup Script for zcash-vote-server Bootstrap
# 
# This script removes bootstrap resources created by bootstrap.sh:
# - Removes IAM role bindings from Terraform service account
# - Deletes Terraform service account
# - Optionally deletes GCS state bucket
# - Removes backend.tf
# - Cleans up gcloud.env
#
# WARNING: This does NOT delete validator infrastructure or the GCP project.
# Only bootstrap/Terraform management resources are removed.
#
# Usage:
#   ./cleanup.sh [--delete-state-bucket] [--delete-project]
##########

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GCLOUD_ENV_FILE="${SCRIPT_DIR}/gcloud.env"
BACKEND_FILE="${SCRIPT_DIR}/backend.tf"
DELETE_STATE_BUCKET=false
DELETE_PROJECT=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --delete-state-bucket)
            DELETE_STATE_BUCKET=true
            shift
            ;;
        --delete-project)
            DELETE_PROJECT=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--delete-state-bucket] [--delete-project]"
            echo ""
            echo "Options:"
            echo "  --delete-state-bucket  Delete GCS state bucket (WARNING: destroys state)"
            echo "  --delete-project       Delete the entire GCP project (DANGEROUS!)"
            echo "  -h, --help            Show this help message"
            echo ""
            echo "This script removes bootstrap resources:"
            echo "  - Terraform service account and IAM bindings"
            echo "  - backend.tf file"
            echo "  - Token generation line from gcloud.env"
            echo ""
            echo "WARNING: Run 'tofu destroy' first to remove validator infrastructure!"
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
echo "GCP Bootstrap Cleanup"
echo "============================================"
echo ""

# Check for gcloud CLI
if ! command -v gcloud >/dev/null 2>&1; then
    echo "Error: gcloud CLI is not installed"
    exit 1
fi

# Source gcloud.env if it exists
if [ ! -f "$GCLOUD_ENV_FILE" ]; then
    echo "Error: gcloud.env not found"
    echo "Nothing to clean up."
    exit 0
fi

source "$GCLOUD_ENV_FILE"

if [ -z "${TF_VAR_project_id:-}" ]; then
    echo "Error: TF_VAR_project_id not set in gcloud.env"
    exit 1
fi

echo "Project: ${TF_VAR_project_id}"
echo ""

# Confirm with user
echo "WARNING: This will remove bootstrap resources for project: ${TF_VAR_project_id}"
if [ "$DELETE_STATE_BUCKET" = true ]; then
    echo "  - Will DELETE Terraform state bucket (ALL STATE WILL BE LOST)"
fi
if [ "$DELETE_PROJECT" = true ]; then
    echo "  - Will DELETE THE ENTIRE PROJECT (THIS CANNOT BE UNDONE)"
fi
echo ""
echo "Make sure you have run 'tofu destroy' first to remove validator infrastructure!"
echo ""
read -p "Continue? (yes/no): " -r
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

TERRAFORM_SA="terraform@${TF_VAR_project_id}.iam.gserviceaccount.com"

# Delete project if requested
if [ "$DELETE_PROJECT" = true ]; then
    echo ""
    echo "DELETING PROJECT: ${TF_VAR_project_id}"
    echo "This will delete everything in the project!"
    read -p "Are you ABSOLUTELY sure? Type the project ID to confirm: " -r
    if [[ $REPLY != "$TF_VAR_project_id" ]]; then
        echo "Project ID did not match. Aborting."
        exit 1
    fi
    
    echo "Deleting project..."
    gcloud projects delete "${TF_VAR_project_id}" --quiet || true
    
    echo ""
    echo "✓ Project deleted: ${TF_VAR_project_id}"
    echo "✓ All resources in the project have been deleted"
    
    # Clean up local files
    if [ -f "$BACKEND_FILE" ]; then
        rm "$BACKEND_FILE"
        echo "✓ Removed backend.tf"
    fi
    
    if [ -f "$GCLOUD_ENV_FILE" ]; then
        rm "$GCLOUD_ENV_FILE"
        echo "✓ Removed gcloud.env"
    fi
    
    echo ""
    echo "Cleanup complete! Project and all local configuration removed."
    exit 0
fi

# Check if service account exists
if ! gcloud iam service-accounts describe "${TERRAFORM_SA}" --project="${TF_VAR_project_id}" >/dev/null 2>&1; then
    echo "Terraform service account not found: ${TERRAFORM_SA}"
    echo "May have already been deleted."
else
    # Remove IAM role bindings
    echo ""
    echo "Removing IAM role bindings..."
    TERRAFORM_ROLES=(
        "roles/compute.admin"
        "roles/iam.serviceAccountAdmin"
        "roles/iam.serviceAccountUser"
        "roles/resourcemanager.projectIamAdmin"
    )

    for ROLE in "${TERRAFORM_ROLES[@]}"; do
        echo "  Removing ${ROLE}..."
        gcloud projects remove-iam-policy-binding "${TF_VAR_project_id}" \
            --member="serviceAccount:${TERRAFORM_SA}" \
            --role="${ROLE}" \
            --quiet 2>/dev/null || echo "    (role not found, skipping)"
    done

    echo "✓ Removed IAM bindings"

    # Delete service account
    echo ""
    echo "Deleting Terraform service account..."
    gcloud iam service-accounts delete "${TERRAFORM_SA}" \
        --project="${TF_VAR_project_id}" \
        --quiet
    
    echo "✓ Deleted service account: ${TERRAFORM_SA}"
fi

# Delete state bucket if requested
if [ "$DELETE_STATE_BUCKET" = true ]; then
    TF_STATE_BUCKET="${TF_VAR_project_id}-zcash-vote-tfstate"
    
    echo ""
    echo "Checking for state bucket..."
    if gsutil ls -p "${TF_VAR_project_id}" "gs://${TF_STATE_BUCKET}" >/dev/null 2>&1; then
        echo "WARNING: About to delete bucket: ${TF_STATE_BUCKET}"
        echo "This will destroy all Terraform state!"
        read -p "Type 'DELETE' to confirm: " -r
        if [[ $REPLY != "DELETE" ]]; then
            echo "Skipping bucket deletion."
        else
            echo "Deleting bucket and all contents..."
            gsutil -m rm -r "gs://${TF_STATE_BUCKET}" || true
            echo "✓ Deleted state bucket: ${TF_STATE_BUCKET}"
        fi
    else
        echo "State bucket not found (may not have been created)"
    fi
fi

# Remove backend.tf
if [ -f "$BACKEND_FILE" ]; then
    echo ""
    echo "Removing backend.tf..."
    rm "$BACKEND_FILE"
    echo "✓ Removed backend.tf"
fi

# Clean up gcloud.env
echo ""
echo "Cleaning up gcloud.env..."

if grep -q "GOOGLE_OAUTH_ACCESS_TOKEN" "$GCLOUD_ENV_FILE"; then
    # Remove token generation line
    grep -v "GOOGLE_OAUTH_ACCESS_TOKEN" "$GCLOUD_ENV_FILE" > "${GCLOUD_ENV_FILE}.tmp"
    
    # Remove "Auto-generated" comment line if it exists
    grep -v "Auto-generated by bootstrap.sh" "${GCLOUD_ENV_FILE}.tmp" > "${GCLOUD_ENV_FILE}.tmp2" || true
    mv "${GCLOUD_ENV_FILE}.tmp2" "${GCLOUD_ENV_FILE}"
    rm -f "${GCLOUD_ENV_FILE}.tmp"
    
    echo "✓ Removed token generation from gcloud.env"
else
    echo "✓ No token generation found in gcloud.env"
fi

echo ""
echo "============================================"
echo "✓ Cleanup Complete!"
echo "============================================"
echo ""
echo "Removed:"
echo "  - Terraform service account and IAM bindings"
echo "  - backend.tf (if existed)"
echo "  - Token generation from gcloud.env"
if [ "$DELETE_STATE_BUCKET" = true ]; then
    echo "  - GCS state bucket (if existed)"
fi
echo ""
echo "gcloud.env has been cleaned but preserved for future use."
echo "You can run bootstrap.sh again to recreate the bootstrap resources."
echo ""
