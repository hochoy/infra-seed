# Cloudflare configuration

# Get the zone ID for your domain
data "cloudflare_zone" "main" {
  name = var.domain_name
}

# Wait for Gateway to be ready and have an IP address assigned
resource "null_resource" "wait_for_gateway_ip" {
  provisioner "local-exec" {
    command = <<-EOF
      echo "Waiting for Gateway to get an IP address..."
      for i in {1..60}; do
        IP=$(kubectl get gateway infra-seed-main-gateway -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
        if [ ! -z "$IP" ]; then
          echo "Gateway IP assigned: $IP"
          exit 0
        fi
        echo "Attempt $i/60: Gateway IP not yet assigned, waiting 10 seconds..."
        sleep 10
      done
      echo "Timeout waiting for Gateway IP"
      exit 1
    EOF
  }
  
  depends_on = [kubernetes_manifest.main_gateway]
}

# Get the Gateway IP address dynamically
data "kubernetes_resource" "gateway_ip" {
  api_version = "gateway.networking.k8s.io/v1"
  kind        = "Gateway"
  
  metadata {
    name      = "infra-seed-main-gateway"
    namespace = "default"
  }
  
  depends_on = [null_resource.wait_for_gateway_ip]
}

# A record pointing to the actual Gateway IP (not the reserved static IP)
resource "cloudflare_record" "main" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@" # Root domain
  content = try(data.kubernetes_resource.gateway_ip.object.status.addresses[0].value, "")
  type    = "A"
  ttl     = var.cloudflare_proxy_enabled ? 1 : 300
  proxied = var.cloudflare_proxy_enabled

  lifecycle {
    precondition {
      condition     = try(data.kubernetes_resource.gateway_ip.object.status.addresses[0].value, "") != ""
      error_message = "Gateway IP address is not yet available"
    }
  }

  depends_on = [data.kubernetes_resource.gateway_ip]
}

# WWW subdomain
resource "cloudflare_record" "www" {
  zone_id = data.cloudflare_zone.main.id
  name    = "www"
  content = try(data.kubernetes_resource.gateway_ip.object.status.addresses[0].value, "")
  type    = "A"
  ttl     = var.cloudflare_proxy_enabled ? 1 : 300
  proxied = var.cloudflare_proxy_enabled

  lifecycle {
    precondition {
      condition     = try(data.kubernetes_resource.gateway_ip.object.status.addresses[0].value, "") != ""
      error_message = "Gateway IP address is not yet available"
    }
  }

  depends_on = [data.kubernetes_resource.gateway_ip]
}

# Optional: API subdomain
resource "cloudflare_record" "api" {
  count   = var.enable_api_subdomain ? 1 : 0
  zone_id = data.cloudflare_zone.main.id
  name    = "api"
  content = try(data.kubernetes_resource.gateway_ip.object.status.addresses[0].value, "")
  type    = "A"
  ttl     = var.cloudflare_proxy_enabled ? 1 : 300
  proxied = var.cloudflare_proxy_enabled

  lifecycle {
    precondition {
      condition     = try(data.kubernetes_resource.gateway_ip.object.status.addresses[0].value, "") != ""
      error_message = "Gateway IP address is not yet available"
    }
  }

  depends_on = [data.kubernetes_resource.gateway_ip]
}

# Cloudflare Page Rules for security and performance
resource "cloudflare_page_rule" "ssl_redirect" {
  zone_id  = data.cloudflare_zone.main.id
  target   = "http://${var.domain_name}/*"
  priority = 1
  status   = "active"

  actions {
    always_use_https = true
  }
}

resource "cloudflare_page_rule" "www_redirect" {
  zone_id  = data.cloudflare_zone.main.id
  target   = "https://www.${var.domain_name}/*"
  priority = 2
  status   = "active"

  actions {
    forwarding_url {
      url         = "https://${var.domain_name}/$1"
      status_code = 301
    }
  }
}

# Security settings
# NOTE: Some settings may require specific Cloudflare plan permissions
resource "cloudflare_zone_settings_override" "main" {
  zone_id = data.cloudflare_zone.main.id

  settings {
    # Security
    security_level = "medium"
    challenge_ttl  = 1800
    browser_check  = "on"

    # SSL
    # Full (Strict) mode validates Origin CA certificates for end-to-end encryption
    ssl                      = "strict"
    always_use_https         = "on"
    min_tls_version          = "1.2"
    automatic_https_rewrites = "on"

    # Performance
    brotli = "on"
    # Note: Minify settings removed due to API compatibility issues
    # Configure minify settings in Cloudflare dashboard if needed

    # Caching
    browser_cache_ttl = 14400
    cache_level       = "aggressive"
  }
}
