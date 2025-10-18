terraform {
  backend "gcs" {
    bucket = "infra-seed-one-terraform-state"
    prefix = "terraform/state"
  }
}
