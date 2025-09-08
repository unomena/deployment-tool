#!/bin/bash
# validate-django-environment.sh - Django Environment Validation Script
# 
# This script validates Django environment setup and database connectivity.
# Uses environment variables for configuration.
#
# Required Environment Variables:
#   DJANGO_SETTINGS_MODULE - Django settings module path
#   SECRET_KEY            - Django secret key
#   DB_NAME              - Database name
#   DB_USER              - Database user
#
# Optional Environment Variables:
#   PROJECT_PYTHON_PATH  - Path to PROJECT Python executable (required for Django operations)
#   DJANGO_PROJECT_DIR   - Django project directory (default: current directory)

set -e  # Exit on any error

# Default values - PROJECT_PYTHON_PATH is required and set by deployment orchestrator
DJANGO_PROJECT_DIR="${DJANGO_PROJECT_DIR:-.}"

# Source common logging utilities
source "$(dirname "$0")/logging-utils.sh"

# Validate PROJECT_PYTHON_PATH is provided
if [[ -z "${PROJECT_PYTHON_PATH}" ]]; then
    log_error "PROJECT_PYTHON_PATH is required but not set"
    log_error "This should be set by the deployment orchestrator"
    exit 1
fi

# Check required environment variables
check_required_vars() {
    local missing_vars=()
    
    if [[ -z "${DJANGO_SETTINGS_MODULE}" ]]; then
        missing_vars+=("DJANGO_SETTINGS_MODULE")
    fi
    
    if [[ -z "${SECRET_KEY}" ]]; then
        missing_vars+=("SECRET_KEY")
    fi
    
    if [[ -z "${DB_NAME}" ]]; then
        missing_vars+=("DB_NAME")
    fi
    
    if [[ -z "${DB_USER}" ]]; then
        missing_vars+=("DB_USER")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Required variables: DJANGO_SETTINGS_MODULE, SECRET_KEY, DB_NAME, DB_USER"
        log_error "PROJECT_PYTHON_PATH should be set by deployment orchestrator"
        exit 1
    fi
}

# Check Python executable
check_python() {
    log_info "Checking PROJECT Python executable: ${PROJECT_PYTHON_PATH}"
    
    if ! command -v "${PROJECT_PYTHON_PATH}" >/dev/null 2>&1; then
        log_error "PROJECT Python executable not found: ${PROJECT_PYTHON_PATH}"
        exit 1
    fi
    
    local python_version
    python_version=$(${PROJECT_PYTHON_PATH} --version 2>&1)
    log_info "Using PROJECT Python: ${python_version}"
}

# Validate Django environment variables
validate_environment_vars() {
    log_info "Validating Django environment variables..."
    
    local validation_script='
import os
import sys

# Check critical environment variables
required_vars = ["DJANGO_SETTINGS_MODULE", "SECRET_KEY", "DB_NAME", "DB_USER"]
missing_vars = [var for var in required_vars if not os.environ.get(var)]

if missing_vars:
    print(f"ERROR: Missing environment variables: {missing_vars}")
    sys.exit(1)

print("✓ All required environment variables are present")

# Display configuration summary
django_settings = os.environ.get("DJANGO_SETTINGS_MODULE")
db_name = os.environ.get("DB_NAME")
db_user = os.environ.get("DB_USER")
debug_mode = os.environ.get("DEBUG", "Not set")

print(f"Django Settings Module: {django_settings}")
print(f"Database Name: {db_name}")
print(f"Database User: {db_user}")
print(f"Debug Mode: {debug_mode}")
'
    
    if ! ${PROJECT_PYTHON_PATH} -c "${validation_script}"; then
        log_error "Environment variables validation failed"
        exit 1
    fi
    
    log_info "Environment variables validation passed"
}

# Test Django setup
test_django_setup() {
    log_info "Testing Django setup and configuration..."
    
    local django_test_script='
import os
import sys
import django
from django.conf import settings
from django.core.management import execute_from_command_line

try:
    # Test Django setup
    django.setup()
    print("✓ Django setup successful")
    
    # Test settings access
    secret_key = settings.SECRET_KEY
    if not secret_key:
        raise Exception("SECRET_KEY is empty")
    print("✓ Django settings accessible")
    
    # Test database configuration
    db_config = settings.DATABASES.get("default", {})
    if not db_config:
        raise Exception("No default database configuration found")
    print("✓ Database configuration found")
    
    db_engine = db_config.get("ENGINE", "Unknown")
    db_name = db_config.get("NAME", "Unknown")
    print(f"Database Engine: {db_engine}")
    print(f"Database Name: {db_name}")
    
except Exception as e:
    print(f"ERROR: Django setup failed: {e}")
    sys.exit(1)
'
    
    cd "${DJANGO_PROJECT_DIR}"
    
    # Add the src directory to Python path for Django imports
    export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
    
    # Create logs directory if it doesn't exist
    mkdir -p "${DJANGO_PROJECT_DIR}/src/logs"
    
    if ! ${PROJECT_PYTHON_PATH} -c "${django_test_script}"; then
        log_error "Django setup test failed"
        exit 1
    fi
    
    log_info "Django setup test passed"
}

