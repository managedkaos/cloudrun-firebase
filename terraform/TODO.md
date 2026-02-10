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

## Tagging

Your Google Cloud organization or folder has a **Tag Engine policy** (or a similar organizational policy) that requires resources to be categorized. This is a common "best practice" in enterprise environments to ensure resources are not orphaned and costs are trackable.

### 1. Benefits of Using Environment Tags

Tagging doesn't just silence the warning; it unlocks several management features:

- **Cost Allocation:** You can filter your billing reports by the `environment` tag to see exactly how much "Development" is costing versus "Production."

- **Security & IAM:** You can write IAM policies that say _"Developers can only manage resources where environment=Development"_, preventing accidental deletions in Production.

- **Automation:** You can run scripts that target specific tags (e.g., "Shut down all Cloud Run services tagged `environment:Test` every night at 8 PM to save money").

- **Governance:** It provides a standardized way to audit your infrastructure without guessing based on service names.

---

### 2. How to "Fix" the Warning

To satisfy the requirement, you need to bind a tag value to your **Project**. Run these commands in your terminal:

**Step A: Find your Project Number**

Bash

```
gcloud projects describe YOUR_PROJECT_ID --format="value(projectNumber)"
```

**Step B: Create the Tag Binding**

The error message expects a specific key/value. Replace `VALUE` with `Development`, `Production`, etc.

Bash

```hcl
# Note: You need the tag value's 'namespaced name' or 'permanent ID'.
# Usually, it looks like: organizations/ORG_ID/tagKeys/environment/tagValues/Development

gcloud resource-manager tags bindings create \
    --tag-value=organizations/YOUR_ORG_ID/tagKeys/environment/tagValues/Development \
    --parent=//cloudresourcemanager.googleapis.com/projects/YOUR_PROJECT_NUMBER
```

> **Tip:** If you don't know the exact IDs for your tags, you can usually add them through the **Google Cloud Console** by going to **IAM & Admin > Tags**.

---

### 3. Deploying Multiple Environments in One Project

While Google generally recommends **one project per environment** (for total isolation), you can definitely manage multiple environments in one project using Cloud Run by following this pattern:

#### The Strategy: Suffixing & Environment Variables

Since a Cloud Run service name must be unique within a project, you differentiate them by name and use `--set-env-vars` to change their behavior.

**1. Deploy the Development version:**

Bash

```bash
gcloud run deploy my-app-dev \
  --source . \
  --set-env-vars="ENV=development,DB_URL=dev-db-url" \
  --region us-central1
```

**2. Deploy the Production version (same code):**

Bash

```bash
gcloud run deploy my-app-prod \
  --source . \
  --set-env-vars="ENV=production,DB_URL=prod-db-url" \
  --region us-central1
```

#### Why do this?

- **Separation:** `my-app-dev` and `my-app-prod` will have completely different URLs.

- **Testing:** You can test new code on the `dev` URL without touching the `prod` traffic.

- **Config:** Your code reads `process.env.DB_URL` (Node) or `os.environ.get('DB_URL')` (Python), so the code remains identical while the database it connects to changes.

## Tagging in TF

You need to grant your user or service account the **Tag Viewer** role on the Organization itself.

If you plan to actually _create_ the binding (the link between your project and the tag), the **Tag Viewer** role is enough to "read" the keys, but you will also need the **Tag User** role to attach them to resources.

- **Tag Viewer (`roles/resourcemanager.tagViewer`):** Allows Terraform to read/find the tag IDs.

- **Tag User (`roles/resourcemanager.tagUser`):** Allows Terraform to "bind" that tag to your Project.

```bash
# 1. Grant permission to READ the tags
gcloud organizations add-iam-policy-binding 663416857025 \
    --member="user:USER_EMAIL" \
    --role="roles/resourcemanager.tagViewer"

# 2. Grant permission to USE/BIND the tags to resources
gcloud organizations add-iam-policy-binding 663416857025 \
    --member="user:USER_EMAIL" \
    --role="roles/resourcemanager.tagUser"
```

```hcl
# --- Variable for your environment name ---
variable "environment_name" {
  type        = string
  description = "The human-readable environment name (e.g., Development, Production, Staging, Test)"
}

# 1. Lookup the Tag Key (the "environment" category)
data "google_tags_tag_key" "env_key" {
  parent     = "organizations/${var.organization_id}"
  short_name = "environment"
}

# 2. Lookup the specific Tag Value based on your variable
data "google_tags_tag_value" "env_value" {
  parent     = data.google_tags_tag_key.env_key.id
  short_name = var.environment_name
}

# Bind the environment tag to the project using the programmatically retrieved IDs
resource "google_tags_tag_binding" "project_binding" {
  # Uses the project number from your 'default' project resource
  parent = "//cloudresourcemanager.googleapis.com/projects/${google_project.default.number}"

  # Uses the permanent ID found by the data source above
  tag_value = data.google_tags_tag_value.env_value.id

  depends_on = [google_project.default]
}
```
