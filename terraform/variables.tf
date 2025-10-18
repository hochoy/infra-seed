variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

variable "gke_cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "infra-seed-cluster"
}

variable "artifact_registry_name" {
  description = "Name of the Artifact Registry repository"
  type        = string
  default     = "infra-seed-registry"
}

variable "github_owner" {
  description = "GitHub repository owner/organization"
  type        = string
}

# Note: github_token is not needed as a variable
# The GitHub provider reads from GITHUB_TOKEN environment variable by default
# Set it with: export GITHUB_TOKEN=$(gh auth token)

variable "github_repo_name" {
  description = "GitHub repository name (for current monorepo)"
  type        = string
  default     = "infra-seed"
}

variable "domain_name" {
  description = "Your domain name (e.g., example.com)"
  type        = string
}

variable "cloudflare_proxy_enabled" {
  description = "Enable Cloudflare proxy (orange cloud)"
  type        = bool
  default     = true
}

variable "enable_api_subdomain" {
  description = "Enable API subdomain (api.yourdomain.com)"
  type        = bool
  default     = true
}
