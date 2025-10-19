# Infra Seed

Production-ready Kubernetes infrastructure on GKE with Terraform, automated CI/CD via GitHub Actions, and role-based access control.

## Table of Contents

- [📋 Overview](#-overview)
- [🏗️ Architecture](#️-architecture)
- [📁 Repository Structure](#-repository-structure)

- [🚀 Setup](#-setup)
- [🆘 Troubleshooting](#-troubleshooting)

- [🛠️ Developer Workflows](#️-developer-workflows)
- [🌐 Traffic Flow](#-traffic-flow)

- [💰 Cost Estimate](#-cost-estimate)
- [🔒 Security Features](#-security-features)
- [🔗 Links](#-links)
- [🔮 Future Enhancements](#-future-enhancements)

## 📋 Overview

This project provides a complete infrastructure-as-code solution for deploying applications to Google Kubernetes Engine (GKE) with:

- **Terraform-managed infrastructure** - GKE cluster, load balancer, SSL certificates, DNS
- **GitHub Actions CI/CD** - Automated namespace provisioning and application deployment
- **Role-based access control** - User access management via `namespaces.yaml`
- **Cloudflare integration** - DNS management and DDoS protection
- **Workload Identity Federation** - Keyless authentication (no service account keys)

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Request                            │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Cloudflare (DNS + DDoS)                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │     DNS      │  │  Proxy/WAF   │  │  Origin CA   │           │
│  └──────────────┘  └──────────────┘  └──────────────┘           │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Google Cloud Platform                         │
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              HTTPS Load Balancer + SSL                     │ │
│  │  ┌──────────┐  ┌──────────┐  ┌────────────┐                │ │
│  │  │ Static IP│  │ SSL Cert │  │ Health Chk │                │ │
│  │  └──────────┘  └──────────┘  └────────────┘                │ │
│  └─────────────────────┬──────────────────────────────────────┘ │
│                        │                                        │
│  ┌─────────────────────▼──────────────────────────────────────┐ │
│  │              GKE Cluster (Regional)                        │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐  │ │
│  │  │         Gateway API (GKE Gateway Controller)         │  │ │
│  │  │  ┌──────────┐  ┌──────────┐  ┌────────────┐          │  │ │
│  │  │  │ Gateway  │  │HTTPRoutes│  │ BackendPol │          │  │ │
│  │  │  └──────────┘  └──────────┘  └────────────┘          │  │ │
│  │  └───────────────────┬──────────────────────────────────┘  │ │
│  │                      │                                     │ │
│  │  ┌───────────────────▼──────────────────────────────────┐  │ │
│  │  │           Isolated Namespaces                        │  │ │
│  │  │                                                      │  │ │
│  │  │  ┌─────────────┐  ┌─────────────┐  ┌────────────┐    │  │ │
│  │  │  │ service-one │  │ service-two │  │ service-...│    │  │ │
│  │  │  │             │  │             │  │            │    │  │ │
│  │  │  │ • Pods      │  │ • Pods      │  │ • Pods     │    │  │ │
│  │  │  │ • Services  │  │ • Services  │  │ • Services │    │  │ │
│  │  │  │ • RBAC      │  │ • RBAC      │  │ • RBAC     │    │  │ │
│  │  │  │ • Quotas    │  │ • Quotas    │  │ • Quotas   │    │  │ │
│  │  │  │ • NetPol    │  │ • NetPol    │  │ • NetPol   │    │  │ │
│  │  │  └─────────────┘  └─────────────┘  └────────────┘    │  │ │
│  │  └──────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │          Supporting Infrastructure                         │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌────────────┐        │ │
│  │  │ Artifact Reg │  │  VPC Network │  │ Secret Mgr │        │ │
│  │  └──────────────┘  └──────────────┘  └────────────┘        │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              |
┌────────────────────────────────────────────────────────────────┐
│                      GitHub Actions CI/CD                      │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────┐            │
│  │  WIF Auth    │  │ Build/Push   │  │   Deploy   │            │
│  └──────────────┘  └──────────────┘  └────────────┘            │
└────────────────────────────────────────────────────────────────┘
```

### Key Components

**Cloudflare Layer**
- DNS management and resolution
- DDoS protection and Web Application Firewall (WAF)
- Origin CA certificates for end-to-end encryption
- Proxy mode hides origin IP address

**GCP Network Layer**
- Static IP address for stable external access
- HTTPS Load Balancer with automatic SSL certificate management
- Health checks for backend service availability
- Regional deployment for high availability

**GKE Cluster**
- Private nodes (no external IPs) for security
- Gateway API for modern traffic routing (replaces Ingress)
- Workload Identity for secure, keyless authentication
- Autoscaling and auto-repair capabilities

**Namespace Isolation**
- Each service runs in isolated namespace
- Per-namespace GCP service accounts with minimal permissions
- RBAC for user access control (admin/viewer roles)
- Resource quotas and limit ranges
- Network policies (default deny + allow same namespace)

**CI/CD Pipeline**
- GitHub Actions workflows auto-generated per service
- Workload Identity Federation (no service account keys)
- Automated build, push to Artifact Registry, and deploy to GKE
- Each namespace has its own GitHub repository

## 📁 Repository Structure

```
infra-seed/
├── scripts/
│   ├── init.sh          # Initial setup: GCP project, billing, Cloudflare, Terraform backend
│   ├── auth.sh          # Authenticate with GCP, Cloudflare and Github for Terraform operations
│   ├── test.sh          # Test deployed services (DNS, load balancer, endpoints)
│   └── monitor.sh       # Monitor deployment status and networking milestones
│
├── terraform/
│   ├── main.tf          # Core infrastructure: GKE cluster, VPC, Artifact Registry
│   ├── backend.tf       # Terraform backend configuration (GCS)
│   ├── variables.tf     # Input variables for all Terraform configurations
│   ├── outputs.tf       # Output values from Terraform deployment
│   ├── terraform.tfvars.example  # Example configuration file
│   │
│   ├── namespaces.tf    # 🎯 Define all namespaces and routing here
│   ├── ingress.tf       # Gateway API resources (Gateway, HTTPRoutes)
│   ├── cloudflare.tf    # DNS records and Origin CA certificates
│   ├── kubernetes-rbac.tf        # Cluster-level RBAC roles
│   ├── service-accounts.tf      # GCP service accounts
│   ├── workload-identity.tf     # Workload Identity Federation setup
│   ├── github-automation.tf     # Auto-create GitHub repos per namespace
│   │
│   ├── modules/
│   │   └── namespace/   # Reusable module for namespace creation
│   │       ├── main.tf          # Namespace resources (SA, RBAC, quotas, network policies)
│   │       ├── variables.tf     # Module input variables
│   │       ├── outputs.tf       # Module outputs
│   │       └── README.md        # Module documentation
│   │
│   └── templates/
│       ├── service/     # Template for new services
│       │   ├── src/app.py       # Sample Flask application
│       │   ├── Dockerfile       # Container build instructions
│       │   ├── deployment.yaml  # Kubernetes Deployment manifest
│       │   ├── service.yaml     # Kubernetes Service manifest
│       │   ├── requirements.txt # Python dependencies
│       │   └── README.md        # Service documentation
│       │
│       └── workflows/
│           └── deploy.yml       # GitHub Actions workflow template
│
├── README.md           # This file - project documentation
├── BLOG.md             # Blog post/article content
├── .gitignore          # Git ignore rules
└── .python-version     # Python version for local development
```

### Key Files

**`terraform/namespaces.tf`** - Central configuration for all namespaces
- Define new namespaces here
- Configure routing (path prefix, service name, port)
- Set user access (administrators, viewers)
- Automatically creates GitHub repos and WIF bindings

**`terraform/ingress.tf`** - Gateway API resources
- Main Gateway (load balancer entry point)
- HTTPRoutes for path-based routing
- Backend policies for health checks

**`scripts/init.sh`** - One-time setup
- Creates GCP project and links billing
- Stores Cloudflare API token in Secret Manager
- Initializes Terraform backend (GCS bucket)
- Generates `terraform.tfvars` with defaults

**`terraform/modules/namespace/`** - Namespace isolation
- Creates isolated namespace with RBAC, quotas, network policies
- Sets up GCP service account with Workload Identity
- Grants user access based on administrator/viewer roles

## 🚀 Setup

### Prerequisites

Vendor accounts:
- Google Billing Account
- Cloudflare Account
- Cloudflare Domain
- GitHub Account

Tools:
- `gcloud` CLI
- `terraform` CLI
- `kubectl` CLI
- `gh` CLI


### Initialization

The `init.sh` script performs complete infrastructure setup and deployment in a single run:

```bash
# Clone the repository
git clone git@github.com:hochoy/infra-seed.git
cd infra-seed
./scripts/init.sh
```

**What init.sh does for you:**
- ✅ Google Cloud authentication
- ✅ Project creation and configuration
- ✅ Billing account linking
- ✅ Cloudflare API token storage (Secret Manager)
- ✅ Terraform backend setup (GCS bucket)
- ✅ terraform.tfvars generation with smart defaults
- ✅ Terraform initialization (`terraform init`)
- ✅ Infrastructure deployment (GKE cluster, Kubernetes resources, Cloudflare DNS)
- ✅ Logs all commands to init.log for review

The script uses a 2-step Terraform deployment strategy to avoid Kubernetes provider issues:
1. First deploys the GKE cluster and node pool
2. Then deploys all remaining infrastructure (Kubernetes resources, DNS, etc.)

**For subsequent infrastructure modifications:**

After the initial deployment, you can make changes to your infrastructure by editing the Terraform files and applying them:

```bash
# Authenticate (if starting a new shell session)
sh ./scripts/auth.sh

# Make your changes to terraform/*.tf files
# Then apply them:
cd terraform/
terraform plan    # Review changes
terraform apply   # Apply changes
```

### Test the infrastructure

After deploying your infrastructure, it's important to verify that all components are properly configured and operational.

#### Step 1: Monitor deployment status

First, run the monitoring script to check the Gateway and HTTPRoute deployment status:

```bash
sh ./scripts/monitor.sh
```

This script checks:
- **Gateway Status**: Verifies the Gateway is programmed and has an IP address
- **HTTPRoute Configuration**: Confirms all routes are accepted and configured
- **Pod Health**: Shows running pods across all service namespaces
- **Network Endpoint Groups (NEGs)**: Confirms NEGs are created for each service
- **Backend Health**: Displays health status of backend services

#### Step 2: Test service accessibility

Once `monitor.sh` shows all components are healthy (Gateway programmed, routes accepted, backends healthy), run the testing script:

```bash
sh ./scripts/test.sh
```

This script tests:
- **DNS Resolution**: Verifies domain resolves correctly
- **GCP Load Balancer**: Direct IP access with proper Host headers
- **Cloudflare Domain**: HTTPS endpoints through Cloudflare proxy
- **Health Checks**: Service health endpoints

Example output when services are fully operational:
```
🚀 infra-seed Service Testing Script
[INFO] === Checking Prerequisites ===
✅ kubectl is installed
✅ curl is installed
✅ jq is installed (optional)
✅ dig is installed
✅ kubectl can connect to cluster
✅ Gateway infra-seed-main-gateway exists
✅ Gateway has IP address assigned: 34.149.233.235
[INFO] === Testing GCP Load Balancer Direct IP ===
✅ curl -H 'Host: hundred.sh' 'http://34.149.233.235/one' → HTTP 200 | {"service":"SERVICE_NAME","status":"running"...
```

**Important:** During initial deployment, you may see "fault filter abort" errors when accessing your services. This is expected behavior while the Gateway is initializing and configuring HTTPRoutes. According to [Google's Gateway API documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-multi-cluster-gateways), this message appears before HTTPRoutes are fully configured and health checks pass.


There is often a delay in DNS propagation or load balancer setup, so re-running the script after a few minutes is recommended.

## 🆘 Troubleshooting

### GCP Load Balancer Shows "fault filter abort"
**Symptom**: When accessing the load balancer IP directly after initial deployment, you see "fault filter abort" message.  
**Cause**: This is expected behavior during Gateway initialization before HTTPRoutes are fully configured ([see GCP docs](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-multi-cluster-gateways)).  
**Solution**: Use `./scripts/test.sh` to verify deployment milestones. The message will disappear once routes are properly configured and health checks pass.

### Kubernetes REST Client Error During Terraform Plan/Apply
```
Error: Failed to construct REST client
cannot create REST client: no client config
```
**Cause**: Terraform tries to validate Kubernetes resources before the GKE cluster exists.  
**Solution**: Use targeted deployment to create infrastructure first, then Kubernetes resources:
```bash
# First: Deploy GCP infrastructure only
terraform apply -target=google_container_cluster.primary -target=google_container_node_pool.primary_nodes -auto-approve

# Second: Deploy all remaining resources
terraform apply -auto-approve
```

### SSL Certificate Not Provisioning
- Wait 10-15 minutes for initial provisioning
- Verify DNS points to correct static IP
- Check: `gcloud compute ssl-certificates describe infra-seed-ssl-cert`


## 🛠️ Developer Workflows

### Working with Services

For detailed instructions on developing, testing, and deploying services, see the **[Service README Template](./terraform/templates/service/README.md)** which is included in every generated service repository.

The service template documentation covers:
- **Local Development** - Python environment setup (pyenv/venv/devcontainers), container runtime (Docker/Podman), Minikube testing
- **Configuration** - Understanding auto-generated `github.yaml`
- **Deployment** - Automated CI/CD via GitHub Actions, monitoring, rollbacks
- **Kubernetes Operations** - Viewing pods/logs, debugging, resource monitoring
- **Troubleshooting** - Common issues and solutions
- **Architecture** - Namespace isolation, RBAC, CI/CD pipeline

### Quick Access to Production Cluster

```bash
# Authenticate with Google Cloud
gcloud auth login

# Get cluster credentials
gcloud container clusters get-credentials infra-seed-cluster \
  --region=us-central1 \
  --project=$(gcloud config get-value project)

# Set your namespace
kubectl config set-context --current --namespace=YOUR_NAMESPACE

# Verify access
kubectl get pods
```

### Add a new namespace

1. **Edit `terraform/namespaces.tf`** - Add a new entry to the `locals.namespaces` map:

```hcl
locals {
  namespaces = {
    # ... existing namespaces ...
    
    "my-new-service" = {
      administrators = [
        { email = "admin@example.com", name = "Admin User" }
      ]
      viewers = [
        { email = "viewer@example.com", name = "Viewer User" }
      ]
      wif_repos = []  # Will be auto-populated
      routing = {
        enabled        = true
        path_prefix    = "/mynewservice"
        service_name   = "my-new-service-service"
        service_port   = 80
        url_rewrite    = true
        rewrite_target = "/"
      }
    }
  }
}
```

2. **Apply Terraform changes**:

```bash
sh ./scripts/auth.sh
cd terraform/
terraform plan  # Review changes
terraform apply
```

3. **What gets created automatically**:
- ✅ Kubernetes namespace with isolation policies
- ✅ GCP service account with Workload Identity bindings
- ✅ RBAC roles for administrators and viewers
- ✅ GitHub repository with CI/CD workflow
- ✅ HTTPRoute for path-based routing
- ✅ Resource quotas and network policies

4. **Clone and customize the generated repository**:

```bash
# The GitHub repo is auto-created at github.com/<owner>/my-new-service
gh repo clone <owner>/my-new-service
cd my-new-service

# Customize the service code in src/app.py
# Modify deployment.yaml if needed
# Push changes to trigger CI/CD
git add .
git commit -m "Initial service implementation"
git push
```

### Add and deploy a new service to existing namespace

Currently, to keep the terraform module simple, each namespace is designed to host a single service.

In the future, we could either:
- Enhance the module to support multiple services per namespace
- Decouple service and gateway route deployment from namespace creation

### Add a new administrator/viewer to existing namespace

1. **Edit `terraform/namespaces.tf`** - Update the administrators or viewers list:

```hcl
"my-service" = {
  administrators = [
    { email = "admin@example.com", name = "Admin User" },
    { email = "newadmin@example.com", name = "New Admin" }  # Add this line
  ]
  viewers = [
    { email = "viewer@example.com", name = "Viewer User" },
    { email = "newviewer@example.com", name = "New Viewer" }  # Add this line
  ]
  # ... rest of config ...
}
```

2. **Apply Terraform changes**:

```bash
sh ./scripts/auth.sh
cd terraform/
terraform plan  # Verify only RBAC changes
terraform apply
```

3. **New users can now access the cluster**:

```bash
# User authenticates with their Google account
gcloud auth login

# Get cluster credentials
gcloud container clusters get-credentials infra-seed-cluster \
  --region=us-central1 \
  --project=$(gcloud config get-value project)

# Set namespace context
kubectl config set-context --current --namespace=my-service

# Administrators can view and modify resources
kubectl get pods
kubectl logs <pod-name>
kubectl exec -it <pod-name> -- /bin/sh

# Viewers can only view resources (read-only)
kubectl get pods
kubectl get services
# kubectl delete pod <pod-name>  # This will fail for viewers
```

**Role Permissions**:
- **Administrators**: Full access to namespace resources (create, read, update, delete)
- **Viewers**: Read-only access to namespace resources (get, list, watch)

## 🌐 Traffic Flow

```
User Request
    ↓
Cloudflare DNS → Cloudflare Proxy (DDoS protection)
    ↓
GCP Static IP → HTTPS Load Balancer
    ↓
SSL Certificate → Gateway API (GKE Gateway Controller)
    ↓
Gateway → HTTPRoutes (path-based routing) + Backend Policies
    ↓
Network Endpoint Group (NEG) + Health Checks
    ↓
Kubernetes Service → Pods (in isolated namespaces)
```

**Detailed Flow:**

1. **DNS Resolution** - Cloudflare resolves domain to GCP static IP
2. **Cloudflare Proxy** - Request passes through Cloudflare's network (DDoS protection, WAF)
3. **Load Balancer** - GCP HTTPS Load Balancer terminates SSL with managed certificate
4. **Gateway API** - GKE's Gateway Controller processes the request through:
   - **Gateway Resource** - Entry point that references the load balancer
   - **HTTPRoute Resources** - Match request paths (e.g., `/one`, `/two`) and route to appropriate services
   - **Backend Policies** - Define health check configurations
5. **NEG (Network Endpoint Groups)** - Direct traffic to pod IPs (not node IPs)
6. **Kubernetes Service** - ClusterIP service in the target namespace
7. **Pods** - Application containers receive and process the request

**Why Gateway API instead of Ingress?**
- Gateway API is the modern successor to Ingress
- Better separation of concerns (infrastructure vs routing)
- More expressive routing rules
- Native GKE integration with Google Cloud Load Balancer
- Built-in health check configuration

## 💰 Cost Estimate

- **GKE Cluster**: ~$75/month (regional control plane)
- **Compute**: ~$30/month (e2-medium nodes)
- **Load Balancer**: ~$18/month
- **Other**: ~$5/month (DNS, storage, etc.)
- **Total**: ~$128/month for production-ready setup

**Cost Optimization Tips:**

- **Use preemptible nodes** for non-production environments (~70% cost savings on compute)
- **Enable cluster autoscaling** to scale down during low-traffic periods
- **Use Cloud NAT** for outbound internet access instead of assigning external IPs to individual nodes:
  - Nodes currently use private IPs only (already configured)
  - If nodes need to reach external services (e.g., API calls, package downloads), Cloud NAT provides a shared gateway
  - This reduces costs by sharing a single NAT gateway across all nodes rather than paying for individual external IPs
  - Note: Current setup already uses private nodes; Cloud NAT is only needed if your pods need outbound internet access
- **Right-size your nodes** - Start with e2-medium and adjust based on actual usage
- **Use committed use discounts** for 1-3 year commitments (up to 57% savings)
- **Implement pod autoscaling** (HPA) to optimize resource utilization within nodes

## 🔒 Security Features

- ✅ **Workload Identity Federation** - No service account keys
- ✅ **SSL Encryption** - Cloudflare Origin Certificate
- ✅ **Cloudflare Protection** - DDoS mitigation, WAF
- ✅ **Cloudflare Proxy** - Hide origin IP
- ✅ **Role-Based Access Control** - Namespace-level access
- ✅ **Private GKE Nodes** - Nodes on private IPs
- ✅ **Audit Logging** - All actions logged to Cloud Logging


## 🔗 Links

**Project Repository**
- [GitHub Repository](https://github.com/hochoy/infra-seed)

**Google Cloud Platform**
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [Gateway API on GKE](https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways)
- [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [Artifact Registry](https://cloud.google.com/artifact-registry/docs)
- [GCP Pricing Calculator](https://cloud.google.com/products/calculator)

**Kubernetes**
- [Kubernetes Documentation](https://kubernetes.io/docs/home/)
- [Gateway API](https://gateway-api.sigs.k8s.io/)
- [RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

**Cloudflare**
- [Cloudflare Docs](https://developers.cloudflare.com/)
- [Origin CA Certificates](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
- [Cloudflare Terraform Provider](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs)

**Terraform**
- [Terraform Documentation](https://developer.hashicorp.com/terraform/docs)
- [Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Kubernetes Provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)

**GitHub Actions**
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Workload Identity Federation for GitHub](https://cloud.google.com/blog/products/identity-security/enabling-keyless-authentication-from-github-actions)

**Related Blog Posts**
- [BLOG.md](./BLOG.md) - Detailed blog post about this project

## 🔮 Future Enhancements

- Split terraform into foundational and application layers
    - Foundational: GKE cluster, networking, Cloudflare
    - Application: Namespaces, deployments, services

- Add other compute options and services
    - Cloudflare Cloud Workers 
    - GCP Cloud Run
    - GCP Pub/Sub
    - Databases and Caches (Cloud SQL, Memorystore)
    - Object Storage (Cloud Storage, Cloudflare R2)

- Preventing access to GCP Load Balancer IP
    - Firewall rules - allow only Cloudflare IP ranges (caveat: other cloudflare customers can still access)
    - Cloudflare Tunnel - hide the IP completely (caveat: might not scale as well)

- Istio or Envoy for advanced traffic management
- OAuth2 for customers versus team members
- Add Helm chart support for application deployments
- Integrate monitoring
- Other languages/framework templates (Node.js, Go, Java, Rust, etc.)
