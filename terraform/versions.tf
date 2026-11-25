terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Configure a GCS backend for shared state before real use:
  # backend "gcs" { bucket = "rami-tf-state"; prefix = "infra" }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
