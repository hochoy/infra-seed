# GitHub Automation
# Creates template repository and generates service repositories with auto-configured github.yaml

# Template repository - contains base service structure
resource "github_repository" "service_template" {
  name        = "infra-seed-service-template"
  description = "Template repository for infra-seed microservices"
  visibility  = "private"
  is_template = true

  has_issues   = false
  has_projects = false
  has_wiki     = false
  auto_init    = true
  
  # default_branch is deprecated - main branch is created automatically with auto_init
}

# Populate template repository with service files
resource "github_repository_file" "template_dockerfile" {
  repository          = github_repository.service_template.name
  branch              = "main"
  file                = "Dockerfile"
  content             = file("${path.module}/templates/service/Dockerfile")
  commit_message      = "Add Dockerfile template"
  commit_author       = "Terraform"
  commit_email        = "terraform@infra-seed.local"
  overwrite_on_create = true
}

resource "github_repository_file" "template_requirements" {
  repository          = github_repository.service_template.name
  branch              = "main"
  file                = "requirements.txt"
  content             = file("${path.module}/templates/service/requirements.txt")
  commit_message      = "Add requirements.txt"
  commit_author       = "Terraform"
  commit_email        = "terraform@infra-seed.local"
  overwrite_on_create = true
}

resource "github_repository_file" "template_deployment" {
  repository          = github_repository.service_template.name
  branch              = "main"
  file                = "deployment.yaml"
  content             = file("${path.module}/templates/service/deployment.yaml")
  commit_message      = "Add deployment.yaml"
  commit_author       = "Terraform"
  commit_email        = "terraform@infra-seed.local"
  overwrite_on_create = true
}

resource "github_repository_file" "template_service" {
  repository          = github_repository.service_template.name
  branch              = "main"
  file                = "service.yaml"
  content             = file("${path.module}/templates/service/service.yaml")
  commit_message      = "Add service.yaml"
  commit_author       = "Terraform"
  commit_email        = "terraform@infra-seed.local"
  overwrite_on_create = true
}

resource "github_repository_file" "template_app" {
  repository          = github_repository.service_template.name
  branch              = "main"
  file                = "src/app.py"
  content             = file("${path.module}/templates/service/src/app.py")
  commit_message      = "Add app.py"
  commit_author       = "Terraform"
  commit_email        = "terraform@infra-seed.local"
  overwrite_on_create = true
}

resource "github_repository_file" "template_readme" {
  repository          = github_repository.service_template.name
  branch              = "main"
  file                = "README.md"
  content             = file("${path.module}/templates/service/README.md")
  commit_message      = "Add README.md"
  commit_author       = "Terraform"
  commit_email        = "terraform@infra-seed.local"
  overwrite_on_create = true
}

# Test: Adding workflow file to template to verify if limitation exists
resource "github_repository_file" "template_workflow" {
  repository          = github_repository.service_template.name
  branch              = "main"
  file                = ".github/workflows/deploy.yml"
  content             = file("${path.module}/templates/workflows/deploy.yml")
  commit_message      = "Add workflow template"
  commit_author       = "Terraform"
  commit_email        = "terraform@infra-seed.local"
  overwrite_on_create = true
}

# Create service repositories from template
resource "github_repository" "service" {
  for_each = local.namespaces

  name        = each.key
  description = "Microservice: ${each.key}"
  visibility  = "private"

  # Create from template
  template {
    owner                = var.github_owner
    repository           = github_repository.service_template.name
    include_all_branches = false
  }

  has_issues           = true
  has_projects         = false
  has_wiki             = false
  vulnerability_alerts = true

  depends_on = [github_repository.service_template]
}

