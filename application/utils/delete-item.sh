#!/bin/bash -e
curl -s -X 'DELETE' \
  http://localhost:8080/item/${1:-unknownid} \
  -H "X-API-KEY: default-apikey" \
  -H 'accept: application/json' | jq -c .
