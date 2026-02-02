# --- 0. Variables ---
variable "project_id" {
  type        = string
  description = "The GCP Project ID (must be globally unique)"
}

variable "name" {
  type        = string
  description = "The base name to use for the cloud run instance"
}

variable "region" {
  type        = string
  description = "The GCP region where resources are deployed"
}

# --- 1. Provider & Version Setup ---
# For the gcs backend, you can set the GOOGLE_STORAGE_BUCKET
# environment variable, which the backend configuration will read.
# export GOOGLE_STORAGE_BUCKET="terraform-state-bucket-name"
terraform {
  backend "gcs" {
    prefix = "terraform/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.0"
    }
  }
}

provider "google" {
  project         = var.project_id
  region          = var.region
  billing_project = var.project_id
}

provider "google-beta" {
  project               = var.project_id
  region                = var.region
  billing_project       = var.project_id
  user_project_override = true
}


# --- 2. Enable Required APIs ---
resource "google_project_service" "services" {
  for_each = toset([
    "apigateway.googleapis.com",        # API Gateway
    "apikeys.googleapis.com",           # API Key Credentials
    "artifactregistry.googleapis.com",  # Arifact Registry
    "cloudbuild.googleapis.com",        # Cloud Build
    "cloudfunctions.googleapis.com",    # Cloud Functions
    "firebase.googleapis.com",          # Firebase Management
    "firestore.googleapis.com",         # Firestore
    "identitytoolkit.googleapis.com",   # Firebase Auth
    "run.googleapis.com",               # Cloud Run
    "secretmanager.googleapis.com",     # Secret Manager
    "servicecontrol.googleapis.com",    # Service Control
    "servicemanagement.googleapis.com", # Service Management
  ])
  service            = each.key
  disable_on_destroy = false
}

# --- 3. Initialize Firebase & Firestore ---
resource "google_firebase_project" "default" {
  provider   = google-beta
  project    = var.project_id
  depends_on = [google_project_service.services]
}

resource "google_firestore_database" "database" {
  provider    = google-beta
  project     = var.project_id
  name        = "(default)" # Firebase requires the "(default)" database
  location_id = var.region
  type        = "FIRESTORE_NATIVE"
  depends_on  = [google_firebase_project.default]
}

# --- 4. Configure Firebase Auth (Identity Platform) ---
#
# TODO: Break this out so it is only applied once per project
#
# resource "google_identity_platform_config" "auth" {
#  provider = google-beta
#  project  = var.project_id
#  autodelete_anonymous_users = true
#  sign_in {
#    allow_duplicate_emails = false
#    email {
#      enabled           = true
#      password_required = true
#    }
#  }
#  depends_on = [google_project_service.services]
#}

# --- 5. Cloud Run Service Setup ---

# Create a dedicated Service Account for the Cloud Run instance
resource "google_service_account" "cloud_run_sa" {
  account_id   = "cloud-run-sa"
  display_name = "Cloud Run Service Account"
}

# Grant the Service Account access to Firestore
resource "google_project_iam_member" "firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service
resource "google_cloud_run_v2_service" "cloud_run" {
  name     = var.name
  location = var.region

  # change this to true to prevent accidental deletion
  deletion_protection = false

  template {
    service_account = google_service_account.cloud_run_sa.email
    containers {
      # Use a placeholder image initially
      image = "us-docker.pkg.dev/cloudrun/container/hello"
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name = "FIREBASE_CONFIG_JSON"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.firebase_config.secret_id
            version = "latest"
          }
        }
      }
    }
  }
  depends_on = [google_firestore_database.database]

  lifecycle {
    ignore_changes = [
      client,
      client_version,
      build_config,
      template[0].containers,
    ]
  }
}

# --- 6. Allow Public Access ---
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  name     = google_cloud_run_v2_service.cloud_run.name
  location = google_cloud_run_v2_service.cloud_run.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- 7. Blocking Function & Secrets ---

# Create Secret for Firebase Config
resource "google_secret_manager_secret" "firebase_config" {
  provider   = google-beta
  project    = var.project_id
  secret_id  = "firebase-config"
  depends_on = [google_project_service.services]

  # change this to true to prevent accidental deletion
  deletion_protection = false

  replication {
    auto {}
  }
}

# Create Initial placeholder for Firebase Config
resource "google_secret_manager_secret_version" "firebase_config_version" {
  provider    = google-beta
  secret      = google_secret_manager_secret.firebase_config.id
  secret_data = "{}"

  lifecycle {
    ignore_changes = [
      enabled,
      secret_data
    ]
  }
}

# Grant Cloud Run Access to the Firebase Config Secret
resource "google_secret_manager_secret_iam_member" "firebase_config_access" {
  secret_id = google_secret_manager_secret.firebase_config.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Create Secret for Allowed Emails
resource "google_secret_manager_secret" "auth_allowed_emails" {
  provider   = google-beta
  project    = var.project_id
  secret_id  = "auth-allowed-emails"
  depends_on = [google_project_service.services]

  # change this to true to prevent accidental deletion
  deletion_protection = false

  replication {
    auto {}
  }
}

# Create Initial placeholder for Allowed Emails
resource "google_secret_manager_secret_version" "auth_allowed_emails_version" {
  provider    = google-beta
  secret      = google_secret_manager_secret.auth_allowed_emails.id
  secret_data = "test@example.com"

  lifecycle {
    ignore_changes = [
      enabled,
      secret_data
    ]
  }
}

# Service Account for the Function
resource "google_service_account" "function_sa" {
  account_id   = "auth-blocking-function-sa"
  display_name = "Auth Blocking Function Service Account"
}

# Grant Function SA access to the Secret
resource "google_secret_manager_secret_iam_member" "function_sa_secret_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.auth_allowed_emails.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.function_sa.email}"
}

