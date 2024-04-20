#!/bin/bash

# Usage check
if [ $# -ne 4 ]; then
    echo "Usage: $0 <vault-address> <vault-username> <vault-password> <path-to-read>"
    exit 1
fi

# Assign arguments to variables
VAULT_ADDR=$1
VAULT_USERNAME=$2
VAULT_PASSWORD=$3
PATH_TO_READ=$(echo $4 | sed 's:/*$::')  # Normalize the input path by removing trailing slashes

# Export Vault address for the session
export VAULT_ADDR

# Authenticate and capture the token
VAULT_TOKEN=$(vault login -method=userpass username="$VAULT_USERNAME" password="$VAULT_PASSWORD" -format=json | jq -r '.auth.client_token')

if [ -z "$VAULT_TOKEN" ]; then
    echo "Authentication failed."
    exit 1
fi

# Export the Vault token for the session
export VAULT_TOKEN

declare -A secrets_map  # Associate array to hold the paths and data

# Function to recursively read secrets
read_secrets() {
    local path_to_read=$(echo "secret/$1" | sed 's://*/:/:g')  # Normalize path to avoid double slashes

    # Attempt to list the path to see if it's a directory
    local secrets_list=$(vault kv list -format=json "$path_to_read" 2>/dev/null)
    if [ $? -eq 0 ]; then
        # Directory; recurse through the list
        local entries=$(echo "$secrets_list" | jq -r '.[]')
        for entry in $entries; do
            read_secrets "$1/$entry"
        done
    else
        # Single secret; attempt to read
        local secret_data=$(vault kv get -format=json "$path_to_read" 2>/dev/null)
        if [ $? -eq 0 ]; then
            secrets_map["$path_to_read"]=$(echo "$secret_data" | jq '.data.data')
        fi
    fi
}

read_secrets "$PATH_TO_READ"

# Convert the associative array to a JSON object
printf "{\n"
for path in "${!secrets_map[@]}"; do
    printf "%s\n" "\"$path\": ${secrets_map[$path]}"
done | sed '$!s/$/,/'  # Add commas except for the last line
printf "}\n"
