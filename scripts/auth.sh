

#!/bin/bash

# Authenticate to GKE Cluster. This is required for null_resource.wait_for_gateway_ip and null_resource.wait_for_cluster_ready
gcloud container clusters get-credentials infra-seed-cluster --region=us-central1 --project=$(gcloud config get-value project)

# Set CLOUDFLARE_API_TOKEN for terraform cloudflare provider
export CLOUDFLARE_API_TOKEN=$(gcloud secrets versions access latest --secret="cloudflare-api-token")

# Set GITHUB_TOKEN for terraform github provider
gh auth login --scope repo,workflow,repo
export GITHUB_TOKEN=$(gh auth token)