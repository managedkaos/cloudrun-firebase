#!/usr/bin/env bash
set -euo pipefail

read -p "Email: " EMAIL
read -s -p "Password: " PASSWORD
echo ""

API_KEY="AIzaSyBQB2Cu1_zWExoECU2OV0w-8BJ3H-bpM24"

ID_TOKEN=$(curl -s \
  "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"returnSecureToken\":true}" \
  | jq -r '.idToken')

if [ -z "${ID_TOKEN}" ] || [ "${ID_TOKEN}" = "null" ]; then
  echo "Failed to fetch ID token."
else
  echo "ID token:"
  echo "export ID_TOKEN=${ID_TOKEN}"
fi
