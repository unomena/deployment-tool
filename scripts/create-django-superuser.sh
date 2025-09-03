#!/bin/bash
# create-django-superuser.sh - Django Superuser Creation Script
# 
# This script creates a Django superuser if it doesn't already exist.
# Uses environment variables for configuration.
#
# Required Environment Variables:
#   DEFAULT_SUPERUSER_USERNAME - Superuser username
#   DEFAULT_SUPERUSER_EMAIL    - Superuser email
#   DEFAULT_SUPERUSER_PASSWORD - Superuser password
#
# Optional Environment Variables:
#   PROJECT_PYTHON_PATH  - Path to PROJECT Python executable (required for Django operations)
#   DJANGO_PROJECT_DIR   - Django project directory (default: current directory)
#   DJANGO_SETTINGS_MODULE - Django settings module (should be set)

set -e  # Exit on any error

# Default values - PROJECT_PYTHON_PATH is required and set by deployment orchestrator
DJANGO_PROJECT_DIR="${DJANGO_PROJECT_DIR:-.}"

# Validate PROJECT_PYTHON_PATH is provided
if [[ -z "${PROJECT_PYTHON_PATH}" ]]; then
    echo -e "\033[0;31m[ERROR]\033[0m PROJECT_PYTHON_PATH is required but not set"
    echo -e "\033[0;31m[ERROR]\033[0m This should be set by the deployment orchestrator"
    exit 1
fi

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
    
    if [[ -z "${DEFAULT_SUPERUSER_USERNAME}" ]]; then
        missing_vars+=("DEFAULT_SUPERUSER_USERNAME")
    fi
    
    if [[ -z "${DEFAULT_SUPERUSER_EMAIL}" ]]; then
        missing_vars+=("DEFAULT_SUPERUSER_EMAIL")
    fi
    
    if [[ -z "${DEFAULT_SUPERUSER_PASSWORD}" ]]; then
        missing_vars+=("DEFAULT_SUPERUSER_PASSWORD")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Required variables: DEFAULT_SUPERUSER_USERNAME, DEFAULT_SUPERUSER_EMAIL, DEFAULT_SUPERUSER_PASSWORD"
        log_error "PROJECT_PYTHON_PATH should be set by deployment orchestrator"
        exit 1
    fi
}

# Validate email format
validate_email() {
    local email="$1"
    local email_regex="^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"
    
    if [[ ! $email =~ $email_regex ]]; then
        log_error "Invalid email format: $email"
        exit 1
    fi
}

# Check Python and Django availability
check_django_availability() {
    log_info "Checking PROJECT Python and Django availability..."
    
    if ! command -v "${PROJECT_PYTHON_PATH}" >/dev/null 2>&1; then
        log_error "PROJECT Python executable not found: ${PROJECT_PYTHON_PATH}"
        exit 1
    fi
    
    local python_version
    python_version=$(${PROJECT_PYTHON_PATH} --version 2>&1)
    log_info "Using PROJECT Python: ${python_version}"
    
    # Check Django availability
    local django_check_script='
import sys
try:
    import django
    print(f"Django {django.get_version()} available")
except ImportError:
    print("ERROR: Django not available")
    sys.exit(1)
'
    
    cd "${DJANGO_PROJECT_DIR}"
    
    if ! ${PROJECT_PYTHON_PATH} -c "${django_check_script}"; then
        log_error "Django is not available"
        exit 1
    fi
}

# Check if superuser already exists
superuser_exists() {
    log_info "Checking if superuser '${DEFAULT_SUPERUSER_USERNAME}' already exists..."
    
    local user_check_script='
import os
import sys
import django

try:
    django.setup()
    from django.contrib.auth import get_user_model
    
    User = get_user_model()
    username = os.environ.get("DEFAULT_SUPERUSER_USERNAME")
    
    if User.objects.filter(username=username).exists():
        print("EXISTS")
    else:
        print("NOT_EXISTS")
        
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
'
    
    cd "${DJANGO_PROJECT_DIR}"
    
    local result
    result=$(${PROJECT_PYTHON_PATH} -c "${user_check_script}")
    
    case "$result" in
        "EXISTS")
            return 0  # User exists
            ;;
        "NOT_EXISTS")
            return 1  # User does not exist
            ;;
        "ERROR:"*)
            log_error "Failed to check superuser existence: ${result#ERROR: }"
            exit 1
            ;;
        *)
            log_error "Unexpected result from superuser check: $result"
            exit 1
            ;;
    esac
}

# Create superuser
create_superuser() {
    log_info "Creating superuser '${DEFAULT_SUPERUSER_USERNAME}'..."
    
    local superuser_creation_script='
import os
import sys
import django

try:
    django.setup()
    from django.contrib.auth import get_user_model
    
    User = get_user_model()
    
    username = os.environ.get("DEFAULT_SUPERUSER_USERNAME")
    email = os.environ.get("DEFAULT_SUPERUSER_EMAIL")
    password = os.environ.get("DEFAULT_SUPERUSER_PASSWORD")
    
    # Create superuser
    user = User.objects.create_superuser(username, email, password)
    
    print(f"✓ Superuser created successfully")
    print(f"Username: {username}")
    print(f"Email: {email}")
    print(f"User ID: {user.id}")
    
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
'
    
    cd "${DJANGO_PROJECT_DIR}"
    
    if ! ${PROJECT_PYTHON_PATH} -c "${superuser_creation_script}"; then
        log_error "Failed to create superuser"
        exit 1
    fi
    
    log_info "Superuser created successfully"
}

