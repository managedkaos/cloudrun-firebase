#!/bin/bash -xe
curl -X PUT http://localhost:8080/items/laptop \
  -H "X-API-KEY: default-apikey" \
  -H "Content-Type: application/json" \
  -d '{"price": 1200}'
