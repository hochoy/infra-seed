

#!/bin/bash

# Read configuration from terraform.tfvars
TFVARS_FILE="terraform/terraform.tfvars"

if [ ! -f "$TFVARS_FILE" ]; then
    echo "Error: terraform/terraform.tfvars not found"
    echo "Please run ./scripts/init.sh first"
    exit 1
fi

# Extract values from terraform.tfvars
CLUSTER_NAME=$(grep 'gke_cluster_name' "$TFVARS_FILE" | cut -d'"' -f2)
REGION=$(grep 'region' "$TFVARS_FILE" | cut -d'"' -f2)
PROJECT_ID=$(grep 'project_id' "$TFVARS_FILE" | cut -d'"' -f2)

if [ -z "$CLUSTER_NAME" ] || [ -z "$REGION" ] || [ -z "$PROJECT_ID" ]; then
    echo "Error: Could not read cluster configuration from terraform.tfvars"
    echo "Please ensure terraform.tfvars contains: gke_cluster_name, region, project_id"
    exit 1
fi

# Authenticate to GKE Cluster. This is required for null_resource.wait_for_gateway_ip and null_resource.wait_for_cluster_ready
gcloud container clusters get-credentials "$CLUSTER_NAME" --region="$REGION" --project="$PROJECT_ID"

# Set CLOUDFLARE_API_TOKEN for terraform cloudflare provider
export CLOUDFLARE_API_TOKEN=$(gcloud secrets versions access latest --secret="cloudflare-api-token")

# Set GITHUB_TOKEN for terraform github provider
# Check if already authenticated, if not prompt for login
if ! gh auth status &>/dev/null; then
    echo "GitHub CLI not authenticated. Please authenticate:"
    gh auth login -s repo -s workflow
fi
export GITHUB_TOKEN=$(gh auth token)

echo ""
echo "Environment variables set:"
echo "  CLOUDFLARE_API_TOKEN: ✓"
echo "  GITHUB_TOKEN: ✓"
echo ""
echo "You can now run terraform commands."