# Test database connection
test_database_connection() {
    log_info "Testing database connection..."
    
    local db_test_script='
import os
import sys
import django
from django.db import connection
from django.core.management import execute_from_command_line

try:
    # Setup Django
    django.setup()
    
    # Test database connection
    with connection.cursor() as cursor:
        cursor.execute("SELECT 1")
        result = cursor.fetchone()
        if result and result[0] == 1:
            print("✓ Database connection successful")
        else:
            raise Exception("Database query returned unexpected result")
    
    # Get database info
    db_vendor = connection.vendor
    db_name = connection.settings_dict.get("NAME", "Unknown")
    print(f"Database Vendor: {db_vendor}")
    print(f"Connected to: {db_name}")
    
except Exception as e:
    print(f"ERROR: Database connection failed: {e}")
    sys.exit(1)
'
    
    cd "${DJANGO_PROJECT_DIR}"
    
    if ! ${PROJECT_PYTHON_PATH} -c "${db_test_script}"; then
        log_error "Database connection test failed"
        exit 1
    fi
    
    log_info "Database connection test passed"
}

# Check Django management commands
test_django_management() {
    log_info "Testing Django management command access..."
    
    cd "${DJANGO_PROJECT_DIR}"
    
    # Test manage.py access - check both root and src directory
        # Add src directory to Python path and change to src directory
        export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
        cd "${DJANGO_PROJECT_DIR}/src"
    else
        log_error "manage.py not found in ${DJANGO_PROJECT_DIR} or ${DJANGO_PROJECT_DIR}/src"
        exit 1
    fi
    
    # Test help command (should not fail)
    if ! ${PROJECT_PYTHON_PATH} manage.py check --deploy 2>/dev/null; then
        log_info "✓ Django management commands accessible"
    else
        log_warn "Django management commands may have issues"
    fi
}

# Check installed packages
check_django_packages() {
    log_info "Checking Django installation..."
    
    local package_check_script='
import sys
import django

try:
    print(f"✓ Django version: {django.get_version()}")
    
    # Check for common Django packages
    packages_to_check = [
        "django.contrib.admin",
        "django.contrib.auth", 
        "django.contrib.contenttypes",
        "django.contrib.sessions",
        "django.db",
    ]
    
    for package in packages_to_check:
        try:
            __import__(package)
            print(f"✓ {package} available")
        except ImportError:
            print(f"⚠ {package} not available")
            
except ImportError:
    print("ERROR: Django is not installed or not accessible")
    sys.exit(1)
'
    
    if ! ${PROJECT_PYTHON_PATH} -c "${package_check_script}"; then
        log_error "Django package check failed"
        exit 1
    fi
    
    log_info "Django package check passed"
}

# Main execution function
main() {
    log_info "Starting Django environment validation"
    log_info "Project directory: ${DJANGO_PROJECT_DIR}"
    log_info "Python executable: ${PROJECT_PYTHON_PATH}"
    
    # Run all checks
    check_required_vars
    check_python
    check_django_packages
    validate_environment_vars
    test_django_setup
    test_database_connection
    test_django_management
    
    log_info "🎉 Django environment validation completed successfully"
}

# Help function
show_help() {
    cat << EOF
validate-django-environment.sh - Django Environment Validation Script

DESCRIPTION:
    This script validates Django environment setup, configuration, and database connectivity.
    It performs comprehensive checks to ensure Django is properly configured and ready for use.

REQUIRED ENVIRONMENT VARIABLES:
    DJANGO_SETTINGS_MODULE  Django settings module (e.g., project.settings)
    SECRET_KEY             Django secret key
    DB_NAME               Database name
    DB_USER               Database user

OPTIONAL ENVIRONMENT VARIABLES:
    PYTHON_PATH           Path to Python executable (default: python)
    DJANGO_PROJECT_DIR    Django project directory (default: current directory)
    DEBUG                 Django debug mode setting (for display only)

USAGE:
    # Set environment variables
    export DJANGO_SETTINGS_MODULE="project.settings"
    export SECRET_KEY="your-secret-key"
    export DB_NAME="myapp_db"
    export DB_USER="myapp_user"
    
    # Run the script
    ./validate-django-environment.sh

    # Or with custom Python/directory
    export PYTHON_PATH="/path/to/venv/bin/python"
    export DJANGO_PROJECT_DIR="/path/to/project"
    ./validate-django-environment.sh

CHECKS PERFORMED:
    ✓ Environment variables validation
    ✓ Python executable availability
    ✓ Django installation and version
    ✓ Django setup and configuration
    ✓ Database connection test
    ✓ Management commands accessibility

EXIT CODES:
    0  Success - All validations passed
    1  Error - One or more validations failed

EXAMPLES:
    # Basic validation
    DJANGO_SETTINGS_MODULE=project.settings SECRET_KEY=key DB_NAME=db DB_USER=user ./validate-django-environment.sh
    
    # With virtual environment
    PYTHON_PATH=venv/bin/python DJANGO_SETTINGS_MODULE=project.settings SECRET_KEY=key DB_NAME=db DB_USER=user ./validate-django-environment.sh
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