# Verify superuser creation
verify_superuser() {
    log_info "Verifying superuser creation..."
    
    local verification_script='
import os
import sys
import django

try:
    django.setup()
    from django.contrib.auth import get_user_model
    
    User = get_user_model()
    username = os.environ.get("DEFAULT_SUPERUSER_USERNAME")
    
    try:
        user = User.objects.get(username=username)
        
        print(f"✓ Superuser found: {user.username}")
        print(f"Email: {user.email}")
        print(f"Is superuser: {user.is_superuser}")
        print(f"Is staff: {user.is_staff}")
        print(f"Is active: {user.is_active}")
        print(f"Date joined: {user.date_joined}")
        
        if not user.is_superuser:
            print("WARNING: User exists but is not a superuser")
            sys.exit(1)
            
        if not user.is_active:
            print("WARNING: User exists but is not active")
            sys.exit(1)
            
    except User.DoesNotExist:
        print("ERROR: Superuser not found after creation")
        sys.exit(1)
        
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
'
    
    cd "${DJANGO_PROJECT_DIR}"
    
    if ! ${PROJECT_PYTHON_PATH} -c "${verification_script}"; then
        log_error "Superuser verification failed"
        exit 1
    fi
    
    log_info "Superuser verification passed"
}

# Test superuser login capability
test_superuser_authentication() {
    log_info "Testing superuser authentication..."
    
    local auth_test_script='
import os
import sys
import django

try:
    django.setup()
    from django.contrib.auth import authenticate
    
    username = os.environ.get("DEFAULT_SUPERUSER_USERNAME")
    password = os.environ.get("DEFAULT_SUPERUSER_PASSWORD")
    
    user = authenticate(username=username, password=password)
    
    if user is not None:
        if user.is_active and user.is_superuser:
            print("✓ Superuser authentication successful")
        else:
            print("ERROR: User authenticated but lacks superuser privileges")
            sys.exit(1)
    else:
        print("ERROR: Superuser authentication failed")
        sys.exit(1)
        
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
'
    
    cd "${DJANGO_PROJECT_DIR}"
    
    if ! ${PROJECT_PYTHON_PATH} -c "${auth_test_script}"; then
        log_error "Superuser authentication test failed"
        exit 1
    fi
    
    log_info "Superuser authentication test passed"
}

# Main execution function
main() {
    log_info "Starting Django superuser creation process"
    log_info "Username: ${DEFAULT_SUPERUSER_USERNAME}"
    log_info "Email: ${DEFAULT_SUPERUSER_EMAIL}"
    log_info "Project directory: ${DJANGO_PROJECT_DIR}"
    
    # Run all checks and operations
    check_required_vars
    validate_email "${DEFAULT_SUPERUSER_EMAIL}"
    check_django_availability
    
    # Check if superuser already exists
    if superuser_exists; then
        log_info "Superuser '${DEFAULT_SUPERUSER_USERNAME}' already exists"
        verify_superuser
        test_superuser_authentication
        log_info "✓ Existing superuser validation completed"
    else
        log_info "Superuser '${DEFAULT_SUPERUSER_USERNAME}' does not exist, creating..."
        create_superuser
        verify_superuser
        test_superuser_authentication
        log_info "🎉 Superuser creation completed successfully"
    fi
}

# Help function
show_help() {
    cat << EOF
create-django-superuser.sh - Django Superuser Creation Script

DESCRIPTION:
    This script creates a Django superuser if it doesn't already exist.
    It performs validation, creation, and verification of the superuser account.

REQUIRED ENVIRONMENT VARIABLES:
    DEFAULT_SUPERUSER_USERNAME  Superuser username
    DEFAULT_SUPERUSER_EMAIL     Superuser email address
    DEFAULT_SUPERUSER_PASSWORD  Superuser password

OPTIONAL ENVIRONMENT VARIABLES:
    PROJECT_PYTHON_PATH   Path to PROJECT Python executable (set by deployment orchestrator)
    DJANGO_PROJECT_DIR    Django project directory (default: current directory)
    DJANGO_SETTINGS_MODULE Django settings module (should be set)

USAGE:
    # Set environment variables
    export DEFAULT_SUPERUSER_USERNAME="admin"
    export DEFAULT_SUPERUSER_EMAIL="admin@example.com"
    export DEFAULT_SUPERUSER_PASSWORD="secure_password"
    
    # Run the script
    ./create-django-superuser.sh

    # Or with custom Python/directory
    export PYTHON_PATH="/path/to/venv/bin/python"
    export DJANGO_PROJECT_DIR="/path/to/project"
    ./create-django-superuser.sh

OPERATIONS PERFORMED:
    ✓ Environment variables validation
    ✓ Email format validation
    ✓ Django availability check
    ✓ Existing superuser check
    ✓ Superuser creation (if needed)
    ✓ Superuser verification
    ✓ Authentication test

EXIT CODES:
    0  Success - Superuser exists or was created successfully
    1  Error - Validation failed or creation unsuccessful

EXAMPLES:
    # Basic superuser creation
    DEFAULT_SUPERUSER_USERNAME=admin DEFAULT_SUPERUSER_EMAIL=admin@example.com DEFAULT_SUPERUSER_PASSWORD=password ./create-django-superuser.sh
    
    # With virtual environment
    PYTHON_PATH=venv/bin/python DEFAULT_SUPERUSER_USERNAME=admin DEFAULT_SUPERUSER_EMAIL=admin@example.com DEFAULT_SUPERUSER_PASSWORD=password ./create-django-superuser.sh
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
