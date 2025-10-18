output "project_id" {
  description = "The GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "The GCP region"
  value       = var.region
}

output "gke_cluster_name" {
  description = "Name of the GKE cluster"
  value       = google_container_cluster.primary.name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.primary.endpoint
  sensitive   = true
}

output "artifact_registry_url" {
  description = "URL of the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.main.repository_id}"
}

output "namespace_admin_sa_email" {
  description = "Email of the namespace admin service account"
  value       = google_service_account.namespace_admin.email
}

# Note: Per-namespace deployment service account emails are now
# output from the namespaces module in namespaces.tf

output "workload_identity_pool_name" {
  description = "Name of the Workload Identity Pool"
  value       = google_iam_workload_identity_pool.github_actions.name
}

output "workload_identity_provider_name" {
  description = "Name of the Workload Identity Provider"
  value       = google_iam_workload_identity_pool_provider.github_actions.name
}
