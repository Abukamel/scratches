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

# Function to recursively read secrets and output them as JSON
read_secrets() {
    local path_to_read=$(echo "secret/$1" | sed 's://*/:/:g')  # Normalize path to avoid double slashes
    local is_directory=$(vault kv list -format=json "$path_to_read" 2>/dev/null)

    if [ $? -eq 0 ]; then
        # It's a directory; recurse through the list and build the JSON object
        local entries=$(echo "$is_directory" | jq -r '.[]')
        for entry in $entries; do
            read_secrets "$1/$entry"
        done
    else
        # Attempt to read the path as a single secret
        local secret_data=$(vault kv get -format=json "$path_to_read" 2>/dev/null)
        if [ $? -eq 0 ]; then
            local secret_payload=$(echo "$secret_data" | jq -r '.data.data')
            if [ "$secret_payload" != "null" ]; then
                # Output the secret data as JSON
                echo "\"$path_to_read\": $secret_payload,"
            fi
        fi
    fi
}

# Wrap the recursive read function calls in a JSON object
echo "{"
read_secrets "$PATH_TO_READ"
echo "}"
