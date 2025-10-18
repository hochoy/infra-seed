# Namespace Module - Complete with Security and Resource Management
# This module creates a fully configured namespace with:
# - GCP Service Account with namespace administration permissions
# - Kubernetes Namespace and RBAC for users
# - Workload Identity Federation for GitHub repos
# - Resource Quotas and Limit Ranges
# - Network Policies
# - User access control

# 1. GCP Service Account (per namespace)
resource "google_service_account" "deployment" {
  account_id   = "deploy-${var.namespace_name}"
  display_name = "Deployment SA for ${var.namespace_name}"
  description  = "Service account for deploying to ${var.namespace_name} namespace"
}

# 2. GCP IAM Roles (Minimal permissions for cluster access)
# Only grant basic cluster viewer access for authentication
resource "google_project_iam_member" "deployment_roles" {
  for_each = toset([
    "roles/container.clusterViewer",    # Only view cluster (get credentials)
    "roles/artifactregistry.reader"     # Pull images
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.deployment.email}"
}

# 3. Artifact Registry write access (for pushing images during CI/CD)
resource "google_artifact_registry_repository_iam_member" "deployment_writer" {
  project    = var.project_id
  location   = var.region
  repository = var.artifact_registry_name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.deployment.email}"
}

# 4. Kubernetes Namespace
resource "kubernetes_namespace" "main" {
  metadata {
    name = var.namespace_name

    labels = {
      "managed-by" = "terraform"
      "name"       = var.namespace_name
    }
  }
}

# 5. GitHub Workload Identity Bindings (Multiple repos can use this SA)
# Each GitHub repo in the wif_repos list can authenticate as this GCP SA
resource "google_service_account_iam_member" "github_wif" {
  for_each = toset(var.wif_repos)

  service_account_id = google_service_account.deployment.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${var.wif_provider}/attribute.repository/${each.value}"
}

# 6. GSA Namespace Admin RoleBinding
# Grant the GSA admin permissions within this namespace only
resource "kubernetes_role_binding" "gsa_namespace_admin" {
  metadata {
    name      = "gsa-namespace-admin"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "namespace-admin-clusterrole"
  }

  subject {
    kind      = "User"
    name      = google_service_account.deployment.email
    api_group = "rbac.authorization.k8s.io"
  }
}

# 7. Administrator User RoleBindings
# Grant full namespace admin access to specified users
resource "kubernetes_role_binding" "admins" {
  for_each = { for idx, admin in var.administrators : idx => admin }

  metadata {
    name      = "admin-${replace(replace(each.value.email, "@", "-"), ".", "-")}"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "namespace-admin-clusterrole"
  }

  subject {
    kind      = "User"
    name      = each.value.email
    api_group = "rbac.authorization.k8s.io"
  }
}

# 8. Viewer User RoleBindings
# Grant read-only access to specified users
resource "kubernetes_role_binding" "viewers" {
  for_each = { for idx, viewer in var.viewers : idx => viewer }

  metadata {
    name      = "viewer-${replace(replace(each.value.email, "@", "-"), ".", "-")}"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "namespace-viewer-clusterrole"
  }

  subject {
    kind      = "User"
    name      = each.value.email
    api_group = "rbac.authorization.k8s.io"
  }
}

# 9. GCP IAM for Users (all users need cluster viewer to authenticate)
# Users need this to run 'gcloud container clusters get-credentials'
resource "google_project_iam_member" "user_cluster_access" {
  for_each = toset(concat(
    [for admin in var.administrators : admin.email],
    [for viewer in var.viewers : viewer.email]
  ))

  project = var.project_id
  role    = "roles/container.clusterViewer"
  member  = "user:${each.value}"
}

# 10. Resource Quota (limit namespace resource consumption)
# Prevents a single namespace from consuming all cluster resources
resource "kubernetes_resource_quota" "namespace_quota" {
  metadata {
    name      = "namespace-quota"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"           = var.quota_cpu_requests
      "requests.memory"        = var.quota_memory_requests
      "limits.cpu"             = var.quota_cpu_limits
      "limits.memory"          = var.quota_memory_limits
      "pods"                   = var.quota_pods
      "services"               = var.quota_services
      "persistentvolumeclaims" = var.quota_pvcs
    }
  }
}

