# TODOs

- Use the `auth_allowed_emails` resource with `secret_id  = "AUTH_ALLOWED_EMAILS"` (upper case, snake case); remove the lowercase secret with `secret_id  = "auth-allowed-emails"` (lower case, kebab case).

```terraform
# TODO: Figure out how to use Firebase Auth (Identity Platform)
# https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/identity_platform_config
resource "google_identity_platform_config" "auth" {
  provider                   = google-beta.user_project_override_true
  project                    = google_project.default.project_id
  autodelete_anonymous_users = true
  depends_on                 = [google_project_service.services]

  blocking_functions {
    # Dynamically create a trigger block for each blocking function
    dynamic "triggers" {
      for_each = google_cloudfunctions2_function.blocking_functions
      content {
        function_uri = triggers.value.service_config[0].uri
        event_type   = triggers.value.build_config[0].entry_point
      }
    }

    # Forward ID tokens or Access tokens to the function
    forward_inbound_credentials {
      id_token      = true
      access_token  = false
      refresh_token = false
    }
  }

  multi_tenant {
    allow_tenants           = false
    default_tenant_location = null
  }

  sign_in {
    allow_duplicate_emails = false
    email {
      enabled           = true
      password_required = true
    }
    phone_number {
      enabled            = false
      test_phone_numbers = {}
    }
  }
}

# Allow the Identity Platform service agent to call the blocking function
resource "google_cloud_run_service_iam_member" "invoker" {
  for_each = google_cloudfunctions2_function.blocking_functions
  project  = google_project.default.project_id
  location = each.value.location
  service  = each.value.name
  role     = "roles/run.invoker"
  #member     = "serviceAccount:${var.project_id}@appspot.gserviceaccount.com"
  #member     = "serviceAccount:service-${google_project.default.number}@gcp-sa-identitytoolkit.iam.gserviceaccount.com"
  #member     = "allUsers"
  member = "serviceAccount:${google_project_service_identity.identity_toolkit.email}"

  #depends_on = [google_project_service.services]
  depends_on = [
    google_project_service.services,
    google_project_service_identity.identity_toolkit
  ]
}
```

```terraform
# Service Account for the Function
resource "google_service_account" "blocking_function_sa" {
  provider     = google-beta.user_project_override_true
  project      = google_project.default.project_id
  account_id   = "blocking-function-sa"
  display_name = "Blocking Function Service Account"
}

# Grant Function SA access to the Secret
resource "google_secret_manager_secret_iam_member" "blocking_function_sa_secret_access" {
  provider  = google-beta.user_project_override_true
  project   = google_project.default.project_id
  secret_id = google_secret_manager_secret.auth_allowed_emails.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.blocking_function_sa.email}"
}

# Storage Bucket for Function Source
resource "google_storage_bucket" "function_bucket" {
  provider                    = google-beta.user_project_override_true
  project                     = google_project.default.project_id
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
  provider = google-beta.user_project_override_true
  name     = "blocking_functions.${data.archive_file.function_zip.output_md5}.zip"
  bucket   = google_storage_bucket.function_bucket.name
  source   = data.archive_file.function_zip.output_path
}

# Cloud Function (Gen 2)
# Define the triggers for the blocking functions
variable "auth_triggers" {
  default = {
    "before-create"  = "beforeCreate" # Triggered on first-time signup
    "before-sign-in" = "beforeSignIn" # Triggered on every subsequent login
  }
}

resource "google_cloudfunctions2_function" "blocking_functions" {
  for_each = var.auth_triggers

  provider = google-beta.user_project_override_true
  project  = google_project.default.project_id
  name     = "auth-${each.key}"
  location = var.region

  build_config {
    runtime     = "nodejs24"
    entry_point = each.value # beforeCreate and beforeSignIn
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
    service_account_email = google_service_account.blocking_function_sa.email

    environment_variables = {
      GOOGLE_CLOUD_PROJECT    = var.project_id
      FUNCTION_SIGNATURE_TYPE = "cloudevent"
    }

    secret_environment_variables {
      key        = "AUTH_ALLOWED_EMAILS"
      project_id = var.project_id
      secret     = google_secret_manager_secret.auth_allowed_emails.secret_id
      version    = "latest"
    }
  }

  depends_on = [
    google_project_service.services,
    google_secret_manager_secret_iam_member.blocking_function_sa_secret_access
  ]
}
```

```terraform
# TODO: CONFIGURE THIS WHEN SECRETS MANAGER IS IN PLACE
resource "google_identity_platform_default_supported_idp_config" "google_sign_in" {
  provider = google-beta.user_project_override_true
  project  = google_firebase_project.default.project

  enabled       = true
  idp_id        = "google.com"
  client_id     = "<YOUR_OAUTH_CLIENT_ID>"
  client_secret = var.oauth_client_secret

  depends_on = [
    google_identity_platform_config.auth
  ]
}
```
