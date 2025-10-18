terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

provider "cloudflare" {
  # API token will be provided via environment variable CLOUDFLARE_API_TOKEN
  # The token needs Zone-SSL and Certificates-Edit permissions for Origin CA
}

provider "github" {
  owner = var.github_owner
  # Token is read from GITHUB_TOKEN environment variable by default
  # Set it with: export GITHUB_TOKEN=$(gh auth token)
  # No need to specify token parameter - provider reads GITHUB_TOKEN automatically
}

# Kubernetes provider to manage GKE resources
provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

# Get current GCP client config for authentication
data "google_client_config" "default" {}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "container.googleapis.com",
    "compute.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Artifact Registry for container images
resource "google_artifact_registry_repository" "main" {
  depends_on = [google_project_service.required_apis]

  location      = var.region
  repository_id = var.artifact_registry_name
  description   = "Docker repository for ${var.project_id}"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-minimum-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }
}

# VPC Network
resource "google_compute_network" "vpc" {
  depends_on = [google_project_service.required_apis]

  name                    = "${var.project_id}-vpc"
  auto_create_subnetworks = false
}

# Subnet for GKE
resource "google_compute_subnetwork" "gke_subnet" {
  name          = "${var.project_id}-gke-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id

  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.2.0.0/20"
  }
}

# GKE Cluster - minimal and cost-friendly
resource "google_container_cluster" "primary" {
  depends_on = [google_project_service.required_apis]

  name     = var.gke_cluster_name
  location = var.region

  # Remove default node pool
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.gke_subnet.name

  # Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Network configuration
  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  # Minimal configuration for cost savings
  cluster_autoscaling {
    enabled = false
  }

  # Basic cluster settings
  deletion_protection = false

  # Enable basic addons
  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }

  # Enable Gateway API
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  # Private cluster configuration for security
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "10.3.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks"
    }
  }
}

# Node pool - stable configuration that works
resource "google_container_node_pool" "primary_nodes" {
  name       = "simple-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 1

  node_config {
    machine_type = "e2-medium" # More stable than e2-micro

    # Google recommends custom service accounts with minimal permissions
    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/userinfo.email"
    ]

    # Enable Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    disk_size_gb = 20            # Increased for stability
    disk_type    = "pd-balanced" # Match actual deployed type

    # Network tags for firewall rules
    tags = ["gke-node"]

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# Service account for GKE nodes
resource "google_service_account" "gke_nodes" {
  account_id   = "${var.project_id}-gke-nodes"
  display_name = "GKE Nodes Service Account"
  description  = "Service account for GKE cluster nodes"
}

# IAM bindings for GKE nodes service account
resource "google_project_iam_member" "gke_nodes_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
    "roles/artifactregistry.reader"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# BACKUP: Manual Gateway API CRD installation if gateway_api_config doesn't work
# Uncomment and apply this block if the cluster doesn't automatically install Gateway API CRDs
#
# resource "null_resource" "install_gateway_api_crds" {
#   depends_on = [google_container_node_pool.primary_nodes]
#   
#   provisioner "local-exec" {
#     command = <<-EOF
#       # Get cluster credentials
#       gcloud container clusters get-credentials ${var.gke_cluster_name} --location=${var.region} --project=${var.project_id}
#       
#       # Install Gateway API CRDs manually
#       kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
#       
#       # Wait for CRDs to be ready
#       kubectl wait --for condition=established --timeout=60s crd/gateways.gateway.networking.k8s.io
#       kubectl wait --for condition=established --timeout=60s crd/httproutes.gateway.networking.k8s.io
#       kubectl wait --for condition=established --timeout=60s crd/referencegrants.gateway.networking.k8s.io
#       kubectl wait --for condition=established --timeout=60s crd/gcpbackendpolicies.networking.gke.io
#     EOF
#   }
#   
#   triggers = {
#     cluster_endpoint = google_container_cluster.primary.endpoint
#   }
# }
