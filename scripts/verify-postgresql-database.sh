#!/bin/bash
# verify-postgresql-database.sh - PostgreSQL Database Verification and Creation Script
# 
# This script checks if a PostgreSQL database exists and creates it if needed.
# Uses root credentials from configuration for database creation and application
# credentials for runtime access.
#
# Required Environment Variables:
#   DB_HOST     - PostgreSQL host (default: localhost)
#   DB_PORT     - PostgreSQL port (default: 5432)
#   DB_NAME     - Database name to verify/create
#   DB_USER     - Database user to create/use (application user)
#   DB_PASSWORD - Database user password (application password)
#
# Optional Environment Variables:
#   DB_SERVERS_CONFIG - Path to database servers configuration file
#   POSTGRES_USER - PostgreSQL superuser (will be loaded from config if not set)

set -e  # Exit on any error

# Default values
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common logging utilities
source "$(dirname "$0")/logging-utils.sh"

# Load root credentials from configuration
load_root_credentials() {
    log_info "Loading database root credentials from configuration..."
    
    # Check if manage-database-credentials.py exists
    if [[ ! -f "${SCRIPT_DIR}/manage-database-credentials.py" ]]; then
        log_error "manage-database-credentials.py not found in ${SCRIPT_DIR}"
        exit 1
    fi
    
    # Load root credentials using the credentials manager
    local credentials_output
    if ! credentials_output=$(DB_HOST="${DB_HOST}" python3 "${SCRIPT_DIR}/manage-database-credentials.py" 2>/dev/null); then
        log_error "Failed to load root credentials from configuration"
        exit 1
    fi
    
    # Source the exported variables
    eval "${credentials_output}"
    
    # Use root credentials for administrative operations
    if [[ -n "${DB_ROOT_USER}" ]]; then
        POSTGRES_USER="${DB_ROOT_USER}"
        POSTGRES_PASSWORD="${DB_ROOT_PASSWORD}"
        log_info "Using root user '${POSTGRES_USER}' from configuration"
    else
        log_error "Failed to load root credentials from configuration"
        exit 1
    fi
}

# Check required environment variables
check_required_vars() {
    local missing_vars=()
    
    if [[ -z "${DB_NAME}" ]]; then
        missing_vars+=("DB_NAME")
    fi
    
    if [[ -z "${DB_USER}" ]]; then
        missing_vars+=("DB_USER")
    fi
    
    if [[ -z "${DB_PASSWORD}" ]]; then
        missing_vars+=("DB_PASSWORD")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Required variables: DB_NAME, DB_USER, DB_PASSWORD"
        log_error "Optional variables: DB_HOST (default: localhost), DB_PORT (default: 5432), POSTGRES_USER (default: postgres)"
        exit 1
    fi
}

# Check if PostgreSQL is running and accessible
check_postgresql_connection() {
    log_info "Checking PostgreSQL connection to ${DB_HOST}:${DB_PORT}..."
    
    if ! pg_isready -h "${DB_HOST}" -p "${DB_PORT}" >/dev/null 2>&1; then
        log_error "PostgreSQL is not running or not accessible at ${DB_HOST}:${DB_PORT}"
        log_error "Please ensure PostgreSQL is installed and running"
        exit 1
    fi
    
    log_info "PostgreSQL service is running and accessible"
    
    # Load root credentials after confirming PostgreSQL is accessible
    load_root_credentials
}

# Check if database exists
database_exists() {
    local db_exists
    export PGPASSWORD="${POSTGRES_PASSWORD}"
    db_exists=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" 2>/dev/null || echo "0")
    unset PGPASSWORD
    
    if [[ "${db_exists}" == "1" ]]; then
        return 0  # Database exists
    else
        return 1  # Database does not exist
    fi
}

