#!/bin/bash

# Validate that exactly five arguments are provided
if [ $# -ne 5 ]; then
    echo "Usage: $0 <vault-address> <vault-username> <vault-password> <old-path> <new-path>"
    echo "Example $0 $VAULT_ADDR $VAULT_USERNAME $VAULT_PASSWORD tenant/shared/test-dir2 tenant/shared/test-dir"
    exit 1
fi

VAULT_ADDR=$1
VAULT_USERNAME=$2
VAULT_PASSWORD=$3
OLD_PATH=$(echo $4 | sed 's:/*$::')  # Normalize the input path by removing trailing slashes
NEW_PATH=$(echo $5 | sed 's:/*$::')  # Normalize the input path by removing trailing slashes

# Exporting Vault Address for the session
export VAULT_ADDR

# Authenticate and capture the token
VAULT_TOKEN=$(vault login -method=userpass username="$VAULT_USERNAME" password="$VAULT_PASSWORD" -format=json | jq -r '.auth.client_token')

if [ -z "$VAULT_TOKEN" ]; then
    echo "Authentication failed."
    exit 1
fi

# Export the Vault token for the session
export VAULT_TOKEN

# Function to recursively move secrets
move_secrets() {
    local old_path=$(echo "secret/$1" | sed 's://*/:/:g')  # Normalize path to avoid double slashes
    local new_path=$(echo "secret/$2" | sed 's://*/:/:g')  # Normalize path to avoid double slashes

    echo "Processing $old_path"

    # Attempt to list the path to see if it's a directory
    secrets=$(vault kv list -format=json "$old_path" 2>/dev/null)
    if [ $? -eq 0 ]; then
        # It's a directory; recurse through the list
        local entries=$(echo "$secrets" | jq -r '.[]')
        for entry in $entries; do
            move_secrets "$1/$entry" "$2/$entry"
        done
    else
        echo "Attempting to read $old_path as a secret..."
        # If listing failed, try reading it as a single secret
        secret_data=$(vault kv get -format=json "$old_path" 2>/dev/null)
        if [ $? -eq 0 ]; then
            # Extracting data field from secret
            secret_payload=$(echo "$secret_data" | jq -r .data.data)
            if [ "$secret_payload" != "null" ]; then
                # Writing secret to the new path
                echo "$secret_payload" | vault kv put "$new_path" -

                # Extracting version field from secret's metadata, if available
                secret_versions=$(echo "$secret_data" | jq -r '.data.metadata.versions | keys[]?' 2>/dev/null)

                # Check if there are any versions to destroy
                if [ -n "$secret_versions" ]; then
                    for version in $secret_versions; do
                        vault kv destroy -versions="$version" "$old_path"
                        echo "Permanently deleted secret version $version at $old_path"
                    done
                fi

                # Delete the metadata of the old secret
                vault kv metadata delete "$old_path"
                echo "Permanently deleted metadata and all versions at $old_path"
                echo "Moved $old_path to $new_path"
            else
                echo "No data found at $old_path, skipping..."
            fi
        else
            echo "Failed to read or list $old_path, it might not exist or permission denied"
        fi
    fi
}

# Start the moving process
move_secrets "$OLD_PATH" "$NEW_PATH"
