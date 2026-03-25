#!/bin/sh
# vault-setup.sh
# ─────────────────────────────────────────────────────────────────────────────
# One-time setup: configures the Vault database secrets engine for PostgreSQL.
#
# Prerequisites:
#   - Vault running and VAULT_ADDR + VAULT_TOKEN exported
#   - db container running: docker compose up -d db
#   - Static postgres credentials already stored in Vault KV:
#       docker-dhi-setup/data/postgres → username, password, db
#
# Usage:
#   chmod +x vault-setup.sh && ./vault-setup.sh
# ─────────────────────────────────────────────────────────────────────────────

set -eu

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
DB_MOUNT="database"
DB_ROLE="api-role"
DB_CONNECTION="taskdb-postgres"

echo "==> Reading bootstrap credentials from Vault KV..."
PG_USER=$(vault kv get -field=username docker-dhi-setup/postgres)
PG_PASS=$(vault kv get -field=password docker-dhi-setup/postgres)
PG_DB=$(vault kv get -field=db docker-dhi-setup/postgres)

echo "==> Creating vault_admin role in PostgreSQL..."
# vault_admin is the dedicated user Vault uses to create/revoke dynamic roles.
# Kept separate from the app bootstrap user for least-privilege.
docker exec taskdb psql -U "${PG_USER}" -d "${PG_DB}" -c "
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'vault_admin') THEN
      CREATE ROLE vault_admin
        WITH LOGIN PASSWORD '${PG_PASS}'
        CREATEROLE;
    END IF;
  END
  \$\$;
  GRANT ALL PRIVILEGES ON DATABASE ${PG_DB} TO vault_admin;
  GRANT ALL ON SCHEMA public TO vault_admin;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO vault_admin;
  ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO vault_admin;
"

echo "==> Enabling Vault database secrets engine..."
vault secrets enable -path="${DB_MOUNT}" database 2>/dev/null \
  || echo "    (already enabled, continuing)"

echo "==> Configuring PostgreSQL connection in Vault..."
vault write "${DB_MOUNT}/config/${DB_CONNECTION}" \
  plugin_name="postgresql-database-plugin" \
  allowed_roles="${DB_ROLE}" \
  connection_url="postgresql://{{username}}:{{password}}@127.0.0.1:5432/${PG_DB}?sslmode=disable" \
  username="vault_admin" \
  password="${PG_PASS}"

echo "==> Creating dynamic role '${DB_ROLE}'..."
vault write "${DB_MOUNT}/roles/${DB_ROLE}" \
  db_name="${DB_CONNECTION}" \
  creation_statements="
    CREATE ROLE \"{{name}}\"
      WITH LOGIN PASSWORD '{{password}}'
      VALID UNTIL '{{expiration}}';
    GRANT SELECT, INSERT, UPDATE, DELETE
      ON ALL TABLES IN SCHEMA public TO \"{{name}}\";
    GRANT USAGE, SELECT
      ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\";
  " \
  revocation_statements="
    REVOKE ALL ON ALL TABLES IN SCHEMA public FROM \"{{name}}\";
    REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM \"{{name}}\";
    DROP ROLE IF EXISTS \"{{name}}\";
  " \
  default_ttl="1h" \
  max_ttl="24h"

echo ""
echo "✓ Done. Test with:"
echo "  vault read ${DB_MOUNT}/creds/${DB_ROLE}"
echo ""
echo "Next: restart the api container to pick up dynamic credentials:"
echo "  docker compose restart api"
