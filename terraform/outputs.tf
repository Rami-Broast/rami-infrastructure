output "api_url" {
  description = "Cloud Run service URL. Client API base is this + /api/v1."
  value       = google_cloud_run_v2_service.api.uri
}

output "sql_connection_name" {
  description = "Cloud SQL connection name (PROJECT:REGION:INSTANCE) for --add-cloudsql-instances."
  value       = google_sql_database_instance.pg.connection_name
}

output "runtime_service_account" {
  description = "Service account the API runs as."
  value       = google_service_account.api.email
}

output "backup_bucket" {
  description = "GCS bucket for logical DB backups (BACKUP_GCS_BUCKET)."
  value       = google_storage_bucket.db_backups.url
}
