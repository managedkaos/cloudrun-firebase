# --- 0. Variables ---
variable "project_name" {
  type        = string
  description = "The GCP Project Name. Project names must be between 4 to 30 characters, with lowercase and/or uppercase letters, numbers, hyphens, single-quotes, double-quotes, spaces, and exclamation points. The project name is only used within Firebase interfaces and isn't visible to end-users."
}

variable "project_id" {
  type        = string
  description = "The GCP Project ID; must be globally unique. Project IDs must be between 6 to 30 characters, with lowercase letters, digits, hyphens and must start with a letter. Trailing hyphens are prohibited."
}

variable "region" {
  type        = string
  description = "The GCP region where resources are deployed"
}

variable "environment_name" {
  type        = string
  description = "The human-readable environment name (e.g., Development, Production, Staging, Test)"
}

variable "billing_account" {
  type        = string
  description = "The billing account ID.  Firebase project must use the Blaze plan and be associated with a Cloud Billing account.  See https://console.cloud.google.com/billing/"
}

variable "organization_id" {
  type        = string
  description = "The ID of the organization where resources will be created. You are not required to create an Organization resource to use Google Cloud. You can create, manage, and bill for projects as an individual user without an organization, but creating one is highly recommended for enterprise security, centralized control, and managing resources at scale. See https://console.cloud.google.com/organizations"
}

variable "email_address" {
  type        = string
  description = "The email address to use for budget notifications."
}

variable "budget_currency_code" {
  type        = string
  default     = "USD"
  description = "The email address to use for budget notifications."
}

variable "budget_amount" {
  type        = string
  default     = "25"
  description = "The email address to use for budget notifications."
}

variable "budget_calendar_period" {
  type        = string
  default     = "MONTH"
  description = "Recurring time period for the budget.  Possible values are: MONTH, QUARTER, YEAR, and CALENDAR_PERIOD_UNSPECIFIED."
}

variable "budget_display_name" {
  type        = string
  default     = "Firebase Project Budget"
  description = "The email address to use for budget notifications."
}

variable "cloud_run_name" {
  type        = string
  default     = "cloud-run"
  description = "The base name to use for the cloud run instance"
}

# --- 1. State, Provider, and Project Setup ---
# For the gcs backend, set the environment variable TERRAFORM_STATE_BUCKET.
# Provide the bucket name when running `terraform init`.
# terraform init -backend-config="bucket=${TERRAFORM_STATE_BUCKET}"
terraform {
  backend "gcs" {
  }

  required_providers {
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.0"
    }
  }
}

provider "google-beta" {
  alias                 = "user_project_override_true"
  user_project_override = true
}

provider "google-beta" {
  alias                 = "user_project_override_false"
  user_project_override = false
}

# Create a new Google Cloud project.
# https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_project.html
resource "google_project" "default" {
  provider        = google-beta.user_project_override_true
  name            = var.project_name
  project_id      = var.project_id
  billing_account = var.billing_account
  org_id          = var.organization_id

  # Required for the project to display as a Firebase project.
  labels = {
    "firebase" = "enabled"
  }
}


# --- 2. Enable Required APIs ---
# https://registry.terraform.io/providers/hashicorp/google-beta/7.18.0/docs/resources/google_project_service
resource "google_project_service" "services" {
  project            = google_project.default.project_id
  service            = each.key
  disable_on_destroy = true

  for_each = toset([
    "apigateway.googleapis.com",         # API Gateway
    "apikeys.googleapis.com",            # API Key Credentials
    "artifactregistry.googleapis.com",   # Arifact Registry
    "billingbudgets.googleapis.com",     # Billing API
    "cloudbuild.googleapis.com",         # Cloud Build
    "cloudfunctions.googleapis.com",     # Cloud Functions
    "eventarc.googleapis.com",           # Event Arc
    "firebase.googleapis.com",           # Firebase Management
    "firebaseextensions.googleapis.com", # Firebase Extensions
    "firebasehosting.googleapis.com",    # Firebase Hosting
    "firestore.googleapis.com",          # Firestore
    "identitytoolkit.googleapis.com",    # Firebase Auth
    "monitoring.googleapis.com",         # Monitoring API
    "pubsub.googleapis.com",             # Pub Sub
    "run.googleapis.com",                # Cloud Run
    "secretmanager.googleapis.com",      # Secret Manager
    "servicecontrol.googleapis.com",     # Service Control
    "servicemanagement.googleapis.com",  # Service Management
    "serviceusage.googleapis.com",       # Service Usage
    "storage.googleapis.com",            # Storage
  ])
}


# --- 3. Initialize Firebase, Firestore, and Auth ---

# Firebase
# https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/firebase_project
resource "google_firebase_project" "default" {
  provider   = google-beta.user_project_override_true
  project    = google_project.default.project_id
  depends_on = [google_project_service.services]
}