# Check if user exists
user_exists() {
    local user_exists
    export PGPASSWORD="${POSTGRES_PASSWORD}"
    user_exists=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" 2>/dev/null || echo "0")
    unset PGPASSWORD
    
    if [[ "${user_exists}" == "1" ]]; then
        return 0  # User exists
    else
        return 1  # User does not exist
    fi
}

# Create database user
create_database_user() {
    log_info "Creating database user: ${DB_USER}"
    
    if user_exists; then
        log_warn "Database user '${DB_USER}' already exists"
    else
        export PGPASSWORD="${POSTGRES_PASSWORD}"
        if psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -c "CREATE USER \"${DB_USER}\" WITH PASSWORD '${DB_PASSWORD}';" >/dev/null 2>&1; then
            log_info "Database user '${DB_USER}' created successfully"
        else
            log_error "Failed to create database user '${DB_USER}'"
            unset PGPASSWORD
            exit 1
        fi
        unset PGPASSWORD
    fi
}

# Create database
create_database() {
    log_info "Creating database: ${DB_NAME}"
    
    export PGPASSWORD="${POSTGRES_PASSWORD}"
    if psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -c "CREATE DATABASE \"${DB_NAME}\" OWNER \"${DB_USER}\";" >/dev/null 2>&1; then
        log_info "Database '${DB_NAME}' created successfully"
    else
        log_error "Failed to create database '${DB_NAME}'"
        unset PGPASSWORD
        exit 1
    fi
    unset PGPASSWORD
}

# Grant necessary privileges
grant_privileges() {
    log_info "Granting privileges to user '${DB_USER}' on database '${DB_NAME}'"
    
    export PGPASSWORD="${POSTGRES_PASSWORD}"
    
    # Grant all privileges on database
    if psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -c "GRANT ALL PRIVILEGES ON DATABASE \"${DB_NAME}\" TO \"${DB_USER}\";" >/dev/null 2>&1; then
        log_info "Database privileges granted"
    else
        log_warn "Failed to grant database privileges (may already exist)"
    fi
    
    # Connect to the database and grant schema privileges
    if psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -d "${DB_NAME}" -c "GRANT ALL ON SCHEMA public TO \"${DB_USER}\";" >/dev/null 2>&1; then
        log_info "Schema privileges granted"
    else
        log_warn "Failed to grant schema privileges (may already exist)"
    fi
    
    # Grant CREATE on schema public (PostgreSQL 15+ requirement)
    if psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -d "${DB_NAME}" -c "GRANT CREATE ON SCHEMA public TO \"${DB_USER}\";" >/dev/null 2>&1; then
        log_info "CREATE privilege on schema granted"
    else
        log_warn "Failed to grant CREATE privilege (may already exist)"
    fi
    
    # Grant default privileges for new tables and sequences
    if psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -d "${DB_NAME}" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO \"${DB_USER}\"; ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO \"${DB_USER}\";" >/dev/null 2>&1; then
        log_info "Default privileges granted for future tables and sequences"
    else
        log_warn "Failed to grant default privileges (may already exist)"
    fi
    
    # For PostgreSQL 15+, we may need to grant the role to our superuser
    if psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -c "GRANT \"${DB_USER}\" TO \"${POSTGRES_USER}\";" >/dev/null 2>&1; then
        log_info "Granted ${DB_USER} role to ${POSTGRES_USER}"
    fi
    
    # Make the user owner of the database and schema for full control
    if psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -d "${DB_NAME}" -c "ALTER DATABASE \"${DB_NAME}\" OWNER TO \"${DB_USER}\"; ALTER SCHEMA public OWNER TO \"${DB_USER}\";" >/dev/null 2>&1; then
        log_info "Ownership transferred to ${DB_USER}"
    else
        log_warn "Could not transfer ownership (this is okay if not needed)"
    fi
    
    unset PGPASSWORD
}

