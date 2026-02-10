#!/bin/bash -xe
curl -s -X 'GET' \
  'http://localhost:8080/debug-db' \
  -H "X-API-KEY: default-apikey" \
  -H "accept: application/json" | jq .
