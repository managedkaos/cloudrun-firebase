#!/bin/bash -e

echo -e "\n\n$(date): Begin"

base_url="${1:-http://localhost:8080}"
api_key="${2:-default-apikey}"

echo -e "\n\t\tBase URL: ${base_url}"
echo -e "\t\t API key: ${api_key}"

echo -e "\n$(date): Creating item"
item_id=$(curl -s -X 'POST' \
  "${base_url}/items" \
  -H "X-API-KEY: ${api_key}" \
  -H 'accept: application/json' \
  -d '{"name":"Fake item", "price": 1200}' | jq -r .id)

echo -e "\n\t\tItem ID = ${item_id}"

echo -e "\n$(date): Listing items"

curl -s \
  "${base_url}/items" \
  -H "X-API-KEY: ${api_key}" \
  -H "Content-Type: application/json" | jq .

echo -e "\n$(date): Updating item ${item_id}"

curl -s -X PUT \
  "${base_url}/items/${item_id}" \
  -H "X-API-KEY: ${api_key}" \
  -H "Content-Type: application/json" \
  -d '{"name": "New Name"}' | jq -c .
echo

echo -e "\n$(date): Deleting item ${item_id}"
curl -s -X 'DELETE' \
  "${base_url}/items/${item_id}" \
  -H "X-API-KEY: ${api_key}" \
  -H 'accept: application/json' | jq -c .

echo -e "\n$(date): Done."
