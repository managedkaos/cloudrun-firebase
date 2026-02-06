#!/bin/bash

# Configuration
PROJECT_ID=${1} # TODO: Make a check for the project ID parameter and read the value from env if its not provided

SERVICE_NAME="${SERVICE_NAME:-cloud-run-application}"
REGION="${REGION:-us-central1}"
SECRET_NAME="FIREBASE_CONFIG_JSON"

echo "🚀 Starting Fully Automated Deployment..."

# 1. Get Project Info
echo "$(date) Getting project info"
gcloud config set project "${PROJECT_ID}"
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
echo "$(date)\t   PROJECT_ID = ${PROJECT_ID}"
echo "$(date)\tPROECT_NUMBER = ${PROJECT_NUMBER} "

# 2. Fetch Firebase Config into memory
echo "$(date) Fetching Firebase Web Config via CLI..."
# We use jq to extract just the configuration object from the CLI output
FIREBASE_JSON=$(firebase --project=${PROJECT_ID} apps:sdkconfig WEB 2>/dev/null | sed -n '/^{/,/^}/p')

if [ -z "$FIREBASE_JSON" ] || [ "$FIREBASE_JSON" == "null" ]; then
    echo "❌ Error: Could not fetch Firebase config. Are you logged in?"
    exit 1
fi

# 3. Update or Create Secret using the in-memory variable
if gcloud secrets describe $SECRET_NAME >/dev/null 2>&1; then
    echo "Updating secret: $SECRET_NAME"
    echo -n "$FIREBASE_JSON" | gcloud secrets versions add $SECRET_NAME --data-file=-
else
    echo
    echo
    echo "Secret '$SECRET_NAME' not found in Secret Manager."
    echo "Check the terraform definition and environment where"
    echo "the deploy script is running."
    echo
    echo
    exit 1
fi

# 4. Permissions Check
SA_EMAIL="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"
gcloud secrets add-iam-policy-binding $SECRET_NAME \
    --member="serviceAccount:$SA_EMAIL" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet

# 5. Build and Deploy
echo "Deploying to Cloud Run..."
gcloud run deploy $SERVICE_NAME \
    --source . \
    --region $REGION \
    --set-secrets="$SECRET_NAME=$SECRET_NAME:latest" \
    --allow-unauthenticated

echo "✅ Success! Config fetched from Firebase and deployed to Secret Manager."
