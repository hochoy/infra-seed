# Building a Production-Ready Infrastructure Starter Kit: A Complete Guide

## Table of Contents

1. [Introduction](#introduction)
2. [The Problem: Infrastructure Prototyping](#the-problem)
3. [Requirements & Goals](#requirements-and-goals)
4. [Architecture Overview](#architecture-overview)
5. [Implementation Deep Dive](#implementation-deep-dive)
6. [Automation & Developer Experience](#automation-and-developer-experience)
7. [Security Implementation](#security-implementation)
8. [Networking & Traffic Flow](#networking-and-traffic-flow)
9. [Operational Tooling](#operational-tooling)
10. [Cost Analysis](#cost-analysis)
11. [Technical Decisions & Trade-offs](#technical-decisions-and-tradeoffs)
12. [Lessons Learned](#lessons-learned)
13. [Future Enhancements](#future-enhancements)
14. [Conclusion](#conclusion)

---

## Introduction

Whether as a solo founder or a staff engineer in an organization, infrastructure prototypes are sometimes harder to spin up than software prototypes - especially when they need to simulate or actually serve as a production environment. You can't just write a few files and test locally; you need real cloud resources, proper security, and a way to reproduce the setup reliably.

This blog post documents my journey building a complete Kubernetes infrastructure starter kit that is:
- **Production-ready** with security best practices
- **Developer-friendly** with automated onboarding
- **Budget-conscious** at ~$128/month (~$4/day)
- **Fully automated** with one-command deployment
- **Completely reproducible** as infrastructure-as-code

---

## The Problem: Infrastructure Prototyping

<details>
<summary><strong>Why Infrastructure is Different</strong></summary>

Traditional software prototypes are straightforward:
- Write code locally
- Test in isolation
- Demo on your laptop
- Total cost: $0

Infrastructure prototypes are fundamentally different:
- Require cloud resources (GCP, AWS, Azure)
- Need integration with multiple services (DNS, load balancers, security)
- Must simulate production constraints (networking, RBAC, quotas)
- Cost money while running
- Impact team workflows if adopted

</details>

<details>
<summary><strong>The Specific Challenge</strong></summary>

I needed to answer these questions through working code:
1. How do we provision namespaces with proper security boundaries?
2. How do we enable developers to self-serve new services?
3. How do we implement CI/CD without storing secrets?
4. How do we make infrastructure changes auditable and reproducible?
5. How do we keep costs low enough to experiment freely?

**The core problem:** Most Kubernetes setups either cut security corners (prototype quality) or require extensive manual configuration (not reproducible). I needed something that was both production-ready AND easy to deploy and maintain.

</details>

---

## Requirements and Goals

<details>
<summary><strong>Must-Have Requirements</strong></summary>

1. **Single-Command Setup** - Minimize manual configuration
2. **Low Budget** - Under $50/day for prototyping, teardown-friendly
3. **Production-Grade Security** - No shortcuts that require later rework
4. **Scalable** - Support multiple teams and services
5. **Version-Controlled** - All configuration in Git
6. **Self-Service** - Developers can onboard without infrastructure team

</details>

<details>
<summary><strong>Non-Goals (For Now)</strong></summary>

- Multi-cloud support
- Multi-region deployment
- Managed database services (Cloud SQL, etc.)
- Service mesh (Istio/Envoy)
- Comprehensive monitoring/observability

These are future enhancements, not MVP blockers.

</details>

---

## Architecture Overview

<!-- ARCHITECTURE DIAGRAM: High-level system architecture showing all major components -->

<details>
<summary><strong>Core Components</strong></summary>

**Infrastructure Layer:**
- **GKE Cluster** - Kubernetes control plane and node pools
- **VPC Network** - Private networking with secondary ranges for pods/services
- **Static IP Address** - Reserved for load balancer
- **Artifact Registry** - Container image storage

**Network Layer:**
- **Cloudflare DNS** - Domain management
- **Cloudflare Proxy** - DDoS protection and SSL termination
- **GCP Load Balancer** - Managed via Gateway API
- **Gateway API** - Kubernetes-native ingress routing

**Security Layer:**
- **Workload Identity Federation** - Keyless authentication for GitHub Actions
- **Network Policies** - Namespace isolation
- **Resource Quotas** - Prevent resource exhaustion
- **RBAC** - Role-based access control

**Automation Layer:**
- **Terraform** - Infrastructure provisioning
- **GitHub Actions** - CI/CD pipelines
- **Shell Scripts** - Operational tooling (init, auth, monitor, test)

</details>

<details>
<summary><strong>Design Principles</strong></summary>

1. **Everything as Code** - No manual ClickOps
2. **Zero Hardcoded Values** - Configuration generated from Terraform outputs
3. **Principle of Least Privilege** - Minimal permissions everywhere
4. **Defense in Depth** - Multiple security layers
5. **Developer Self-Service** - Infrastructure team as platform enablers

</details>

---

## Implementation Deep Dive

<details>
<summary><strong>Phase 1: Automated Setup (`scripts/init.sh`)</strong></summary>

The initialization script is the entry point for the entire system. It handles all prerequisite setup in an interactive, user-friendly way.

#### What It Does

**1. GCP Authentication**
```bash
gcloud auth login
gcloud config set project <project-id>
gcloud auth application-default login
```

**2. Project Management**
- Detects existing project or prompts to create new
- Handles project state validation (ACTIVE, DELETE_REQUESTED, etc.)
- Sets default project and quota project

**3. Billing Account Linking**
- Lists available billing accounts
- Interactive selection
- Required validation (can't proceed without billing)

**4. Cloudflare Token Storage**
- Enables Secret Manager API
- Checks for existing token
- Securely stores in GCP Secret Manager (no environment variables)
- Supports token updates

**5. Terraform Backend Setup**
```bash
# Creates GCS bucket with:
# - Versioning enabled
# - Uniform bucket-level access
# - Public access prevention
# - User permissions
```

**6. Variables Generation**
Generates `terraform.tfvars` with:
- GCP project ID and region
- GKE cluster name
- Artifact Registry name
- **GitHub owner** (inferred from git remote!)
- **GitHub repo name** (inferred from git remote!)
- Domain name and Cloudflare settings

**7. GitHub Token Scope Validation**
- Checks for `workflow` scope (required for .github/workflows/ files)
- Checks for `delete_repo` scope (optional, for terraform destroy)
- Offers to add missing scopes

**8. Terraform Initialization**
```bash
terraform init --reconfigure
terraform plan -out=tfplan
```

#### Key Features

- **Interactive with Smart Defaults** - Infers settings from environment
- **Validation at Each Step** - Prevents proceeding with invalid config
- **Command Logging** - Saves all commands to `init.log` for review
- **Idempotent** - Safe to re-run, detects existing resources
- **Educational** - Explains what each step does

</details>

<details>
<summary><strong>Phase 2: Two-Phase Terraform Deployment</strong></summary>

Due to Kubernetes provider limitations, we split deployment into two phases.

#### Why Two Phases?

The Terraform Kubernetes provider needs:
1. A running cluster to connect to
2. Valid credentials
3. Gateway API CRDs installed

But we also want to manage Kubernetes resources (namespaces, HTTPRoutes, etc.) in the same Terraform configuration. This creates a chicken-and-egg problem.

**Solution: Targeted Apply**

**Phase 1: Foundation**
```bash
terraform apply -target=google_container_node_pool.primary_nodes
```

This creates:
- VPC network and subnets
- GKE cluster and node pool
- Static IP address
- Artifact Registry
- Workload Identity pool and provider
- Service accounts
- GitHub template repository

**Phase 2: Kubernetes Resources**
```bash
terraform apply
```

This creates:
- Namespaces with RBAC
- Gateway and HTTPRoutes
- Network policies and quotas
- Service repositories
- Cloudflare DNS records (requires Gateway IP)

</details>

<details>
<summary><strong>Phase 3: The Namespace Module</strong></summary>

The `namespace` module is the heart of the system. It provisions everything needed for a service to run.

<!-- ARCHITECTURE DIAGRAM: Namespace module component diagram showing all resources it creates -->

#### GCP Resources

**Service Account Creation**
```hcl
resource "google_service_account" "deployment" {
  account_id   = "deploy-${var.namespace_name}"
  display_name = "Deployment SA for ${var.namespace_name}"
}
```

**Minimal IAM Permissions**
- `roles/container.clusterViewer` - Get cluster credentials
- `roles/artifactregistry.reader` - Pull images
- `roles/artifactregistry.writer` - Push images (for CI/CD)

**Workload Identity Federation Binding**
```hcl
resource "google_service_account_iam_member" "github_wif" {
  for_each = toset(var.wif_repos)
  
  service_account_id = google_service_account.deployment.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${var.wif_provider}/attribute.repository/${each.value}"
}
```

This allows GitHub Actions from specified repositories to authenticate as the GCP service account without any keys.

#### Kubernetes Resources

**Namespace with Labels**
```hcl
resource "kubernetes_namespace" "main" {
  metadata {
    name = var.namespace_name
    labels = {
      "managed-by" = "terraform"
      "name"       = var.namespace_name
    }
  }
}
```

**RBAC Configuration**
- Administrator RoleBindings (full namespace access)
- Viewer RoleBindings (read-only access)
- Service account RoleBinding (for deployments)

**Resource Quotas**
```yaml
hard:
  requests.cpu: "10"
  requests.memory: "20Gi"
  limits.cpu: "20"
  limits.memory: "40Gi"
  pods: "20"
  services: "10"
  persistentvolumeclaims: "5"
```

**Limit Ranges**
```yaml
Container:
  default:
    cpu: "500m"
    memory: "512Mi"
  default_request:
    cpu: "100m"
    memory: "128Mi"
  max:
    cpu: "2"
    memory: "4Gi"
```

**Network Policies**

1. Default Deny All Ingress
```hcl
resource "kubernetes_network_policy" "default_deny_ingress" {
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}
```

2. Allow Same Namespace
```hcl
resource "kubernetes_network_policy" "allow_same_namespace" {
  spec {
    pod_selector {}
    ingress {
      from {
        pod_selector {}
      }
    }
  }
}
```

3. Allow from Specific Namespaces (Optional)
```hcl
# Configured via allow_ingress_from_namespaces variable
```

**Gateway API Resources**

HTTPRoute:
```hcl
resource "kubernetes_manifest" "httproute" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    spec = {
      parentRefs = [{
        name      = "infra-seed-main-gateway"
        namespace = "default"
      }]
      hostnames = [var.domain_name]
      rules = [{
        matches = [{
          path = {
            type  = "PathPrefix"
            value = var.routing.path_prefix
          }
        }]
        filters = [{
          type = "URLRewrite"
          urlRewrite = {
            path = {
              type               = "ReplacePrefixMatch"
              replacePrefixMatch = "/"
            }
          }
        }]
        backendRefs = [{
          name = var.routing.service_name
          port = var.routing.service_port
        }]
      }]
    }
  }
}
```

ReferenceGrant (required for cross-namespace Gateway access):
```hcl
resource "kubernetes_manifest" "reference_grant" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "ReferenceGrant"
    spec = {
      from = [{
        group     = "gateway.networking.k8s.io"
        kind      = "HTTPRoute"
        namespace = var.namespace_name
      }]
      to = [{
        group = "gateway.networking.k8s.io"
        kind  = "Gateway"
        name  = "infra-seed-main-gateway"
      }]
    }
  }
}
```

GCPBackendPolicy:
```hcl
resource "kubernetes_manifest" "backend_policy" {
  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "GCPBackendPolicy"
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
        kind  = "Service"
        name  = var.routing.service_name
      }
    }
  }
}
```

#### GitHub Resources

**Repository Creation**
```hcl
resource "github_repository" "service" {
  name        = var.namespace_name
  description = "Microservice: ${var.namespace_name}"
  visibility  = "private"
  
  template {
    owner      = var.github_owner
    repository = "infra-seed-service-template"
  }
}
```

**Auto-Generated Configuration**
```hcl
resource "github_repository_file" "github_config" {
  repository = github_repository.service.name
  file       = "github.yaml"
  
  content = yamlencode({
    gcp = {
      project_id      = var.project_id
      region          = var.region
      cluster_name    = var.gke_cluster_name
      service_account = module.namespace.gcp_service_account_email
    }
    registry = {
      url        = "${var.region}-docker.pkg.dev/${var.project_id}/${var.registry_name}"
      image_name = var.namespace_name
    }
    workload_identity = {
      provider = var.wif_provider
    }
    kubernetes = {
      namespace       = var.namespace_name
      deployment_name = "${var.namespace_name}-deployment"
      service_name    = "${var.namespace_name}-service"
    }
  })
}
```

**Key Point:** Zero hardcoded values! Everything comes from Terraform outputs.

</details>

---

## Automation and Developer Experience

<details>
<summary><strong>GitHub Repository Automation</strong></summary>

<!-- ARCHITECTURE DIAGRAM: Developer workflow from namespace creation to deployed service -->

#### Template Repository System

The system uses GitHub's template repository feature:

**Template Repository: `infra-seed-service-template`**
```
infra-seed-service-template/
├── .github/workflows/
│   └── deploy.yml          # CI/CD workflow
├── src/
│   └── app.py              # FastAPI application
├── Dockerfile              # Multi-stage build
├── deployment.yaml         # K8s deployment
├── service.yaml            # K8s service
├── requirements.txt        # Python dependencies
└── README.md               # Documentation
```

**Service Template (src/app.py):**
```python
from fastapi import FastAPI
import os

app = FastAPI(title="SERVICE_NAME")

@app.get("/")
async def root():
    return {
        "service": "SERVICE_NAME",
        "status": "running",
        "environment": os.getenv("ENVIRONMENT", "production")
    }

@app.get("/health")
async def health():
    return {"status": "healthy"}
```

**Deployment Workflow (.github/workflows/deploy.yml):**
```yaml
name: Deploy

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  id-token: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Load Configuration
        run: |
          # Reads github.yaml for all config
          yq eval '.gcp.project_id' github.yaml
          
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ steps.config.outputs.WIF_PROVIDER }}
          service_account: ${{ steps.config.outputs.GCP_SERVICE_ACCOUNT }}
          
      - name: Build and Push Image
        run: |
          IMAGE_TAG="${REGISTRY_URL}/${IMAGE_NAME}:${GITHUB_SHA}"
          docker build -t $IMAGE_TAG .
          docker push $IMAGE_TAG
          
      - name: Deploy to GKE
        run: |
          kubectl apply -f deployment.yaml
          kubectl apply -f service.yaml
          kubectl rollout status deployment/...
```

</details>

<details>
<summary><strong>Developer Workflow</strong></summary>

**1. Add New Service**

Edit `terraform/namespaces.tf`:
```hcl
locals {
  namespaces = {
    "payment-service" = {
      administrators = []
      viewers        = []
      wif_repos      = []  # Auto-populated
      routing = {
        enabled        = true
        path_prefix    = "/payments"
        service_name   = "payment-service-service"
        service_port   = 80
        url_rewrite    = true
        rewrite_target = "/"
      }
    }
  }
}
```

**2. Apply Terraform**
```bash
terraform apply
```

Result: 
- GitHub repository created
- Namespace provisioned
- RBAC configured
- HTTPRoute created
- All CI/CD configured

**3. Clone and Develop**
```bash
git clone git@github.com:owner/payment-service.git
cd payment-service

# Implement service
cat > src/app.py << 'EOF'
from fastapi import FastAPI

app = FastAPI()

@app.post("/charge")
async def charge_card(amount: float):
    # Implementation
    return {"status": "charged", "amount": amount}
EOF

# Deploy
git add .
git commit -m "Implement payment service"
git push origin main
```

**4. Automatic Deployment**
- GitHub Actions triggers on push
- Authenticates with Workload Identity (no secrets!)
- Builds and pushes image to Artifact Registry
- Deploys to GKE namespace
- Waits for rollout to complete

**5. Access Service**
```bash
curl https://yourdomain.com/payments/charge -d '{"amount": 10.00}'
```

</details>

<details>
<summary><strong>Configuration Management</strong></summary>

All service configuration is in `github.yaml`:

```yaml
gcp:
  project_id: "my-project"
  region: "us-central1"
  cluster_name: "infra-seed-cluster"
  service_account: "deploy-payment-service@my-project.iam.gserviceaccount.com"

registry:
  url: "us-central1-docker.pkg.dev/my-project/infra-seed-registry"
  image_name: "payment-service"

workload_identity:
  provider: "projects/123456/locations/global/workloadIdentityPools/github-actions-pool-abc123/providers/github-actions-provider"

kubernetes:
  namespace: "payment-service"
  deployment_name: "payment-service-deployment"
  service_name: "payment-service-service"

app:
  port: 80
  replicas: 2

build:
  context: "."
  dockerfile: "Dockerfile"
```

**Why this approach?**
- Single source of truth
- No environment variables
- Easy to audit and version
- Type-safe (validated by workflow)
- Works locally and in CI/CD

</details>

---

## Security Implementation

<details>
<summary><strong>Workload Identity Federation</strong></summary>

Traditional approach: Store GCP service account key in GitHub Secrets
- Keys can be stolen
- Keys need rotation
- Keys have broad permissions
- Key management is complex

**Our approach: Workload Identity Federation**

<!-- ARCHITECTURE DIAGRAM: WIF authentication flow from GitHub Actions to GCP -->

```
GitHub Actions Workflow
    ↓
OIDC Token (JWT) with repository claim
    ↓
Workload Identity Pool validates token
    ↓
Workload Identity Provider checks attribute condition
    ↓
Maps to GCP Service Account
    ↓
Returns short-lived GCP credentials
    ↓
Access GCP resources
```

**Configuration:**
```hcl
# Pool
resource "google_iam_workload_identity_pool" "github_actions" {
  workload_identity_pool_id = "github-actions-pool"
}

# Provider
resource "google_iam_workload_identity_pool_provider" "github_actions" {
  workload_identity_pool_id = google_iam_workload_identity_pool.github_actions.id
  
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }
  
  attribute_condition = "assertion.repository.startsWith('owner/')"
  
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Binding
resource "google_service_account_iam_member" "github_wif" {
  service_account_id = google_service_account.deployment.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${pool.name}/attribute.repository/owner/repo"
}
```

**Benefits:**
- ✅ No keys to manage
- ✅ Short-lived credentials (1 hour)
- ✅ Repository-specific (only specific repos can authenticate)
- ✅ Automatic rotation
- ✅ Audit trail via Cloud Logging

</details>

<details>
<summary><strong>Network Policies</strong></summary>

Kubernetes Network Policies provide pod-level firewall rules.

**Default Deny:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

**Allow Same Namespace:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
spec:
  podSelector: {}
  ingress:
  - from:
    - podSelector: {}
```

**Allow Specific Namespaces:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-other-namespaces
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: payment-service
    - namespaceSelector:
        matchLabels:
          name: auth-service
```

**Result:** Services can only communicate explicitly, preventing lateral movement.

</details>

<details>
<summary><strong>Resource Quotas</strong></summary>

Prevent resource exhaustion attacks and noisy neighbors:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-quota
spec:
  hard:
    requests.cpu: "10"
    requests.memory: "20Gi"
    limits.cpu: "20"
    limits.memory: "40Gi"
    pods: "20"
    services: "10"
    persistentvolumeclaims: "5"
```

</details>

<details>
<summary><strong>Limit Ranges</strong></summary>

Provide defaults and maximums for resource requests:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: namespace-limits
spec:
  limits:
  - type: Container
    default:
      cpu: "500m"
      memory: "512Mi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    max:
      cpu: "2"
      memory: "4Gi"
  - type: Pod
    max:
      cpu: "4"
      memory: "8Gi"
```

</details>

<details>
<summary><strong>RBAC</strong></summary>

**ClusterRoles:**
- `namespace-admin-clusterrole` - Full namespace management
- `deployment-admin-clusterrole` - Deployment operations
- `namespace-viewer-clusterrole` - Read-only access

**RoleBindings:**
```hcl
resource "kubernetes_role_binding" "admins" {
  for_each = { for idx, admin in var.administrators : idx => admin }
  
  metadata {
    name      = "admin-${each.value.email}"
    namespace = kubernetes_namespace.main.name
  }
  
  role_ref {
    kind = "ClusterRole"
    name = "namespace-admin-clusterrole"
  }
  
  subject {
    kind = "User"
    name = each.value.email
  }
}
```

**GCP IAM Integration:**
```hcl
resource "google_project_iam_member" "user_cluster_access" {
  for_each = toset([for admin in var.administrators : admin.email])
  
  project = var.project_id
  role    = "roles/container.clusterViewer"
  member  = "user:${each.value}"
}
```

Users need both Kubernetes RBAC AND GCP IAM to access namespaces.

</details>

---

## Networking and Traffic Flow

<details>
<summary><strong>Traffic Path</strong></summary>

<!-- ARCHITECTURE DIAGRAM: Detailed traffic flow with all network components -->

```
1. User makes request to https://yourdomain.com/payments
   ↓
2. DNS Resolution (Cloudflare)
   - Resolves to Cloudflare proxy IP (not origin)
   ↓
3. Cloudflare Proxy
   - DDoS protection
   - WAF rules
   - SSL termination (client → Cloudflare)
   - SSL re-encryption (Cloudflare → origin)
   ↓
4. GCP Static IP (34.149.x.x)
   - Reserved static IP
   - Assigned to Gateway
   ↓
5. GCP HTTPS Load Balancer (managed by Gateway API)
   - SSL termination using Cloudflare Origin CA cert
   - Routes to backend service based on HTTPRoute rules
   ↓
6. Gateway API (infra-seed-main-gateway)
   - Central routing point in default namespace
   - Delegates to HTTPRoutes in namespaces
   ↓
7. HTTPRoute (in payment-service namespace)
   - Matches path prefix "/payments"
   - Rewrites to "/" for backend
   - Routes to payment-service-service
   ↓
8. Kubernetes Service (payment-service-service)
   - Type: ClusterIP
   - Selector: app=payment-service
   - Network Endpoint Group (NEG) enabled
   ↓
9. Network Endpoint Group (NEG)
   - Direct pod IP registration
   - Health checks
   - Load balancing
   ↓
10. Pod (payment-service-deployment)
    - Container listening on port 80
    - Network Policy allows ingress from load balancer
    ↓
11. Response flows back up the stack
```

</details>

<details>
<summary><strong>Gateway API Architecture</strong></summary>

**Why Gateway API over Ingress?**

Traditional Ingress:
- Single ingress resource per namespace
- Limited routing capabilities
- Poor multi-team support
- Extension via annotations (non-standard)

Gateway API:
- Separation of concerns (Gateway vs Routes)
- Cross-namespace routing
- Rich routing features (header matching, URL rewriting, weighted traffic)
- Standardized extension points
- Officially graduated (v1.0)

**Our Implementation:**

**Gateway (default namespace):**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: infra-seed-main-gateway
  namespace: default
spec:
  gatewayClassName: gke-l7-global-external-managed
  addresses:
  - type: NamedAddress
    value: infra-seed-ingress-ip
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: yourdomain.com
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: hundred-sh-tls
    allowedRoutes:
      namespaces:
        from: All
```

**HTTPRoute (payment-service namespace):**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: payment-service-route
  namespace: payment-service
spec:
  parentRefs:
  - name: infra-seed-main-gateway
    namespace: default
  hostnames:
  - yourdomain.com
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /payments
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /
    backendRefs:
    - name: payment-service-service
      port: 80
```

**ReferenceGrant (default namespace):**
```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-payment-service-gateway-access
  namespace: default
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: payment-service
  to:
  - group: gateway.networking.k8s.io
    kind: Gateway
    name: infra-seed-main-gateway
```

</details>

<details>
<summary><strong>SSL/TLS Configuration</strong></summary>

**Cloudflare Origin CA Certificate:**

Instead of Google-managed certificates, we use Cloudflare Origin CA:

```hcl
# Generate private key
resource "tls_private_key" "origin_cert" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create CSR
resource "tls_cert_request" "origin_cert" {
  private_key_pem = tls_private_key.origin_cert.private_key_pem
  subject {
    common_name  = var.domain_name
    organization = "PyKube"
  }
}

# Get Cloudflare Origin Certificate
resource "cloudflare_origin_ca_certificate" "main" {
  csr                = tls_cert_request.origin_cert.cert_request_pem
  hostnames          = [var.domain_name, "*.${var.domain_name}"]
  request_type       = "origin-rsa"
  requested_validity = 5475  # 15 years
}

# Store in Kubernetes Secret
resource "kubernetes_secret" "tls_certificate" {
  metadata {
    name      = "hundred-sh-tls"
    namespace = "default"
  }
  type = "kubernetes.io/tls"
  data = {
    "tls.crt" = cloudflare_origin_ca_certificate.main.certificate
    "tls.key" = tls_private_key.origin_cert.private_key_pem
  }
}
```

**SSL/TLS Flow:**
1. Client → Cloudflare: TLS 1.3 (Cloudflare's cert)
2. Cloudflare → GCP LB: TLS 1.2+ (Origin CA cert)
3. GCP LB → Pod: Plain HTTP (within VPC)

**Cloudflare SSL Mode: Full (Strict)**
- Validates origin certificate
- End-to-end encryption
- No mixed-mode security

</details>

<details>
<summary><strong>Network Endpoint Groups (NEGs)</strong></summary>

NEGs provide direct pod connectivity:

**Traditional Service LoadBalancer:**
```
LB → NodePort → iptables → kube-proxy → Pod
```

**With NEG:**
```
LB → Pod IP directly
```

**Benefits:**
- Lower latency (fewer hops)
- Better load balancing (pod-aware)
- Health checks at pod level
- WebSocket support

**Enabled automatically** by Gateway API on GKE.

</details>

---

## Operational Tooling

<details>
<summary><strong>Authentication Script (`scripts/auth.sh`)</strong></summary>

Quick re-authentication for new terminal sessions:

```bash
#!/bin/bash

# Get cluster credentials
gcloud container clusters get-credentials infra-seed-cluster \
  --region=us-central1

# Export Cloudflare token
export CLOUDFLARE_API_TOKEN=$(gcloud secrets versions access latest \
  --secret="cloudflare-api-token")

# Export GitHub token
export GITHUB_TOKEN=$(gh auth token)
```

Usage:
```bash
source ./scripts/auth.sh
cd terraform
terraform apply
```

</details>

<details>
<summary><strong>Monitoring Script (`scripts/monitor.sh`)</strong></summary>

Comprehensive status checking for Gateway propagation:

**What It Checks:**

1. **Gateway Status**
   - Programmed condition (ready to accept traffic)
   - IP address assignment
   - Number of attached routes

2. **HTTPRoute Status**
   - Accepted condition (Gateway accepts the route)
   - ResolvedRefs condition (backend references valid)
   - Per-namespace reporting

3. **Pod Status**
   - Running pod count per namespace
   - Ready vs total pods

4. **Network Endpoint Group Status**
   - NEG creation per service
   - NEG naming from service annotations

5. **Backend Service Health**
   - GCP backend service health checks
   - Healthy vs total endpoints
   - Per-backend reporting

6. **Recent Events**
   - Gateway-related Kubernetes events
   - Error messages and warnings

**Output Example:**
```
=== Gateway Status ===
✅ Gateway is Programmed
✅ Gateway IP: 34.149.233.235
📊 Attached Routes: 3

=== HTTPRoute Status ===
✅ service-one: Route configured correctly
✅ service-two: Route configured correctly
✅ service-three: Route configured correctly

=== Pod Status ===
✅ service-one: All 2/2 pods running
✅ service-two: All 2/2 pods running
✅ service-three: All 2/2 pods running
```

**Usage:**
```bash
./scripts/monitor.sh

# Or watch mode
watch -n 10 ./scripts/monitor.sh
```

</details>

<details>
<summary><strong>Testing Script (`scripts/test.sh`)</strong></summary>

End-to-end verification of all endpoints:

**Test Categories:**

1. **Prerequisites Check**
   - kubectl, curl, dig availability
   - kubectl cluster connectivity
   - Gateway resource existence
   - Gateway IP assignment

2. **DNS Resolution**
   - Domain resolves correctly
   - Compares with Gateway IP
   - Explains Cloudflare proxy behavior

3. **GCP Load Balancer Direct**
   - Tests each service via direct IP
   - Uses Host header to bypass DNS
   - Verifies health endpoints
   - Tests API endpoints

4. **Cloudflare Domain**
   - Tests through Cloudflare proxy
   - Verifies SSL/TLS
   - Tests all service paths
   - Validates response content

**Output Example:**
```
=== Testing GCP Load Balancer Direct IP ===
✅ curl -k -H 'Host: yourdomain.com' 'https://34.149.233.235/one' 
   → HTTP 200 | {"service":"service-one","status":"running"}
✅ curl -k -H 'Host: yourdomain.com' 'https://34.149.233.235/one/health' 
   → HTTP 200 | {"status":"healthy"}

=== Testing Cloudflare Domain Endpoints ===
✅ curl 'https://yourdomain.com/one' 
   → HTTP 200 | {"service":"service-one","status":"running"}
✅ curl 'https://yourdomain.com/one/health' 
   → HTTP 200 | {"status":"healthy"}

🎉 All tests passed!
```

**Usage:**
```bash
./scripts/test.sh

# Test only GCP load balancer
./scripts/test.sh --gcp-only

# Test only Cloudflare
./scripts/test.sh --cf-only

# Custom timeout
./scripts/test.sh --timeout 15
```

</details>

---

## Cost Analysis

<details>
<summary><strong>Monthly Breakdown (~$128/month)</strong></summary>

**GKE Control Plane: ~$75/month**
- Regional cluster (high availability)
- 99.95% SLA
- Automatic upgrades and patching
- Could reduce to ~$0 with Autopilot mode (but less control)

**Compute (e2-medium nodes): ~$30/month**
- 1 node × e2-medium (2 vCPU, 4GB RAM)
- $0.04/hour × 730 hours = ~$30
- Could scale down to e2-small ($15/month) for dev

**Load Balancer: ~$18/month**
- Forwarding rule: $0.025/hour × 730 = ~$18
- Ingress data: First 1GB free, $0.008/GB after

**Storage & Misc: ~$5/month**
- GCS bucket for Terraform state: <$1
- Artifact Registry: First 0.5GB free
- Secret Manager: First 6 operations free
- Cloud Logging: First 50GB free

**Total: ~$128/month or ~$4.25/day**

</details>

<details>
<summary><strong>Cost Optimization Strategies</strong></summary>

**For Development/Testing:**
1. **Use Preemptible Nodes** - 60-90% cheaper
   ```hcl
   node_config {
     preemptible = true
   }
   ```

2. **Autopilot Mode** - Pay only for pod resources
   ```hcl
   enable_autopilot = true
   ```

3. **Tear Down When Idle**
   ```bash
   terraform destroy
   # Costs: $0/month when destroyed
   ```

**For Production:**
1. **Regional instead of Zonal** (already using)
2. **Committed Use Discounts** - Up to 57% off compute
3. **Cluster Autoscaling** - Scale to zero during off-hours
4. **Right-size node pools** - Match workload requirements

</details>

<details>
<summary><strong>Cost Comparison</strong></summary>

**Managed Kubernetes Alternatives:**
- **EKS (AWS)**: ~$145/month (control plane + nodes)
- **AKS (Azure)**: ~$120/month (free control plane + nodes)
- **DigitalOcean**: ~$40/month (but less features)
- **Managed Services** (Cloud Run, App Engine): $0-50/month (but less control)

**Our solution offers the best balance** of features, control, and cost for a production-ready setup.

</details>

---

## Technical Decisions and Tradeoffs

<details>
<summary><strong>Gateway API vs Ingress</strong></summary>

**Decision: Gateway API**

**Reasoning:**
- **Cross-namespace routing** - HTTPRoutes in namespaces reference Gateway in default namespace
- **Better abstractions** - Clear separation between infrastructure (Gateway) and application (Routes)
- **Richer features** - URL rewriting, header matching, weighted traffic splits
- **Future-proof** - Officially graduated (v1.0), better community support

**Tradeoffs:**
- More complex initial setup
- Newer (less Stack Overflow answers)
- Requires GKE 1.24+

**Alternative Considered:** Traditional Ingress
- Simpler conceptually
- More documentation available
- But: Single ingress per namespace, limited routing, less flexible

</details>

<details>
<summary><strong>Workload Identity Federation vs Service Account Keys</strong></summary>

**Decision: Workload Identity Federation**

**Reasoning:**
- **Security** - No keys to steal or leak
- **Compliance** - Meets zero-trust requirements
- **Simplicity** - No key rotation needed
- **Auditability** - Every request logged with repository info

**Tradeoffs:**
- More complex setup (but worth it)
- Requires GCP-specific configuration
- Limited to supported platforms (GitHub Actions, GitLab CI, etc.)

**Alternative Considered:** Store keys in GitHub Secrets
- Simpler initial setup
- But: Keys can be exfiltrated, need rotation, broad permissions

</details>

<details>
<summary><strong>Cloudflare Origin CA vs Google-Managed Certificates</strong></summary>

**Decision: Cloudflare Origin CA**

**Reasoning:**
- **End-to-end encryption** - Cloudflare → GCP encrypted with trusted cert
- **Faster deployment** - No DNS validation needed
- **Better control** - Certificate in Terraform
- **Long validity** - 15 years vs 90 days

**Tradeoffs:**
- Requires Cloudflare (vendor lock-in)
- Manual renewal after 15 years
- Can't use with other CDNs

**Alternative Considered:** Google-Managed SSL
- Automatic renewal
- But: Requires DNS validation, longer setup time, less control

</details>

<details>
<summary><strong>FastAPI vs Flask</strong></summary>

**Decision: FastAPI**

**Reasoning:**
- **Modern** - Async/await support
- **Performance** - Faster than Flask
- **Documentation** - Auto-generated OpenAPI docs
- **Type Safety** - Pydantic models for validation

**Tradeoffs:**
- Newer framework (smaller ecosystem)
- Steeper learning curve for beginners

**Alternative Considered:** Flask
- More mature
- Larger ecosystem
- But: Synchronous only, slower, manual docs

</details>

<details>
<summary><strong>Two-Phase vs Single-Phase Deployment</strong></summary>

**Decision: Two-Phase (targeted apply)**

**Reasoning:**
- **Kubernetes provider limitation** - Needs cluster to exist
- **Better error handling** - Fail fast on infrastructure issues
- **Clearer separation** - Infrastructure vs applications

**Tradeoffs:**
- Extra command to run
- Not standard Terraform pattern
- Could confuse newcomers

**Alternative Considered:** Separate Terraform configurations
- Cleaner separation
- But: More complex, state management issues, harder to maintain

</details>

<details>
<summary><strong>Single Repository vs Multi-Repository</strong></summary>

**Decision: Single monorepo for infrastructure**

**Reasoning:**
- **Atomic changes** - Update infrastructure and configs together
- **Easier review** - All changes in one PR
- **Simplified CI/CD** - One pipeline
- **Better documentation** - Everything in one place

**Tradeoffs:**
- Larger repository
- Everyone sees everything
- Harder to limit access

**Alternative Considered:** Separate repos for each component
- Better access control
- But: Coordination overhead, versioning complexity

</details>

---

## Lessons Learned

<details>
<summary><strong>1. Invest in Automation Upfront</strong></summary>

**The init.sh script took a full day to build**, but it's saved hours on every deployment since. Key features that proved valuable:

- **Smart defaults** - Inferring GitHub owner/repo from git remote
- **Validation at each step** - Prevents proceeding with bad config
- **Interactive prompts** - Makes it accessible to non-experts
- **Command logging** - Creates audit trail and helps debugging

**Lesson:** Time spent on automation pays dividends immediately.

</details>

<details>
<summary><strong>2. Documentation is Infrastructure</strong></summary>

Initially, I thought code was self-documenting. Wrong.

**What worked:**
- README with clear setup instructions
- GITHUB_AUTOMATION.md for the repository system
- Inline comments explaining "why" not "what"
- Architecture diagrams (planned)

**Lesson:** Code tells you *how*, documentation tells you *why*.

</details>

<details>
<summary><strong>3. Two-Phase Deployment is Non-Negotiable</strong></summary>

I tried everything to avoid the two-phase deployment:
- Separate Terraform configurations (state management nightmare)
- Depends_on hacks (didn't work)
- null_resource provisioners (timing issues)

**Lesson:** Accept the Kubernetes provider limitation and work with it.

</details>

<details>
<summary><strong>4. Gateway API is Production-Ready</strong></summary>

Despite being newer, Gateway API proved more reliable than Ingress for our use case:

- **Better error messages** - Clear status conditions
- **Cross-namespace support** - Built-in, not hacked
- **Rich routing** - URL rewriting just works

**Lesson:** Don't assume older = better. Evaluate based on requirements.

</details>

<details>
<summary><strong>5. Monitor and Test Scripts are Essential</strong></summary>

The `monitor.sh` and `test.sh` scripts caught issues that would have been painful to debug manually:

- Gateway IP assignment delays
- HTTPRoute acceptance issues
- Backend health check failures
- DNS propagation problems

**Lesson:** Build observability into the platform from day one.

</details>

<details>
<summary><strong>6. Zero Hardcoded Values Prevents Configuration Drift</strong></summary>

Auto-generating `github.yaml` from Terraform outputs eliminated entire classes of bugs:

- ❌ Wrong cluster name in repo
- ❌ Mismatched service account email
- ❌ Incorrect registry URL
- ❌ Stale configuration after changes

**Lesson:** Generate configuration, don't template it.

</details>

<details>
<summary><strong>7. Security by Default is Easier Than Retrofitting</strong></summary>

Implementing security features from the start (WIF, network policies, resource quotas) was far easier than adding them later:

- No migration of existing keys
- No service disruption
- No "temporary" workarounds that become permanent

**Lesson:** Production-grade security from day one, even in prototypes.

</details>

<details>
<summary><strong>8. Cost Consciousness Enables Experimentation</strong></summary>

Keeping costs low (~$4/day) made it psychologically easy to:
- Try risky changes
- Tear down and rebuild
- Run multiple experiments
- Keep it running continuously

**Lesson:** Low cost = high confidence = more learning.

</details>

---

## Future Enhancements

<details>
<summary><strong>Short Term (Next 2 Months)</strong></summary>

**1. Automated Tests in CI/CD**
- Add test stage before deployment
- Unit tests for services
- Integration tests via test.sh

**2. GitHub Teams Integration**
- Use `github_team_repository` for access control
- Team-based RBAC
- Simpler permission management

**3. Multi-Environment Support**
- Dev, staging, production namespaces
- Environment-specific configurations
- Blue-green deployments

</details>

<details>
<summary><strong>Medium Term (3-6 Months)</strong></summary>

**4. Observability Stack**
- Prometheus for metrics
- Grafana for dashboards
- Loki for logs
- Tempo for traces

**5. Database Support**
- Cloud SQL Terraform module
- Memorystore for Redis
- Automatic backup configuration
- Connection pooling

**6. Service Mesh (Istio)**
- mTLS between services
- Traffic management (canary, A/B testing)
- Better observability
- Circuit breaking

</details>

<details>
<summary><strong>Long Term (6-12 Months)</strong></summary>

**7. Multi-Language Templates**
- Node.js/Express template
- Go/Gin template
- Rust/Actix template
- Java/Spring Boot template

**8. Advanced Security**
- OAuth2/OIDC for services
- Policy enforcement (OPA)
- Secret rotation automation
- Vulnerability scanning

**9. Multi-Region Support**
- Regional clusters
- Global load balancing
- Data replication
- Disaster recovery

**10. Cloudflare Tunnel Integration**
- Eliminate public IP address exposure
- Private-only GKE clusters
- Enhanced security through private connectivity
- Evaluate scalability for production workloads

**11. Platform Abstraction**
- CLI tool for common operations
- Self-service portal
- GitOps workflows
- Service catalog

</details>

---

## Conclusion

Building this Kubernetes infrastructure starter kit taught me that **production-ready doesn't mean complicated**. With the right abstractions and automation, a single engineer can build and maintain a platform that:

- Scales from prototype to production
- Onboards new services in minutes
- Maintains security best practices
- Costs less than $5/day
- Runs completely as code

<details>
<summary><strong>Key Takeaways</strong></summary>

1. **Automate Everything** - The init.sh script is the foundation
2. **Zero Hardcoded Values** - Generate configuration from Terraform outputs
3. **Security by Default** - Workload Identity Federation, network policies, resource quotas
4. **Gateway API** - More powerful than Ingress for multi-tenant scenarios
5. **Comprehensive Tooling** - Monitor and test scripts catch issues early
6. **Developer Self-Service** - Add namespace → get GitHub repo with CI/CD

</details>

<details>
<summary><strong>The Real Win</strong></summary>

The biggest success isn't the technology stack - it's enabling this workflow:

```bash
# Infrastructure team: Add namespace
vim terraform/namespaces.tf
terraform apply

# Developer: Implement and deploy service
git clone <new-repo>
vim src/app.py
git push
# Service is live at https://yourdomain.com/<path>
```

**That's the power of a well-designed platform.**

</details>

<details>
<summary><strong>Next Steps</strong></summary>

If you're building something similar:

1. **Start with init.sh** - Automate setup first
2. **Use Gateway API** - Don't waste time with Ingress
3. **Embrace Workload Identity** - No keys from day one
4. **Build monitoring tools** - You'll thank yourself later
5. **Document as you go** - Future you will appreciate it

</details>

<details>
<summary><strong>Resources</strong></summary>

- **Repository:** [github.com/hochoy/infra-seed](https://github.com/hochoy/infra-seed)
- **Documentation:** README.md, docs/GITHUB_AUTOMATION.md
- **Gateway API Docs:** [gateway-api.sigs.k8s.io](https://gateway-api.sigs.k8s.io)
- **Workload Identity Federation:** [cloud.google.com/iam/docs/workload-identity-federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- **GKE Gateway API:** [cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways)

</details>

---

**Development timeline:** ~40 hours over 9 days across 3 weeks
- **Sep 28** (2 commits): Initial setup, manual config docs, local dev with Podman/Minikube
- **Sep 29** (1 commit): Production deployment documentation
- **Sep 30** (1 commit): Production configuration changes
- **Oct 4** (5 commits): Planning phase - created design docs (1,537 lines), namespace updates
- **Oct 8** (18 commits): Heavy refactoring - deleted outdated docs (1,349 lines), major ingress overhaul, SSL/TLS implementation, all service deployments, CPU optimization, multiple debug iterations
- **Oct 9** (6 commits): DNS fixes, Gateway API cleanup, null resource orchestration, service improvements
- **Oct 11** (8 commits): Built test.sh script (396 lines), automated init.sh improvements, workload identity enhancements, 2-phase deployment warnings
- **Oct 12** (10 commits): Major automation day - GitHub template system (987 lines), monitoring script (239 lines), documentation consolidation (removed 2,142 lines), namespace module refactoring
- **Oct 16** (1 commit): Final documentation updates

**Deployment time:** ~15 minutes (init + 2-phase terraform apply)  
**Teardown time:** ~5 minutes (terraform destroy)  
**Services deployed:** 3 example microservices

**Built with:** Terraform, GKE, Cloudflare, GitHub Actions, and thoughtful automation.

---

*Questions? Issues? PRs welcome at [github.com/hochoy/infra-seed](https://github.com/hochoy/infra-seed)*
