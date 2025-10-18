# Kubernetes RBAC Resources
# ClusterRoles that can be bound to service accounts in any namespace

# Administrator ClusterRole - Full namespace management permissions
resource "kubernetes_cluster_role" "namespace_admin" {
  metadata {
    name = "namespace-admin-clusterrole"
  }

  # Core resources
  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims", "events"]
    verbs      = ["*"]
  }

  # Apps resources
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs      = ["*"]
  }

  # Networking resources
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["*"]
  }

  # Batch resources
  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["*"]
  }

  # RBAC resources (within namespace)
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings"]
    verbs      = ["*"]
  }
}

# Deployment Admin ClusterRole - For GitHub Actions deployment service account
resource "kubernetes_cluster_role" "deployment_admin" {
  metadata {
    name = "deployment-admin-clusterrole"
  }

  # Core resources needed for deployments
  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps", "secrets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Deployment resources
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Networking for ingress
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # For rollout status checks
  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get", "list"]
  }
}

# Viewer ClusterRole - Read-only access
resource "kubernetes_cluster_role" "namespace_viewer" {
  metadata {
    name = "namespace-viewer-clusterrole"
  }

  # Core resources - read only
  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims", "events"]
    verbs      = ["get", "list", "watch"]
  }

  # Apps resources - read only
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs      = ["get", "list", "watch"]
  }

  # Networking resources - read only
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }

  # Pod logs
  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get", "list"]
  }
}