# Storage Bucket for Function Source
resource "google_storage_bucket" "function_bucket" {
  provider                    = google-beta
  project                     = var.project_id
  name                        = "${var.project_id}-gcf-source"
  location                    = var.region
  uniform_bucket_level_access = true
  depends_on                  = [google_project_service.services]
}

# Zip the function code
data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "../blocking_functions"
  output_path = "/tmp/blocking_functions.zip"
}

# Upload zip to bucket
resource "google_storage_bucket_object" "function_archive" {
  name   = "blocking_functions.${data.archive_file.function_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.function_zip.output_path
}

# Cloud Function (Gen 2)
resource "google_cloudfunctions2_function" "blocking_function" {
  provider = google-beta
  project  = var.project_id
  name     = "auth-before-create"
  location = var.region

  build_config {
    runtime     = "nodejs24"
    entry_point = "beforeCreate" # Export name in index.js
    source {
      storage_source {
        bucket = google_storage_bucket.function_bucket.name
        object = google_storage_bucket_object.function_archive.name
      }
    }
  }

  service_config {
    max_instance_count    = 10
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.function_sa.email
    environment_variables = {
      GCLOUD_PROJECT = var.project_id
    }
  }

  depends_on = [
    google_project_service.services,
    google_secret_manager_secret_iam_member.function_sa_secret_access
  ]
}

# --- 8. API Gateway ---
resource "google_api_gateway_api" "api" {
  provider = google-beta
  project  = var.project_id
  api_id   = "${var.name}-api"

  depends_on = [google_project_service.services]
}

resource "google_api_gateway_api_config" "api_config" {
  provider             = google-beta
  project              = var.project_id
  api                  = google_api_gateway_api.api.api_id
  api_config_id_prefix = "${var.name}-"

  # Creates the new config before trying to delete the old one
  lifecycle {
    create_before_destroy = true
  }

  gateway_config {
    backend_config {
      google_service_account = google_service_account.gateway_sa.email
    }
  }

  openapi_documents {
    document {
      path = "api-gateway-openapi.yaml"
      contents = base64encode(templatefile("${path.module}/api-gateway-openapi.yaml", {
        cloud_run_url = google_cloud_run_v2_service.cloud_run.uri
      }))
    }
  }

  depends_on = [
    google_project_service.services,
    google_cloud_run_v2_service.cloud_run
  ]
}

resource "google_api_gateway_gateway" "api_gateway" {
  provider   = google-beta
  project    = var.project_id
  region     = var.region
  gateway_id = "${var.name}-gateway"
  api_config = google_api_gateway_api_config.api_config.id

  depends_on = [google_api_gateway_api_config.api_config]
}

resource "google_service_account" "gateway_sa" {
  account_id   = "api-gateway-sa"
  display_name = "API Gateway Service Account"
}

resource "google_cloud_run_service_iam_member" "gateway_invoker" {
  service  = google_cloud_run_v2_service.cloud_run.name
  location = google_cloud_run_v2_service.cloud_run.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.gateway_sa.email}"
}

# API Gateway managed service can be eventually consistent right after config creation.
# resource "time_sleep" "wait_for_api_gateway_config" {
#   create_duration = "60s"
#   depends_on      = [google_api_gateway_api_config.api_config]
# }

# Enable the api gateway managed service
resource "google_project_service" "api_gateway_managed_service" {
  service            = google_api_gateway_api.api.managed_service
  disable_on_destroy = false

  depends_on = [
    google_api_gateway_api.api
  ]
}

# TODO: Figure out how to create an API Key in terraform
# Create an API Key
# resource "google_apikeys_key" "api_key" {
#   name         = "${var.name}-key"
#   display_name = "API Key for testing ${var.name}"
#   project      = var.project_id

#   restrictions {
#     api_targets {
#       service = google_api_gateway_api.api.managed_service
#       # Optional: restrict to specific methods/paths
#       # methods = ["GET*"]
#     }
#   }

#   # Ensure the managed service is active before creating the key
#   depends_on = [
#     google_project_service.services,
#     google_project_service.api_gateway_managed_service
#   ]

# }

# --- 9. Outputs ---
output "project_id" {
  value = var.project_id
}

output "service_account_email" {
  value       = google_service_account.cloud_run_sa.email
  description = "The email of the service account running the application"
}

output "cloud_run_url" {
  value       = google_cloud_run_v2_service.cloud_run.uri
  description = "The publicly accessible URL of the Cloud Run service"
}

output "fastapi_docs" {
  value       = "${google_cloud_run_v2_service.cloud_run.uri}/docs"
  description = "The publicly accessible URL of the Cloud Run service"
}

output "blocking_function_uri" {
  value = google_cloudfunctions2_function.blocking_function.service_config[0].uri
}

output "api_gateway_hostname" {
  value       = google_api_gateway_gateway.api_gateway.default_hostname
  description = "Hostname for the API Gateway endpoint"
}

output "api_gateway_url" {
  value       = "https://${google_api_gateway_gateway.api_gateway.default_hostname}/api"
  description = "Base URL for the API Gateway /api routes"
}

# TODO: Output the key when creation is working
# output "api_key_value" {
#   value     = google_apikeys_key.api_key.key_string
#   sensitive = true
# }
