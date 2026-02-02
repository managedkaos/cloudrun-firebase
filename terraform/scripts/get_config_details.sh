#!/bin/bash -xe
gcloud api-gateway api-configs describe cloud-run-and-firebase-20260128223218337500000001 \
  --api=cloud-run-and-firebase-api \
  --project=cloud-run-and-firebase \
  --format=yaml

gcloud api-gateway api-configs describe cloud-run-and-firebase-20260128223218337500000001 \
  --api=cloud-run-and-firebase-api \
  --project=cloud-run-and-firebase \
  --view=FULL --format=json | jq -r '.openapiDocuments[0].document.contents' | base64 -d
