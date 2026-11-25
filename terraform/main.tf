locals {
  suffix       = var.env == "production" ? "" : "-staging"
  service_name = "rami-api${local.suffix}"
  sql_instance = "rami-pg${local.suffix}"
}

# --- Runtime service account (least privilege) --------------------------------
resource "google_service_account" "api" {
  account_id   = "rami-api${local.suffix}"
  display_name = "Rami Broast API runtime (${var.env})"
}

# --- Cloud SQL (Postgres) -----------------------------------------------------
resource "google_sql_database_instance" "pg" {
  name             = local.sql_instance
  database_version = "POSTGRES_16"
  region           = var.region

  settings {
    tier              = var.db_tier
    availability_type = var.env == "production" ? "REGIONAL" : "ZONAL"

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 30
      }
    }
  }

  # Guard against terraform destroy wiping the database in production.
  deletion_protection = var.env == "production"
}

resource "google_sql_database" "app" {
  name     = "bah"
  instance = google_sql_database_instance.pg.name
}

# NOTE: the DB user + password are created out-of-band and stored as the
# DATABASE_URL secret (scripts/setup-secrets.sh) so no credential enters TF state.

# --- Secret Manager (names only; values added out-of-band) --------------------
resource "google_secret_manager_secret" "secrets" {
  for_each  = toset(var.secret_names)
  secret_id = var.env == "production" ? each.value : "${each.value}_STAGING"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "api_access" {
  for_each  = google_secret_manager_secret.secrets
  secret_id = each.value.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

# --- GCS bucket for logical DB backups ----------------------------------------
resource "google_storage_bucket" "db_backups" {
  name                        = "rami-db-backups${local.suffix}-${var.project_id}"
  location                    = var.region
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = var.backup_retention_days
    }
  }
}

# --- Cloud Run service --------------------------------------------------------
# Image is built + deployed by CI (gcloud run deploy --source). Terraform owns
# the service shell, scaling, and wiring; CI pushes new revisions.
resource "google_cloud_run_v2_service" "api" {
  name     = local.service_name
  location = var.region

  template {
    service_account = google_service_account.api.email

    scaling {
      min_instance_count = var.env == "production" ? 1 : 0
      max_instance_count = 10
    }

    containers {
      # Placeholder image; CI replaces it on deploy. Kept out of TF drift with
      # lifecycle.ignore_changes below.
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      ports {
        container_port = 3000
      }
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.pg.connection_name]
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].containers[0].env,
      client,
      client_version,
    ]
  }
}

# Public API (auth is enforced in-app by the global guards).
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
