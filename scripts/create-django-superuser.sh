#!/bin/bash
# create-django-superuser.sh - Django Superuser Creation Script
# 
# This script creates a Django superuser if it doesn't already exist.
# Uses environment variables for configuration.

# Source logging utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging-utils.sh"

# Default values
DEFAULT_SUPERUSER_USERNAME="${DEFAULT_SUPERUSER_USERNAME:-admin}"
DEFAULT_SUPERUSER_EMAIL="${DEFAULT_SUPERUSER_EMAIL:-admin@example.com}"
DEFAULT_SUPERUSER_PASSWORD="${DEFAULT_SUPERUSER_PASSWORD:-changeme}"

# Environment variables (set by deployment orchestrator)
PROJECT_PYTHON_PATH="${PROJECT_PYTHON_PATH:-python3}"
DJANGO_PROJECT_DIR="${DJANGO_PROJECT_DIR:-$(pwd)}"

# Validate required environment variables
validate_environment() {
    log_info "Validating environment variables..."
    
    local required_vars=(
        "DEFAULT_SUPERUSER_USERNAME"
        "DEFAULT_SUPERUSER_EMAIL" 
        "DEFAULT_SUPERUSER_PASSWORD"
        "PROJECT_PYTHON_PATH"
        "DJANGO_PROJECT_DIR"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
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
    
    # Check for custom DJANGO_MANAGE_MODULE path first
    if [[ -n "${DJANGO_MANAGE_MODULE:-}" ]]; then
        log_info "Using custom Django manage module: ${DJANGO_MANAGE_MODULE}"
        # Extract directory from the manage module path
        local manage_dir=$(dirname "${DJANGO_PROJECT_DIR}${DJANGO_MANAGE_MODULE}")
        local manage_file=$(basename "${DJANGO_MANAGE_MODULE}")
        
        if [[ -f "${DJANGO_PROJECT_DIR}${DJANGO_MANAGE_MODULE}" ]]; then
            # Add src directory to Python path so Django can find modules
            export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
            cd "${manage_dir}"
            # Override manage.py command to use the custom path
            MANAGE_PY_CMD="${manage_file}"
        else
            log_error "Custom manage module not found: ${DJANGO_PROJECT_DIR}${DJANGO_MANAGE_MODULE}"
            exit 1
        fi
    # Check if manage.py is in root or src directory and set up accordingly
    elif [[ -f "manage.py" ]]; then
        log_info "Found manage.py in project root"
        # Add src directory to Python path so Django can find modules in src/
        export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
        MANAGE_PY_CMD="manage.py"
    elif [[ -f "src/manage.py" ]]; then
        log_info "Found manage.py in src directory"
        # Add src directory to Python path and change to src directory
        export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
        cd "${DJANGO_PROJECT_DIR}/src"
        MANAGE_PY_CMD="manage.py"
    else
        log_error "manage.py not found in project root or src directory"
        exit 1
    fi
    
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
    
    # Check for custom DJANGO_MANAGE_MODULE path first
    if [[ -n "${DJANGO_MANAGE_MODULE:-}" ]]; then
        log_info "Using custom Django manage module: ${DJANGO_MANAGE_MODULE}"
        # Extract directory from the manage module path
        local manage_dir=$(dirname "${DJANGO_PROJECT_DIR}${DJANGO_MANAGE_MODULE}")
        local manage_file=$(basename "${DJANGO_MANAGE_MODULE}")
        
        if [[ -f "${DJANGO_PROJECT_DIR}${DJANGO_MANAGE_MODULE}" ]]; then
            # Add src directory to Python path so Django can find modules
            export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
            cd "${manage_dir}"
            # Override manage.py command to use the custom path
            MANAGE_PY_CMD="${manage_file}"
        else
            log_error "Custom manage module not found: ${DJANGO_PROJECT_DIR}${DJANGO_MANAGE_MODULE}"
            exit 1
        fi
    # Check if manage.py is in root or src directory and set up accordingly
    elif [[ -f "manage.py" ]]; then
        # Stay in project root directory
        MANAGE_PY_CMD="manage.py"
    elif [[ -f "src/manage.py" ]]; then
        # Add src directory to Python path and change to src directory
        export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
        cd "${DJANGO_PROJECT_DIR}/src"
        MANAGE_PY_CMD="manage.py"
    else
        log_error "manage.py not found in ${DJANGO_PROJECT_DIR} or ${DJANGO_PROJECT_DIR}/src"
        exit 1
    fi
    
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
    
    # Check for custom DJANGO_MANAGE_MODULE path first
    if [[ -n "${DJANGO_MANAGE_MODULE:-}" ]]; then
        log_info "Using custom Django manage module: ${DJANGO_MANAGE_MODULE}"
        # Extract directory from the manage module path
        local manage_dir=$(dirname "${DJANGO_PROJECT_DIR}${DJANGO_MANAGE_MODULE}")
        local manage_file=$(basename "${DJANGO_MANAGE_MODULE}")
        
        if [[ -f "${DJANGO_PROJECT_DIR}${DJANGO_MANAGE_MODULE}" ]]; then
            # Add src directory to Python path so Django can find modules
            export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
            cd "${manage_dir}"
            # Override manage.py command to use the custom path
            MANAGE_PY_CMD="${manage_file}"
        else
            log_error "Custom manage module not found: ${DJANGO_PROJECT_DIR}${DJANGO_MANAGE_MODULE}"
            exit 1
        fi
    # Check if manage.py is in root or src directory and set up accordingly
    elif [[ -f "manage.py" ]]; then
        # Stay in project root directory
        MANAGE_PY_CMD="manage.py"
    elif [[ -f "src/manage.py" ]]; then
        # Add src directory to Python path and change to src directory
        export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
        cd "${DJANGO_PROJECT_DIR}/src"
        MANAGE_PY_CMD="manage.py"
    else
        log_error "manage.py not found in ${DJANGO_PROJECT_DIR} or ${DJANGO_PROJECT_DIR}/src"
        exit 1
    fi
    
    if ! ${PROJECT_PYTHON_PATH} ${MANAGE_PY_CMD} shell -c "${superuser_creation_script}"; then
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
    
    user = User.objects.get(username=username)
    
    print(f"✓ Superuser verification successful")
    print(f"Username: {user.username}")
    print(f"Email: {user.email}")
    print(f"Is superuser: {user.is_superuser}")
    print(f"Is staff: {user.is_staff}")
    print(f"Is active: {user.is_active}")
    print(f"Date joined: {user.date_joined}")
    
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
'
    
    cd "${DJANGO_PROJECT_DIR}"
    
    # Check for custom DJANGO_MANAGE_MODULE path first
    if [[ -n "${DJANGO_MANAGE_MODULE:-}" ]]; then
        log_info "Using custom Django manage module: ${DJANGO_MANAGE_MODULE}"
        # Extract directory from the manage module path
        local manage_dir=$(dirname "${DJANGO_PROJECT_DIR}${DJANGO_MANAGE_MODULE}")
        local manage_file=$(basename "${DJANGO_MANAGE_MODULE}")
        
        if [[ -f "${DJANGO_PROJECT_DIR}${DJANGO_MANAGE_MODULE}" ]]; then
            # Add src directory to Python path so Django can find modules
            export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
            cd "${manage_dir}"
            # Override manage.py command to use the custom path
            MANAGE_PY_CMD="${manage_file}"
        else
            log_error "Custom manage module not found: ${DJANGO_PROJECT_DIR}${DJANGO_MANAGE_MODULE}"
            exit 1
        fi
    # Check if manage.py is in root or src directory and set up accordingly
    elif [[ -f "manage.py" ]]; then
        # Stay in project root directory
        MANAGE_PY_CMD="manage.py"
    elif [[ -f "src/manage.py" ]]; then
        # Add src directory to Python path and change to src directory
        export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
        cd "${DJANGO_PROJECT_DIR}/src"
        MANAGE_PY_CMD="manage.py"
    else
        log_error "manage.py not found in ${DJANGO_PROJECT_DIR} or ${DJANGO_PROJECT_DIR}/src"
        exit 1
    fi
    
    if ! ${PROJECT_PYTHON_PATH} ${MANAGE_PY_CMD} shell -c "${verification_script}"; then
        log_error "Failed to verify superuser"
        exit 1
    fi
}

# Main execution
main() {
    log_info "Starting Django superuser creation process..."
    
    # Validate environment
    validate_environment
    validate_email "$DEFAULT_SUPERUSER_EMAIL"
    
    # Check Django availability
    check_django_availability
    
    # Check if superuser already exists
    if superuser_exists; then
        log_info "✓ Superuser '${DEFAULT_SUPERUSER_USERNAME}' already exists"
        verify_superuser
        log_info "✓ Django superuser setup completed (existing user)"
        return 0
    fi
    
    # Create superuser
    create_superuser
    
    # Verify creation
    verify_superuser
    
    log_info "✓ Django superuser creation completed successfully"
}

# Help function
show_help() {
    cat << EOF
create-django-superuser.sh - Django Superuser Creation Script

DESCRIPTION:
    This script creates a Django superuser if it doesn't already exist.
    Uses environment variables for configuration.

ENVIRONMENT VARIABLES:
    DEFAULT_SUPERUSER_USERNAME  - Username for the superuser (default: admin)
    DEFAULT_SUPERUSER_EMAIL     - Email for the superuser (default: admin@example.com)  
    DEFAULT_SUPERUSER_PASSWORD  - Password for the superuser (default: changeme)
    PROJECT_PYTHON_PATH         - Path to Python executable (set by deployment orchestrator)
    DJANGO_PROJECT_DIR          - Django project directory (set by deployment orchestrator)

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
    ✓ Python and Django availability check
    ✓ Existing superuser check
    ✓ Superuser creation (if needed)
    ✓ Superuser verification
    ✓ Comprehensive logging

RETURN CODES:
    0 - Success (superuser created or already exists)
    1 - Error (validation failed, Django unavailable, creation failed)

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
