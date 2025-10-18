# Outputs for Namespace Module

output "namespace_name" {
  description = "Name of the created namespace"
  value       = kubernetes_namespace.main.metadata[0].name
}

output "gcp_service_account_email" {
  description = "Email of the GCP service account for this namespace"
  value       = google_service_account.deployment.email
}

output "gcp_service_account_name" {
  description = "Name of the GCP service account for this namespace"
  value       = google_service_account.deployment.name
}

output "administrators" {
  description = "List of administrator users"
  value       = var.administrators
}

output "viewers" {
  description = "List of viewer users"
  value       = var.viewers
}

output "wif_repos" {
  description = "GitHub repos that can deploy to this namespace"
  value       = var.wif_repos
}

output "httproute_name" {
  description = "Name of the HTTPRoute (if routing is enabled)"
  value       = var.routing.enabled ? kubernetes_manifest.httproute[0].manifest.metadata.name : null
}

output "routing_path" {
  description = "Path prefix for this service"
  value       = var.routing.enabled ? var.routing.path_prefix : null
}
