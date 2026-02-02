#!/bin/bash -xe
curl -X POST "https://cloud-run-and-firebase-gateway-8gak4itf.uc.gateway.dev/api/items/create" \
  -H "x-api-key: ${TESTING_API_KEY}" \
  -H "Authorization: Bearer ${ID_TOKEN}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "name=Created from the command line"