# 11. Limit Range (default limits for pods without resource specs)
# Prevents pods without resource specifications from consuming unlimited resources
resource "kubernetes_limit_range" "namespace_limits" {
  metadata {
    name      = "namespace-limits"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  spec {
    # Container limits
    limit {
      type = "Container"

      default = {
        cpu    = var.default_cpu_limit
        memory = var.default_memory_limit
      }

      default_request = {
        cpu    = var.default_cpu_request
        memory = var.default_memory_request
      }

      max = {
        cpu    = var.max_cpu_limit
        memory = var.max_memory_limit
      }
    }

    # Pod limits
    limit {
      type = "Pod"

      max = {
        cpu    = var.max_pod_cpu
        memory = var.max_pod_memory
      }
    }
  }
}

# 12. Network Policy - Default Deny Ingress
# Security best practice: deny all ingress by default
resource "kubernetes_network_policy" "default_deny_ingress" {
  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

# 13. Network Policy - Allow Ingress from same namespace
# Pods in the same namespace can communicate with each other
resource "kubernetes_network_policy" "allow_same_namespace" {
  metadata {
    name      = "allow-same-namespace"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {}
      }
    }
  }
}

# 13. Network Policy - Allow from Specific Namespaces
# Allow traffic from specific namespaces for cross-namespace communication
resource "kubernetes_network_policy" "allow_from_namespaces" {
  count = length(var.allow_ingress_from_namespaces) > 0 ? 1 : 0

  metadata {
    name      = "allow-from-other-namespaces"
    namespace = kubernetes_namespace.main.metadata[0].name
  }

  spec {
    pod_selector {}  # Apply to all pods in namespace

    policy_types = ["Ingress"]

    dynamic "ingress" {
      for_each = var.allow_ingress_from_namespaces
      content {
        from {
          namespace_selector {
            match_labels = {
              "name" = ingress.value
            }
          }
        }
      }
    }
  }
}

# 14. HTTPRoute - Gateway API Routing
# Routes traffic from the main Gateway to services in this namespace
resource "kubernetes_manifest" "httproute" {
  count = var.routing.enabled ? 1 : 0

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "${var.namespace_name}-route"
      namespace = kubernetes_namespace.main.metadata[0].name
      labels = {
        "managed-by" = "terraform"
        "namespace"  = var.namespace_name
      }
    }
    spec = {
      parentRefs = [{
        name      = var.routing.gateway_name
        namespace = var.routing.gateway_namespace
      }]
      hostnames = [var.domain_name]
      rules = [{
        matches = [{
          path = {
            type  = "PathPrefix"
            value = var.routing.path_prefix
          }
        }]
        filters = var.routing.url_rewrite ? [{
          type = "URLRewrite"
          urlRewrite = {
            path = {
              type               = "ReplacePrefixMatch"
              replacePrefixMatch = var.routing.rewrite_target
            }
          }
        }] : []
        backendRefs = [{
          name = var.routing.service_name
          port = var.routing.service_port
        }]
      }]
    }
  }
}

# 15. ReferenceGrant - Allow HTTPRoute to reference Gateway in default namespace
# Enables cross-namespace reference as required by Gateway API RBAC
resource "kubernetes_manifest" "reference_grant" {
  count = var.routing.enabled ? 1 : 0

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "ReferenceGrant"
    metadata = {
      name      = "allow-${var.namespace_name}-gateway-access"
      namespace = var.routing.gateway_namespace
      labels = {
        "managed-by" = "terraform"
        "namespace"  = var.namespace_name
      }
    }
    spec = {
      from = [{
        group     = "gateway.networking.k8s.io"
        kind      = "HTTPRoute"
        namespace = kubernetes_namespace.main.metadata[0].name
      }]
      to = [{
        group = "gateway.networking.k8s.io"
        kind  = "Gateway"
        name  = var.routing.gateway_name
      }]
    }
  }
}

# 16. GCPBackendPolicy - Backend configuration for GCP load balancer
# Configures health checks, connection draining, logging for the service
resource "kubernetes_manifest" "backend_policy" {
  count = var.routing.enabled ? 1 : 0

  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "GCPBackendPolicy"
    metadata = {
      name      = "${var.namespace_name}-backend-policy"
      namespace = kubernetes_namespace.main.metadata[0].name
      labels = {
        "managed-by" = "terraform"
        "namespace"  = var.namespace_name
      }
    }
    spec = {
      default = {
        connectionDraining = {
          drainingTimeoutSec = 60
        }
        logging = {
          enabled    = true
          sampleRate = 1000000
        }
        timeoutSec = 30
      }
      targetRef = {
        group = ""
        kind  = "Service"
        name  = var.routing.service_name
      }
    }
  }
}
