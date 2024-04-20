#!/bin/bash

# Usage check
if [ $# -ne 4 ]; then
    echo "Usage: $0 <vault-address> <vault-username> <vault-password> <path-to-delete>"
    exit 1
fi

# Assign arguments to variables
VAULT_ADDR=$1
VAULT_USERNAME=$2
VAULT_PASSWORD=$3
PATH_TO_DELETE=$(echo $4 | sed 's:/*$::')  # Normalize the input path by removing trailing slashes

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

# Function to recursively delete secrets
delete_secrets() {
    local path_to_delete=$(echo "secret/$1" | sed 's://*/:/:g')  # Normalize path to avoid double slashes

    echo "Processing $path_to_delete"

    # List the path to see if it's a directory
    secrets=$(vault kv list -format=json "$path_to_delete" 2>/dev/null)
    if [ $? -eq 0 ]; then
        # Directory; recurse through the list
        local entries=$(echo "$secrets" | jq -r '.[]')
        for entry in $entries; do
            delete_secrets "$1/$entry"
        done
    else
        echo "Attempting to delete $path_to_delete..."
        # Extracting version field from secret's metadata, if available
        secret_versions=$(vault kv get -format=json "$path_to_delete" | jq -r '.data.metadata.versions | keys[]?' 2>/dev/null)

        # Check if there are any versions to destroy
        if [ -n "$secret_versions" ]; then
            for version in $secret_versions; do
                vault kv destroy -versions="$version" "$path_to_delete"
                echo "Permanently deleted secret version $version at $path_to_delete"
            done
        fi

        # Delete the metadata of the secret
        vault kv metadata delete "$path_to_delete"
        echo "Permanently deleted metadata and all versions at $path_to_delete"
    fi
}

# Start the deletion process
delete_secrets "$PATH_TO_DELETE"
