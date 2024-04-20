#!/bin/bash

# Usage check
if [ $# -ne 5 ]; then
    echo "Usage: $0 <vault-address> <vault-username> <vault-password> <source-path> <destination-path>"
    exit 1
fi

# Assign arguments to variables
VAULT_ADDR=$1
VAULT_USERNAME=$2
VAULT_PASSWORD=$3
SOURCE_PATH=$(echo $4 | sed 's:/*$::')  # Normalize the input path by removing trailing slashes
DEST_PATH=$(echo $5 | sed 's:/*$::')    # Normalize the input path by removing trailing slashes

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

# Function to recursively copy secrets
copy_secrets() {
    local source_path=$(echo "secret/$1" | sed 's://*/:/:g')  # Normalize path to avoid double slashes
    local dest_path=$(echo "secret/$2" | sed 's://*/:/:g')    # Normalize path to avoid double slashes

    echo "Processing $source_path"

    # List the path to see if it's a directory
    secrets=$(vault kv list -format=json "$source_path" 2>/dev/null)
    if [ $? -eq 0 ]; then
        # Directory; recurse through the list
        local entries=$(echo "$secrets" | jq -r '.[]')
        for entry in $entries; do
            copy_secrets "$1/$entry" "$2/$entry"
        done
    else
        echo "Attempting to read $source_path as a secret..."
        # Try reading as a single secret
        secret_data=$(vault kv get -format=json "$source_path" 2>/dev/null)
        if [ $? -eq 0 ]; then
            # Extracting data field from secret
            secret_payload=$(echo "$secret_data" | jq -r .data.data)
            if [ "$secret_payload" != "null" ]; then
                # Write secret to the new path
                echo "$secret_payload" | vault kv put "$dest_path" -
                echo "Copied $source_path to $dest_path"
            else
                echo "No data found at $source_path, skipping..."
            fi
        else
            echo "Failed to read or list $source_path; it might not exist or permission denied"
        fi
    fi
}

# Start the copy process
copy_secrets "$SOURCE_PATH" "$DEST_PATH"
