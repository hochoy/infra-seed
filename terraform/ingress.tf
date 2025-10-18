# Static IP address for the ingress
resource "google_compute_global_address" "ingress_ip" {
  name         = "infra-seed-ingress-ip"
  description  = "Static IP for infra-seed ingress"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"

  depends_on = [google_project_service.required_apis]
}

# Generate a private key for the certificate
# Replaced Google-managed SSL with Cloudflare Origin CA for better control
resource "tls_private_key" "origin_cert" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create a CSR using the private key
resource "tls_cert_request" "origin_cert" {
  private_key_pem = tls_private_key.origin_cert.private_key_pem

  subject {
    common_name  = var.domain_name
    organization = "PyKube"
  }
}

# Generate Cloudflare Origin Certificate using the CSR
# Provides end-to-end encryption between Cloudflare and GCP origin
resource "cloudflare_origin_ca_certificate" "main" {
  csr                = tls_cert_request.origin_cert.cert_request_pem
  hostnames          = [var.domain_name, "*.${var.domain_name}"]
  request_type       = "origin-rsa"
  requested_validity = 5475 # 15 years
}

# SSL certificate using the Cloudflare Origin Certificate
# NOTE: This GCP SSL cert is created but not used due to ingress controller limitations
resource "google_compute_ssl_certificate" "origin_cert" {
  name_prefix = "infra-seed-origin-cert-"
  description = "SSL certificate from Cloudflare Origin CA"

  # Use the generated certificate and private key
  certificate = cloudflare_origin_ca_certificate.main.certificate
  private_key = tls_private_key.origin_cert.private_key_pem

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_project_service.required_apis]
}

# Note: Backend service will be created automatically by GKE ingress controller
# when using container-native load balancing with NEGs

# Note: Health check will be created automatically by GKE ingress controller
# via the BackendConfig specification in Kubernetes

# Note: URL map, target proxy, and forwarding rules will be created 
# automatically by GKE ingress controller

# Firewall rule to allow health checks
resource "google_compute_firewall" "allow_health_checks" {
  name    = "allow-health-checks"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  # Google Cloud health check source ranges
  source_ranges = [
    "130.211.0.0/22",
    "35.191.0.0/16"
  ]

  # Target all instances in the VPC subnet (GKE nodes will be in this range)
  target_tags = ["gke-node"]

  depends_on = [google_project_service.required_apis]
}

# Kubernetes TLS Secret for the ingress
# Contains the Cloudflare Origin CA certificate and private key
resource "kubernetes_secret" "tls_certificate" {
  depends_on = [
    null_resource.wait_for_cluster_ready,
    cloudflare_origin_ca_certificate.main
  ]

  metadata {
    name      = "hundred-sh-tls"
    namespace = "default"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "tls-certificate"
    }
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = cloudflare_origin_ca_certificate.main.certificate
    "tls.key" = tls_private_key.origin_cert.private_key_pem
  }
}

# Null resource to wait for cluster to be fully ready
# Checks cluster status and node readiness before creating Kubernetes manifests
resource "null_resource" "wait_for_cluster_ready" {
  depends_on = [
    google_container_cluster.primary,
    google_container_node_pool.primary_nodes
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for cluster to be ready..."
      
      # Wait for cluster to be RUNNING
      echo "Checking cluster status..."
      for i in {1..30}; do
        STATUS=$(gcloud container clusters describe ${google_container_cluster.primary.name} \
          --zone=${google_container_cluster.primary.location} \
          --project=${var.project_id} \
          --format="value(status)" 2>/dev/null || echo "ERROR")
        
        if [ "$STATUS" = "RUNNING" ]; then
          echo "✅ Cluster is RUNNING"
          break
        fi
        
        echo "Cluster status: $STATUS, waiting... ($i/30)"
        if [ $i -eq 30 ]; then
          echo "❌ ERROR: Cluster failed to reach RUNNING status after 5 minutes"
          echo "Final cluster status: $STATUS"
          exit 1
        fi
        sleep 10
      done
      
      # Wait for nodes to be ready
      echo "Checking node readiness..."
      for i in {1..30}; do
        READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep Ready | wc -l || echo "0")
        TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [ "$READY_NODES" -gt 0 ] && [ "$READY_NODES" -eq "$TOTAL_NODES" ]; then
          echo "✅ All $READY_NODES nodes are ready"
          break
        fi
        
        echo "Nodes ready: $READY_NODES/$TOTAL_NODES, waiting... ($i/30)"
        if [ $i -eq 30 ]; then
          echo "❌ ERROR: Nodes failed to become ready after 5 minutes"
          echo "Final node status: $READY_NODES/$TOTAL_NODES ready"
          kubectl get nodes --no-headers 2>/dev/null || echo "Unable to get node status"
          exit 1
        fi
        sleep 10
      done
      
      # Wait for Gateway API CRDs to be available
      echo "Checking Gateway API CRDs..."
      for i in {1..20}; do
        if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 && \
           kubectl get crd httproutes.gateway.networking.k8s.io >/dev/null 2>&1; then
          echo "✅ Gateway API CRDs are available"
          break
        fi
        
        echo "Gateway API CRDs not ready, waiting... ($i/20)"
        if [ $i -eq 20 ]; then
          echo "❌ ERROR: Gateway API CRDs not available after 1m 40s"
          echo "Available CRDs:"
          kubectl get crd | grep gateway 2>/dev/null || echo "No Gateway CRDs found"
          exit 1
        fi
        sleep 5
      done
      
      echo "🎉 Cluster readiness check completed successfully!"
      echo "✅ Cluster: RUNNING"
      echo "✅ Nodes: All ready"  
      echo "✅ Gateway API: CRDs available"
    EOT
  }

  # Trigger re-run if cluster or node pool changes
  triggers = {
    cluster_id   = google_container_cluster.primary.id
    node_pool_id = google_container_node_pool.primary_nodes.id
  }
}

# Central Gateway Resource
# Single Gateway that handles all routing using Gateway API
# This replaces the Ingress and enables native cross-namespace routing
# Note: Initial deployment shows "fault filter abort" until routes are configured - use ./scripts/test.sh to verify deployment milestones (see https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-multi-cluster-gateways)
resource "kubernetes_manifest" "main_gateway" {
  depends_on = [
    null_resource.wait_for_cluster_ready,
    google_compute_ssl_certificate.origin_cert,
    kubernetes_secret.tls_certificate,
    module.namespace
  ]

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "infra-seed-main-gateway"
      namespace = "default"
      annotations = {
        "networking.gke.io/load-balancer-type" = "External"
      }
    }
    spec = {
      gatewayClassName = "gke-l7-global-external-managed"
      # Static IP assignment using addresses field (not annotation)
      # Reference: https://cloud.google.com/kubernetes-engine/docs/how-to/deploying-gateways#reserve-static-ip
      addresses = [{
        type  = "NamedAddress"
        value = google_compute_global_address.ingress_ip.name
      }]
  listeners = [{
    name     = "https"
    protocol = "HTTPS"
    port     = 443
    hostname = var.domain_name
    tls = {
      mode = "Terminate"
      certificateRefs = [{
        kind = "Secret"
        name = "hundred-sh-tls"
      }]
    }
    allowedRoutes = {
      namespaces = {
        from = "All"
      }
    }
  }]
    }
  }
}

# Output the static IP address
output "static_ip_address" {
  description = "The static IP address for the ingress"
  value       = google_compute_global_address.ingress_ip.address
}

# Output the SSL certificate name
output "ssl_certificate_name" {
  description = "The name of the SSL certificate"
  value       = google_compute_ssl_certificate.origin_cert.name
}
