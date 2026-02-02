#!/bin/bash -xe
curl -X PUT http://localhost:8080/items/${1:-unknownid} \
  -H "X-API-KEY: default-apikey" \
  -H "Content-Type: application/json" \
  -d '{"name": "new name"}' | jq -c .
