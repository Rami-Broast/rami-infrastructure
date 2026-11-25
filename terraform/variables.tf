variable "project_id" {
  type        = string
  description = "GCP project id."
}

variable "region" {
  type        = string
  description = "Primary region, e.g. me-central2."
}

variable "env" {
  type        = string
  description = "Environment name: staging or production."
  validation {
    condition     = contains(["staging", "production"], var.env)
    error_message = "env must be 'staging' or 'production'."
  }
}

variable "db_tier" {
  type        = string
  description = "Cloud SQL machine tier."
  default     = "db-custom-1-3840"
}

variable "backup_retention_days" {
  type        = number
  description = "Lifecycle delete age (days) for logical backups in GCS."
  default     = 90
}

# Secret NAMES only — values are added out-of-band (scripts/setup-secrets.sh),
# never through Terraform, so no secret ever lands in state.
variable "secret_names" {
  type        = list(string)
  description = "Secret Manager secrets to create (names only)."
  default = [
    "DATABASE_URL",
    "JWT_ACCESS_SECRET",
    "PAYMENT_MOCK_WEBHOOK_SECRET",
  ]
}