# Firestore
# https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/firestore_database
resource "google_firestore_database" "database" {
  provider    = google-beta.user_project_override_true
  project     = google_project.default.project_id
  name        = "(default)" # Firebase requires the "(default)" database
  location_id = var.region
  type        = "FIRESTORE_NATIVE"
  depends_on  = [google_firebase_project.default]
}


# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service_identity
# Force creation of the Identity Toolkit service account
resource "google_project_service_identity" "identity_toolkit" {
  provider = google-beta.user_project_override_true
  project  = google_project.default.project_id
  service  = "identitytoolkit.googleapis.com"
}


# --- 5. Cloud Run Service Setup ---

# Create a dedicated Service Account for the Cloud Run instance
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_service_account
resource "google_service_account" "cloud_run_sa" {
  project                      = google_project.default.project_id
  account_id                   = "cloud-run-sa"
  display_name                 = "Cloud Run Service Account"
  create_ignore_already_exists = true
}

# Grant the Service Account access to Firestore
resource "google_project_iam_member" "firestore_user" {
  project = google_project.default.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Create the Artifact Registry repository for Cloud Run
resource "google_artifact_registry_repository" "cloud_run_source_deploy" {
  provider      = google-beta.user_project_override_true
  project       = google_project.default.project_id
  location      = var.region
  repository_id = "cloud-run-source-deploy"
  description   = "Docker repository for Cloud Run source deployments"
  format        = "DOCKER"

  depends_on = [
    google_project_service.services,
  ]
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service
resource "google_cloud_run_v2_service" "cloud_run" {
  provider            = google-beta.user_project_override_true
  project             = google_project.default.project_id
  name                = var.cloud_run_name
  location            = var.region
  deletion_protection = false
  depends_on          = [google_secret_manager_secret_iam_member.firebase_config_access]

  labels = {
    "environment" = lower(var.environment_name)
  }

  template {
    service_account = google_service_account.cloud_run_sa.email
    containers {
      # Use a placeholder image initially
      image = "us-docker.pkg.dev/cloudrun/container/hello"
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
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

  lifecycle {
    ignore_changes = [
      client,
      client_version,
      build_config,
      template[0].containers,
    ]
  }
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_v2_service_iam#google_cloud_run_v2_service_iam_member
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  provider = google-beta.user_project_override_true
  project  = google_project.default.project_id
  name     = google_cloud_run_v2_service.cloud_run.name
  location = google_cloud_run_v2_service.cloud_run.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- X. Secrets ---
# Create Secret for Firebase Config
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret.html
resource "google_secret_manager_secret" "firebase_config" {
  provider            = google-beta.user_project_override_true
  project             = google_project.default.project_id
  secret_id           = "FIREBASE_CONFIG_JSON"
  depends_on          = [google_project_service.services]
  deletion_protection = false

  replication {
    auto {}
  }
}

# Create Initial placeholder for Firebase Config
resource "google_secret_manager_secret_version" "firebase_config_version" {
  provider    = google-beta.user_project_override_true
  project     = google_project.default.project_id
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
  provider  = google-beta.user_project_override_true
  project   = google_project.default.project_id
  secret_id = google_secret_manager_secret.firebase_config.secret_id
  member    = "serviceAccount:${google_service_account.cloud_run_sa.email}"
  role      = "roles/secretmanager.secretAccessor"
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/firebase_web_app
resource "google_firebase_web_app" "default" {
  provider     = google-beta.user_project_override_true
  project      = google_project.default.project_id
  display_name = "Default Firebase Web App"
}

# https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/firebase_hosting_site
resource "google_firebase_hosting_site" "full" {
  provider   = google-beta.user_project_override_true
  project    = google_project.default.project_id
  site_id    = google_project.default.project_id
  app_id     = google_firebase_web_app.default.app_id
  depends_on = [google_project_service.services]
}


# --- X. Provision blocking functions ---
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

# # Create Secret for Allowed Emails
# resource "google_secret_manager_secret" "auth_allowed_emails" {
#   provider   = google-beta
#   project    = var.project_id
#   secret_id  = "AUTH_ALLOWED_EMAILS"
#   depends_on = [google_project_service.services]

#   # change this to true to prevent accidental deletion
#   deletion_protection = false

#   replication {
#     auto {}
#   }
# }

# # Create Initial placeholder for Allowed Emails
# resource "google_secret_manager_secret_version" "auth_allowed_emails_version" {
#   provider    = google-beta
#   secret      = google_secret_manager_secret.auth_allowed_emails.id
#   secret_data = "test@example.com"

#   lifecycle {
#     ignore_changes = [
#       enabled,
#       secret_data
#     ]
#   }
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

output "project_console_url" {
  value       = "https://console.firebase.google.com/project/${var.project_id}/overview"
  description = "The Firebase Console project overview URL"
}

output "hosting_url" {
  value       = "https://${var.project_id}.web.app"
  description = "The Firebase Hosting default URL"
}
