# Random suffix for workload identity pool to avoid conflicts after soft-deletion
# No keepers means it generates once and stays stable until destroyed
resource "random_id" "workload_identity_suffix" {
  byte_length = 4

  # No keepers - stable during apply cycles, only changes on destroy/recreate
  # This avoids soft-delete conflicts while maintaining stability during normal operations
}

# Workload Identity Pool for GitHub Actions
# Using dynamic suffix to avoid conflicts when recreating after terraform destroy
# Workload Identity Pools have a 30-day soft-delete period before permanent deletion
# See: https://cloud.google.com/iam/docs/manage-workload-identity-pools-providers#delete-provider
resource "google_iam_workload_identity_pool" "github_actions" {
  workload_identity_pool_id = "github-actions-pool-${random_id.workload_identity_suffix.hex}"
  display_name              = "GitHub Actions Pool"
  description               = "Workload Identity Pool for GitHub Actions"
}

# Workload Identity Provider for GitHub Actions
resource "google_iam_workload_identity_pool_provider" "github_actions" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions-provider"
  display_name                       = "GitHub Actions Provider"
  description                        = "OIDC identity pool provider for GitHub Actions"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  attribute_condition = "assertion.repository.startsWith('${var.github_owner}/')"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# IAM binding for namespace admin service account to be used by GitHub Actions
resource "google_service_account_iam_member" "namespace_admin_github_actions" {
  service_account_id = google_service_account.namespace_admin.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/${var.github_owner}/${var.github_repo_name}"
}

# Note: Per-namespace deployment service account WIF bindings are now
# managed by the namespace module in namespaces.tf

# Additional permissions for the namespace admin to manage GKE clusters
resource "google_project_iam_member" "namespace_admin_cluster_admin" {
  project = var.project_id
  role    = "roles/container.clusterAdmin"
  member  = "serviceAccount:${google_service_account.namespace_admin.email}"
}