# Test database connection with created user
test_user_connection() {
    log_info "Testing database connection with user '${DB_USER}'"
    
    # Set PGPASSWORD for the test connection
    export PGPASSWORD="${DB_PASSWORD}"
    
    if psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1;" >/dev/null 2>&1; then
        log_info "Database connection test successful"
    else
        log_error "Database connection test failed"
        exit 1
    fi
    
    # Unset PGPASSWORD
    unset PGPASSWORD
}

# Ensure PostgreSQL superuser has necessary permissions
ensure_superuser_permissions() {
    log_info "Ensuring PostgreSQL superuser has necessary permissions..."
    
    # Check if we can create roles
    export PGPASSWORD="${POSTGRES_PASSWORD}"
    local can_create_role=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -tAc "SELECT rolcreaterole FROM pg_roles WHERE rolname='${POSTGRES_USER}';" 2>/dev/null || echo "f")
    local can_create_db=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -tAc "SELECT rolcreatedb FROM pg_roles WHERE rolname='${POSTGRES_USER}';" 2>/dev/null || echo "f")
    unset PGPASSWORD
    
    if [[ "${can_create_role}" != "t" ]] || [[ "${can_create_db}" != "t" ]]; then
        log_warn "PostgreSQL user '${POSTGRES_USER}' lacks necessary permissions"
        log_warn "Please ensure the root user has CREATEROLE and CREATEDB permissions"
    else
        log_info "PostgreSQL user '${POSTGRES_USER}' has necessary permissions"
    fi
}

# Main execution function
main() {
    log_info "Starting PostgreSQL database verification and setup"
    log_info "Database: ${DB_NAME} | User: ${DB_USER} | Host: ${DB_HOST}:${DB_PORT}"
    
    # Check required variables
    check_required_vars
    
    # Check PostgreSQL connection
    check_postgresql_connection
    
    # Ensure superuser has necessary permissions
    ensure_superuser_permissions
    
    # Check if database exists
    if database_exists; then
        log_info "Database '${DB_NAME}' already exists"
    else
        log_info "Database '${DB_NAME}' does not exist, creating..."
        
        # Create user first (if needed)
        create_database_user
        
        # Create database
        create_database
        
        # Grant privileges
        grant_privileges
        
        log_info "Database setup completed successfully"
    fi
    
    # Test the connection
    test_user_connection
    
    log_info "PostgreSQL database verification completed successfully"
}

# Help function
show_help() {
    cat << EOF
verify-postgresql-database.sh - PostgreSQL Database Verification and Creation Script

DESCRIPTION:
    This script verifies that a PostgreSQL database exists and creates it if needed.
    It also ensures the specified database user exists with proper permissions.

REQUIRED ENVIRONMENT VARIABLES:
    DB_NAME      Database name to verify/create
    DB_USER      Database user to create/use
    DB_PASSWORD  Database user password

OPTIONAL ENVIRONMENT VARIABLES:
    DB_HOST      PostgreSQL host (default: localhost)
    DB_PORT      PostgreSQL port (default: 5432)
    POSTGRES_USER PostgreSQL superuser (default: postgres)

USAGE:
    # Set environment variables
    export DB_NAME="myapp_db"
    export DB_USER="myapp_user"
    export DB_PASSWORD="secure_password"
    
    # Run the script
    ./verify-postgresql-database.sh

    # Or with custom host/port
    export DB_HOST="db.example.com"
    export DB_PORT="5433"
    ./verify-postgresql-database.sh

EXIT CODES:
    0  Success
    1  Error (missing variables, connection failed, etc.)

EXAMPLES:
    # Basic usage
    DB_NAME=myapp DB_USER=myuser DB_PASSWORD=mypass ./verify-postgresql-database.sh
    
    # With custom PostgreSQL connection
    DB_HOST=pg.example.com DB_NAME=myapp DB_USER=myuser DB_PASSWORD=mypass ./verify-postgresql-database.sh
EOF
}

# Handle command line arguments
case "${1:-}" in
    -h|--help|help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