# Generate github.yaml from Terraform outputs - NO HARDCODED VALUES!
resource "github_repository_file" "github_config" {
  for_each = local.namespaces

  repository = github_repository.service[each.key].name
  branch     = "main"
  file       = "github.yaml"

  content = yamlencode({
    gcp = {
      project_id   = var.project_id
      region       = var.region
      cluster_name = var.gke_cluster_name
      service_account = module.namespace[each.key].gcp_service_account_email
    }
    registry = {
      url        = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.main.name}"
      image_name = each.key
    }
    workload_identity = {
      provider = google_iam_workload_identity_pool_provider.github_actions.name
    }
    kubernetes = {
      namespace       = module.namespace[each.key].namespace_name
      deployment_name = "${each.key}-deployment"
      service_name    = "${each.key}-service"
    }
    app = {
      port     = lookup(each.value.routing, "service_port", 80)
      replicas = 2
    }
    build = {
      context    = "."
      dockerfile = "Dockerfile"
    }
  })

  commit_message      = "Generate github.yaml from Terraform"
  commit_author       = "Terraform"
  commit_email        = "terraform@infra-seed.local"
  overwrite_on_create = true

  depends_on = [
    module.namespace,
    google_iam_workload_identity_pool.github_actions
  ]
}

# Add all template files to service repositories explicitly
# (Template repositories sometimes have timing issues, so we ensure all files are present)

resource "github_repository_file" "service_dockerfile" {
  for_each = local.namespaces

  repository = github_repository.service[each.key].name
  branch     = "main"
  file       = "Dockerfile"
  content    = file("${path.module}/templates/service/Dockerfile")

  commit_message      = "Add Dockerfile"
  commit_author       = "Terraform"
  commit_email        = "terraform@infra-seed.local"
  overwrite_on_create = true

  depends_on = [github_repository.service]
}

resource "github_repository_file" "service_requirements" {
  for_each = local.namespaces

  repository = github_repository.service[each.key].name
  branch     = "main"
  file       = "requirements.txt"
  content    = file("${path.module}/templates/service/requirements.txt")

  commit_message      = "Add requirements.txt"
  commit_author       = "Terraform"
  commit_email        = "terraform@infra-seed.local"
  overwrite_on_create = true

  depends_on = [github_repository.service]
}

resource "github_repository_file" "service_deployment" {
  for_each = local.namespaces

  repository = github_repository.service[each.key].name
  branch     = "main"
  file       = "deployment.yaml"
  content    = file("${path.module}/templates/service/deployment.yaml")

  commit_message      = "Add deployment.yaml"
  commit_author       = "Terraform"
  commit_email        = "terraform@infra-seed.local"
  overwrite_on_create = true

  depends_on = [github_repository.service]
}

resource "github_repository_file" "service_service_yaml" {
  for_each = local.namespaces

  repository = github_repository.service[each.key].name
  branch     = "main"
  file       = "service.yaml"
  content    = file("${path.module}/templates/service/service.yaml")

  commit_message      = "Add service.yaml"
  commit_author       = "Terraform"
  commit_email        = "terraform@infra-seed.local"
  overwrite_on_create = true

  depends_on = [github_repository.service]
}

resource "github_repository_file" "service_readme" {
  for_each = local.namespaces

  repository = github_repository.service[each.key].name
  branch     = "main"
  file       = "README.md"
  content    = file("${path.module}/templates/service/README.md")

  commit_message      = "Add README.md"
  commit_author       = "Terraform"
  commit_email        = "terraform@infra-seed.local"
  overwrite_on_create = true

  depends_on = [github_repository.service]
}

resource "github_repository_file" "service_app" {
  for_each = local.namespaces

  repository = github_repository.service[each.key].name
  branch     = "main"
  file       = "src/app.py"
  content    = file("${path.module}/templates/service/src/app.py")

  commit_message      = "Add application code"
  commit_author       = "Terraform"
  commit_email        = "terraform@infra-seed.local"
  overwrite_on_create = true

  depends_on = [github_repository.service]
}

resource "github_repository_file" "service_workflow" {
  for_each = local.namespaces

  repository = github_repository.service[each.key].name
  branch     = "main"
  file       = ".github/workflows/deploy.yml"
  content    = file("${path.module}/templates/workflows/deploy.yml")

  commit_message      = "Add deployment workflow"
  commit_author       = "Terraform"
  commit_email        = "terraform@infra-seed.local"
  overwrite_on_create = true

  depends_on = [github_repository.service]
}

# Outputs
output "service_repositories" {
  description = "Generated service repositories"
  value = {
    for k, v in github_repository.service : k => {
      name      = v.name
      html_url  = v.html_url
      clone_url = v.ssh_clone_url
    }
  }
}

output "template_repository" {
  description = "Template repository"
  value = {
    name     = github_repository.service_template.name
    html_url = github_repository.service_template.html_url
  }
}
