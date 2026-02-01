#!/bin/bash -xe
curl -s http://localhost:8080/items \
  -H "X-API-KEY: default-apikey" \
  -H "Content-Type: application/json" | jq .
