# Namespace Module

Terraform module for creating fully-configured, isolated Kubernetes namespaces with:
- Per-namespace GCP service account (minimal permissions)
- Kubernetes namespace and service account
- Workload Identity Federation for GitHub repos
- RBAC (namespace-scoped RoleBindings)
- Resource quotas and limit ranges
- Network policies (default deny + allow same namespace)
- User access control (administrators and viewers)

## Usage

```hcl
module "namespace" {
  source = "./modules/namespace"

  namespace_name = "my-app"
  
  administrators = [
    { email = "admin@example.com", name = "Admin User" }
  ]
  
  viewers = [
    { email = "viewer@example.com", name = "Viewer User" }
  ]
  
  wif_repos = [
    "org/my-app-repo"
  ]
  
  # Shared configuration
  project_id             = var.project_id
  region                 = var.region
  cluster_name           = var.gke_cluster_name
  wif_provider           = google_iam_workload_identity_pool_provider.github_actions.name
  artifact_registry_name = google_artifact_registry_repository.main.name
}
```

## What Gets Created

### GCP Resources
1. **Service Account**: `deploy-{namespace}@{project_id}.iam.gserviceaccount.com`
   - Minimal permissions: `container.clusterViewer`, `artifactregistry.reader/writer`
2. **IAM Policy Bindings**: For GCP SA and user access
3. **Workload Identity Bindings**: For GitHub repos

### Kubernetes Resources
1. **Namespace**: With managed-by label
2. **Service Account**: `deploy-${namespace_name}` with Workload Identity annotation
3. **RoleBinding**: Namespace-scoped binding to `deployment-admin-clusterrole`
4. **User RoleBindings**: For administrators and viewers
5. **Resource Quota**: CPU, memory, and pod limits
6. **Limit Range**: Default and max resource limits for containers
7. **Network Policies**: Default deny + allow same namespace + allow ingress controller

## Security Model

### Three-Layer Isolation

**Layer 1: GCP IAM**
- GCP SA has NO cluster modification permissions
- Can only authenticate and access Artifact Registry
- Cannot access other namespaces at GCP level

**Layer 2: Kubernetes RBAC**
- RoleBinding (namespace-scoped) limits actions to single namespace
- Cannot list or modify resources in other namespaces

**Layer 3: Workload Identity**
- Only specified GitHub repos can authenticate as the GCP SA
- Each team can have separate repos

## Default Resource Limits

Can be overridden per namespace:

### Resource Quotas
- CPU Requests: 10 cores
- Memory Requests: 20Gi
- CPU Limits: 20 cores
- Memory Limits: 40Gi
- Pods: 20
- Services: 10
- PVCs: 5

### Limit Ranges
- Default CPU Request: 100m
- Default Memory Request: 128Mi
- Default CPU Limit: 500m
- Default Memory Limit: 512Mi
- Max CPU: 2 cores per container, 4 cores per pod
- Max Memory: 4Gi per container, 8Gi per pod

## Inputs

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| namespace_name | string | yes | - | Name of the namespace |
| administrators | list(object) | no | [] | List of admin users |
| viewers | list(object) | no | [] | List of viewer users |
| wif_repos | list(string) | yes | - | GitHub repos (owner/repo) |
| project_id | string | yes | - | GCP project ID |
| region | string | yes | - | GCP region |
| cluster_name | string | yes | - | GKE cluster name |
| wif_provider | string | yes | - | WIF provider resource name |
| artifact_registry_name | string | yes | - | Artifact Registry repo name |

See `variables.tf` for all available variables including quota overrides.

## Outputs

| Name | Description |
|------|-------------|
| namespace_name | Created namespace name |
| gcp_service_account_email | GCP SA email |
| gcp_service_account_name | GCP SA name |
| kubernetes_service_account_name | Kubernetes SA name |

## Network Policies

1. **default-deny-ingress**: Blocks all inbound traffic by default
2. **allow-same-namespace**: Pods in namespace can communicate
3. **allow-from-other-namespaces** (optional): Allow traffic from specific namespaces

**Note**: For GKE ingress (which uses GCP Load Balancer outside the cluster), external traffic reaches pods directly via NEG (Network Endpoint Groups) and doesn't require a network policy.

## Example: Custom Resource Quotas

```hcl
module "high_resource_namespace" {
  source = "./modules/namespace"
  
  namespace_name = "ml-workloads"
  
  # Override default quotas for ML workloads
  quota_cpu_requests    = "50"
  quota_memory_requests = "100Gi"
  quota_pods            = "50"
  
  max_cpu_limit    = "8"
  max_memory_limit = "16Gi"
  
  # ... other required variables
}
```

## References

- Parent configuration: `../../namespaces.tf`
- Documentation: `../../docs/NAMESPACE_ISOLATION.md`
