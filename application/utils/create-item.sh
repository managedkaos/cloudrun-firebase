#!/bin/bash -e
item_id=$(curl -s -X 'POST' \
  'http://localhost:8080/items' \
  -H "X-API-KEY: default-apikey" \
  -H 'accept: application/json' \
  -d '{"name":"Fake item", "price": 1200}' | jq .id)

echo "Item ID = ${item_id}"
