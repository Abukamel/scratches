#!/usr/bin/env python3

import sys
import hvac
import json

def authenticate(client, vault_addr, username, password):
    client.url = vault_addr
    return client.auth.userpass.login(username=username, password=password)

def read_secrets(client, path, secrets_dict):
    try:
        list_response = client.secrets.kv.v2.list_secrets(path=path)
        for secret_path in list_response['data']['keys']:
            new_path = f"{path}/{secret_path}".strip('/')
            if secret_path.endswith('/'):
                read_secrets(client, new_path, secrets_dict)  # Recursive call for directories
            else:
                # Set raise_on_deleted_version explicitly to True to avoid deprecation warning
                secret_data = client.secrets.kv.v2.read_secret_version(path=new_path, raise_on_deleted_version=True)
                secrets_dict[new_path] = secret_data['data']['data']
    except hvac.exceptions.InvalidPath:
        # Set raise_on_deleted_version explicitly to True to avoid deprecation warning
        secret_data = client.secrets.kv.v2.read_secret_version(path=path, raise_on_deleted_version=True)
        secrets_dict[path] = secret_data['data']['data']

def main():
    if len(sys.argv) != 5:
        print("Usage: python read_secrets.py <vault-address> <vault-username> <vault-password> <path-to-read>")
        sys.exit(1)

    vault_addr, username, password, path_to_read = sys.argv[1:5]
    client = hvac.Client()

    if authenticate(client, vault_addr, username, password):
        secrets_dict = {}
        read_secrets(client, path_to_read, secrets_dict)
        print(json.dumps(secrets_dict, indent=4))
    else:
        print("Authentication failed.")
        sys.exit(1)

if __name__ == "__main__":
    main()
