# Service Account for namespace administration
resource "google_service_account" "namespace_admin" {
  account_id   = "namespace-admin"
  display_name = "Namespace Admin Service Account"
  description  = "Service account for managing Kubernetes namespaces"
}

# IAM bindings for namespace admin service account
# This service account needs container.developer to create namespaces and manage RBAC
resource "google_project_iam_member" "namespace_admin_roles" {
  for_each = toset([
    "roles/container.developer",    # Required to create namespaces and manage RBAC
    "roles/iam.serviceAccountAdmin" # Required to bind workload identity
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.namespace_admin.email}"
}

# Note: Per-namespace deployment service accounts are now created by the
# namespace module in namespaces.tf. Each namespace gets its own GCP service
# account with minimal permissions (container.clusterViewer + registry access).
