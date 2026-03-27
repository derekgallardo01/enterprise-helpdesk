#!/usr/bin/env bash
# Provision Azure SQL database for Enterprise Help Desk reporting warehouse.
# Prerequisites: Azure CLI installed and logged in (az login).
#
# Usage:
#   ./provision.sh
#
# Environment variables (required):
#   HELPDESK_RG           - Resource group name
#   HELPDESK_LOCATION     - Azure region (e.g., eastus2)
#   HELPDESK_SQL_SERVER   - Desired SQL server name (globally unique)
#   HELPDESK_SQL_DB       - Database name (default: helpdesk-reporting)
#   HELPDESK_SQL_ADMIN    - SQL admin username
#   HELPDESK_SQL_PASSWORD - SQL admin password
#   HELPDESK_MI_NAME      - Managed identity name for the Functions app

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
HELPDESK_SQL_DB="${HELPDESK_SQL_DB:-helpdesk-reporting}"

echo "=== Enterprise Help Desk SQL Provisioning ==="

# -------------------------------------------------------
# 1. Create SQL Server (if not exists)
# -------------------------------------------------------
echo "Checking if SQL server '${HELPDESK_SQL_SERVER}' exists..."
if ! az sql server show \
    --resource-group "${HELPDESK_RG}" \
    --name "${HELPDESK_SQL_SERVER}" \
    --output none 2>/dev/null; then

    echo "Creating SQL server '${HELPDESK_SQL_SERVER}'..."
    az sql server create \
        --resource-group "${HELPDESK_RG}" \
        --name "${HELPDESK_SQL_SERVER}" \
        --location "${HELPDESK_LOCATION}" \
        --admin-user "${HELPDESK_SQL_ADMIN}" \
        --admin-password "${HELPDESK_SQL_PASSWORD}" \
        --output none

    # Allow Azure services to access the server
    az sql server firewall-rule create \
        --resource-group "${HELPDESK_RG}" \
        --server "${HELPDESK_SQL_SERVER}" \
        --name "AllowAzureServices" \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0 \
        --output none

    echo "SQL server created."
else
    echo "SQL server already exists. Skipping creation."
fi

# -------------------------------------------------------
# 2. Create SQL Database (if not exists)
# -------------------------------------------------------
echo "Checking if database '${HELPDESK_SQL_DB}' exists..."
if ! az sql db show \
    --resource-group "${HELPDESK_RG}" \
    --server "${HELPDESK_SQL_SERVER}" \
    --name "${HELPDESK_SQL_DB}" \
    --output none 2>/dev/null; then

    echo "Creating database '${HELPDESK_SQL_DB}'..."
    az sql db create \
        --resource-group "${HELPDESK_RG}" \
        --server "${HELPDESK_SQL_SERVER}" \
        --name "${HELPDESK_SQL_DB}" \
        --edition GeneralPurpose \
        --family Gen5 \
        --capacity 2 \
        --compute-model Serverless \
        --auto-pause-delay 60 \
        --output none

    echo "Database created."
else
    echo "Database already exists. Skipping creation."
fi

# Build the FQDN for sqlcmd
SQL_FQDN="${HELPDESK_SQL_SERVER}.database.windows.net"

# -------------------------------------------------------
# 3. Run schema scripts in order
# -------------------------------------------------------
echo "Running schema.sql..."
sqlcmd -S "${SQL_FQDN}" \
    -d "${HELPDESK_SQL_DB}" \
    -U "${HELPDESK_SQL_ADMIN}" \
    -P "${HELPDESK_SQL_PASSWORD}" \
    -i "${SCRIPT_DIR}/schema.sql" \
    -b

echo "Running 001-add-sync-state.sql..."
sqlcmd -S "${SQL_FQDN}" \
    -d "${HELPDESK_SQL_DB}" \
    -U "${HELPDESK_SQL_ADMIN}" \
    -P "${HELPDESK_SQL_PASSWORD}" \
    -i "${SCRIPT_DIR}/migrations/001-add-sync-state.sql" \
    -b

echo "Running seed-date-dim.sql..."
sqlcmd -S "${SQL_FQDN}" \
    -d "${HELPDESK_SQL_DB}" \
    -U "${HELPDESK_SQL_ADMIN}" \
    -P "${HELPDESK_SQL_PASSWORD}" \
    -i "${SCRIPT_DIR}/seed-date-dim.sql" \
    -b

echo "Running aggregation-sprocs.sql..."
sqlcmd -S "${SQL_FQDN}" \
    -d "${HELPDESK_SQL_DB}" \
    -U "${HELPDESK_SQL_ADMIN}" \
    -P "${HELPDESK_SQL_PASSWORD}" \
    -i "${SCRIPT_DIR}/aggregation-sprocs.sql" \
    -b

# -------------------------------------------------------
# 4. Create managed identity user for Functions app
# -------------------------------------------------------
echo "Creating managed identity database user for '${HELPDESK_MI_NAME}'..."
sqlcmd -S "${SQL_FQDN}" \
    -d "${HELPDESK_SQL_DB}" \
    -U "${HELPDESK_SQL_ADMIN}" \
    -P "${HELPDESK_SQL_PASSWORD}" \
    -b \
    -Q "
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '${HELPDESK_MI_NAME}')
BEGIN
    CREATE USER [${HELPDESK_MI_NAME}] FROM EXTERNAL PROVIDER;
END;
ALTER ROLE db_datareader ADD MEMBER [${HELPDESK_MI_NAME}];
ALTER ROLE db_datawriter ADD MEMBER [${HELPDESK_MI_NAME}];
GRANT EXECUTE TO [${HELPDESK_MI_NAME}];
"

echo ""
echo "=== Provisioning complete ==="
echo "Server:   ${SQL_FQDN}"
echo "Database: ${HELPDESK_SQL_DB}"
echo "Identity: ${HELPDESK_MI_NAME} (db_datareader, db_datawriter, EXECUTE)"
