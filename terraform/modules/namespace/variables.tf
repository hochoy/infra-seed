# Variables for Namespace Module

variable "namespace_name" {
  type        = string
  description = "Name of the namespace"
}

variable "administrators" {
  type = list(object({
    email = string
    name  = string
  }))
  description = "List of administrator users"
  default     = []
}

variable "viewers" {
  type = list(object({
    email = string
    name  = string
  }))
  description = "List of viewer users"
  default     = []
}

variable "wif_repos" {
  type        = list(string)
  description = "List of GitHub repos that can deploy (format: owner/repo)"
}

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
}

variable "cluster_name" {
  type        = string
  description = "GKE cluster name"
}

variable "wif_provider" {
  type        = string
  description = "Workload Identity Federation provider resource name"
}

variable "artifact_registry_name" {
  type        = string
  description = "Artifact Registry repository name"
}

# Resource Quota Variables
variable "quota_cpu_requests" {
  type        = string
  description = "Total CPU requests quota"
  default     = "10"
}

variable "quota_memory_requests" {
  type        = string
  description = "Total memory requests quota"
  default     = "20Gi"
}

variable "quota_cpu_limits" {
  type        = string
  description = "Total CPU limits quota"
  default     = "20"
}

variable "quota_memory_limits" {
  type        = string
  description = "Total memory limits quota"
  default     = "40Gi"
}

variable "quota_pods" {
  type        = string
  description = "Maximum number of pods"
  default     = "20"
}

variable "quota_services" {
  type        = string
  description = "Maximum number of services"
  default     = "10"
}

variable "quota_pvcs" {
  type        = string
  description = "Maximum number of PVCs"
  default     = "5"
}

# Limit Range Variables
variable "default_cpu_request" {
  type        = string
  description = "Default CPU request for containers"
  default     = "100m"
}

variable "default_memory_request" {
  type        = string
  description = "Default memory request for containers"
  default     = "128Mi"
}

variable "default_cpu_limit" {
  type        = string
  description = "Default CPU limit for containers"
  default     = "500m"
}

variable "default_memory_limit" {
  type        = string
  description = "Default memory limit for containers"
  default     = "512Mi"
}

variable "max_cpu_limit" {
  type        = string
  description = "Maximum CPU limit for containers"
  default     = "2"
}

variable "max_memory_limit" {
  type        = string
  description = "Maximum memory limit for containers"
  default     = "4Gi"
}

variable "max_pod_cpu" {
  type        = string
  description = "Maximum CPU for a pod"
  default     = "4"
}

variable "max_pod_memory" {
  type        = string
  description = "Maximum memory for a pod"
  default     = "8Gi"
}

# Network Policy Variables
variable "allow_ingress_from_namespaces" {
  type        = list(string)
  description = "List of namespace names that can send traffic to this namespace"
  default     = []
}

# Routing Configuration Variables
variable "routing" {
  type = object({
    enabled          = bool
    path_prefix      = string
    service_name     = string
    service_port     = number
    gateway_name     = optional(string, "infra-seed-main-gateway")
    gateway_namespace = optional(string, "default")
    url_rewrite      = optional(bool, true)
    rewrite_target   = optional(string, "/")
  })
  description = "Routing configuration for Gateway API HTTPRoute"
  default = {
    enabled          = false
    path_prefix      = "/"
    service_name     = ""
    service_port     = 80
    gateway_name     = "infra-seed-main-gateway"
    gateway_namespace = "default"
    url_rewrite      = true
    rewrite_target   = "/"
  }
}

variable "domain_name" {
  type        = string
  description = "Domain name for HTTPRoute hostname"
}
