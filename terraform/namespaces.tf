# Namespace Configurations
# This file defines all namespaces and their associated access control and WIF configurations.
# To add a new namespace, simply add an entry to the locals.namespaces map below.

locals {
  # Define all namespaces with their access control and GitHub repo permissions
  namespaces = {
    "service-one" = {
      administrators = []
      viewers        = []
      wif_repos      = [] # Will be dynamically set from generated repos
      routing = {
        enabled        = true
        path_prefix    = "/one"
        service_name   = "service-one-service"
        service_port   = 80
        url_rewrite    = true
        rewrite_target = "/"
      }
    }

    "service-two" = {
      administrators = []
      viewers        = []
      wif_repos      = [] # Will be dynamically set from generated repos
      routing = {
        enabled        = true
        path_prefix    = "/two"
        service_name   = "service-two-service"
        service_port   = 80
        url_rewrite    = true
        rewrite_target = "/"
      }
    }

    "service-three" = {
      administrators = []
      viewers        = []
      wif_repos      = [] # Will be dynamically set from generated repos
      routing = {
        enabled        = true
        path_prefix    = "/three"
        service_name   = "service-three-service"
        service_port   = 80
        url_rewrite    = true
        rewrite_target = "/"
      }
    }
  }
  
  # Dynamically add WIF repos from generated GitHub repositories
  namespaces_with_repos = {
    for k, v in local.namespaces : k => merge(v, {
      wif_repos = ["${var.github_owner}/${k}"]
    })
  }
}

# Create a namespace for each entry in the map
module "namespace" {
  source   = "./modules/namespace"
  for_each = local.namespaces_with_repos

  # Ensure cluster and node pool are created before namespace resources
  depends_on = [
    google_container_cluster.primary,
    google_container_node_pool.primary_nodes,
    github_repository.service
  ]

  # Namespace configuration
  namespace_name = each.key
  administrators = each.value.administrators
  viewers        = each.value.viewers
  wif_repos      = each.value.wif_repos

  # Shared GCP/GKE configuration
  project_id             = var.project_id
  region                 = var.region
  cluster_name           = var.gke_cluster_name
  wif_provider           = google_iam_workload_identity_pool.github_actions.name
  artifact_registry_name = google_artifact_registry_repository.main.name

  # Routing configuration
  routing     = each.value.routing
  domain_name = var.domain_name

  # Optional: Override default resource quotas per namespace if needed
  # quota_cpu_requests    = "20"
  # quota_memory_requests = "40Gi"
  # quota_pods            = "50"

  # Optional: Override default limit ranges per namespace if needed
  # default_cpu_limit     = "1"
  # default_memory_limit  = "1Gi"

  # Optional: Allow traffic from other namespaces (for cross-namespace communication)
  # allow_ingress_from_namespaces = ["service-one", "service-three"]
}

# Outputs for all namespaces
output "namespaces" {
  description = "Map of all namespace configurations"
  value = {
    for k, v in module.namespace : k => {
      namespace_name            = v.namespace_name
      gcp_service_account_email = v.gcp_service_account_email
      administrators            = v.administrators
      viewers                   = v.viewers
      wif_repos                 = v.wif_repos
    }
  }
}
