#!/bin/bash

VAULT_RETRIES=5
echo "Vault is starting..."
until vault status > /dev/null 2>&1 || [ "$VAULT_RETRIES" -eq 0 ]; do
        echo "Waiting for vault to start...: $((VAULT_RETRIES--))"
        sleep 3
done

#SRY FOR LAZY
POSTGRES_LOCK_FILE=./postgres-wait.lock
if test -f "$POSTGRES_LOCK_FILE"; then
  continue
else
  sleep 20
  touch postgres-wait.lock
fi

VAULT_LOCK_FILE=./init.lock
if test -f "$VAULT_LOCK_FILE"; then
  rm run.sh
  vault agent -log-level debug -config=/vault-agent/config/vault-agent.hcl
else
  export VAULT_TOKEN=longtd@vpbank
  policy_file=/vault-agent/config/nginx.hcl

  # Write a Policy
  echo "Write policy ${policy_file}..."
  vault policy write nginx ${policy_file}

  # Enable the kv Secrets engine and store a secret
  echo "Enable kv secret..."
  vault secrets enable -version=2 kv
  echo "Write Static secret..."
  vault kv put kv/nginx/static app=nginx username=nginx password=sup4s3cr3t

  # Enable the postgres Secrets Engine 
  echo "Enable the postgres Secrets Engine..."
  vault secrets enable -path=postgres database
  vault write postgres/config/products \
      plugin_name=postgresql-database-plugin \
      allowed_roles="*" \
      connection_url="postgresql://{{username}}:{{password}}@postgre-demo:5432?sslmode=disable" \
      username="postgres" \
      password="password"

  # Create a Role for nginx
  echo "Create a Role for nginx..."
  vault write postgres/roles/nginx \
    db_name=products \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' INHERIT;
    GRANT ro TO \"{{name}}\";" \
    default_ttl="30s" \
    max_ttl="1h"
  
  # Enable AppRole and create a role:
  echo "Enable AppRole and create a role..."
  vault auth enable approle
  vault write auth/approle/role/nginx token_policies="nginx"

  # Determine vault-agent path
  vault_agent_dir="/vault-agent"

  # Write out a Role ID and Secret ID
  echo "Write out a Role ID and Secret ID..."
  vault read -format=json auth/approle/role/nginx/role-id \
    | jq -r '.data.role_id' > ${vault_agent_dir}/nginx-role_id
  vault write -format=json -f auth/approle/role/nginx/secret-id \
    | jq -r '.data.secret_id' > ${vault_agent_dir}/nginx-secret_id

  # Create Lock File
  touch init.lock

  # Restart the vault-agent-demo container
  /sbin/reboot
fi













