#!/bin/bash
# verify-postgresql-database.sh - PostgreSQL Database Verification and Creation Script
# 
# This script checks if a PostgreSQL database exists and creates it if needed.
# Uses environment variables for configuration.
#
# Required Environment Variables:
#   DB_HOST     - PostgreSQL host (default: localhost)
#   DB_PORT     - PostgreSQL port (default: 5432)
#   DB_NAME     - Database name to verify/create
#   DB_USER     - Database user to create/use
#   DB_PASSWORD - Database user password
#   POSTGRES_USER - PostgreSQL superuser (default: postgres)

set -e  # Exit on any error

# Default values
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
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
    
    if ! pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" >/dev/null 2>&1; then
        log_error "PostgreSQL is not running or not accessible at ${DB_HOST}:${DB_PORT}"
        log_error "Please ensure PostgreSQL is installed and running"
        exit 1
    fi
    
    log_info "PostgreSQL service is running and accessible"
}

# Check if database exists
database_exists() {
    local db_exists
    db_exists=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" 2>/dev/null || echo "0")
    
    if [[ "${db_exists}" == "1" ]]; then
        return 0  # Database exists
    else
        return 1  # Database does not exist
    fi
}

# Check if user exists
user_exists() {
    local user_exists
    user_exists=$(psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" 2>/dev/null || echo "0")
    
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
        if psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -c "CREATE USER \"${DB_USER}\" WITH PASSWORD '${DB_PASSWORD}';" >/dev/null 2>&1; then
            log_info "Database user '${DB_USER}' created successfully"
        else
            log_error "Failed to create database user '${DB_USER}'"
            exit 1
        fi
    fi
}

# Create database
create_database() {
    log_info "Creating database: ${DB_NAME}"
    
    if psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -c "CREATE DATABASE \"${DB_NAME}\" OWNER \"${DB_USER}\";" >/dev/null 2>&1; then
        log_info "Database '${DB_NAME}' created successfully"
    else
        log_error "Failed to create database '${DB_NAME}'"
        exit 1
    fi
}

# Grant necessary privileges
grant_privileges() {
    log_info "Granting privileges to user '${DB_USER}' on database '${DB_NAME}'"
    
    # Grant connection privileges
    if psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -c "GRANT CONNECT ON DATABASE \"${DB_NAME}\" TO \"${DB_USER}\";" >/dev/null 2>&1; then
        log_info "Connection privileges granted"
    else
        log_warn "Failed to grant connection privileges (may already exist)"
    fi
    
    # Connect to the database and grant schema privileges
    if psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${POSTGRES_USER}" -d "${DB_NAME}" -c "GRANT ALL PRIVILEGES ON SCHEMA public TO \"${DB_USER}\";" >/dev/null 2>&1; then
        log_info "Schema privileges granted"
    else
        log_warn "Failed to grant schema privileges (may already exist)"
    fi
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

# Main execution function
main() {
    log_info "Starting PostgreSQL database verification and setup"
    log_info "Database: ${DB_NAME} | User: ${DB_USER} | Host: ${DB_HOST}:${DB_PORT}"
    
    # Check required variables
    check_required_vars
    
    # Check PostgreSQL connection
    check_postgresql_connection
    
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
