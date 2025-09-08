#!/bin/bash
# run-django-migrations.sh - Django Database Migrations Script
# 
# This script runs Django database migrations using the project's virtual environment.
# Uses environment variables for configuration.
#
# Required Environment Variables:
#   PROJECT_PYTHON_PATH  - Path to PROJECT Python executable (required for Django operations)
#   DJANGO_PROJECT_DIR   - Django project directory (default: current directory)
#
# Optional Environment Variables:
#   DJANGO_SETTINGS_MODULE - Django settings module (should be set)

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

# Check Django availability
check_django_availability() {
    log_info "Checking Django availability..."
    
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

# Make migrations (create new migration files if models changed)
make_migrations() {
    log_info "Creating new migrations if needed..."
    
    cd "${DJANGO_PROJECT_DIR}"
    
    # Check if manage.py is in root or src directory and set up accordingly
    if [[ -f "${DJANGO_PROJECT_DIR}/manage.py" ]]; then
        log_info "Using manage.py from project root"
        # Add src directory to Python path so Django can find modules in src/
        export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
        cd "${DJANGO_PROJECT_DIR}"
    elif [[ -f "${DJANGO_PROJECT_DIR}/src/manage.py" ]]; then
        log_info "Using manage.py from src directory"
        # Add src directory to Python path and change to src directory where manage.py is located
        export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
        cd "${DJANGO_PROJECT_DIR}/src"
    else
        log_error "manage.py not found in ${DJANGO_PROJECT_DIR} or ${DJANGO_PROJECT_DIR}/src"
        exit 1
    fi
    
    # Run makemigrations to create new migration files
    if ${PROJECT_PYTHON_PATH} manage.py makemigrations --dry-run --verbosity=0 | grep -q "No changes detected"; then
        log_info "No new migrations needed"
    else
        log_info "Creating new migration files..."
        if ! ${PROJECT_PYTHON_PATH} manage.py makemigrations; then
            log_error "Failed to create migrations"
            exit 1
        fi
        log_info "New migration files created successfully"
    fi
}

# Run migrations
run_migrations() {
    log_info "Running database migrations..."
    
    cd "${DJANGO_PROJECT_DIR}"
    
    # Check if manage.py is in root or src directory and set up accordingly
    if [[ -f "${DJANGO_PROJECT_DIR}/manage.py" ]]; then
        log_info "Using manage.py from project root"
        # Add src directory to Python path so Django can find modules in src/
        export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
        cd "${DJANGO_PROJECT_DIR}"
    elif [[ -f "${DJANGO_PROJECT_DIR}/src/manage.py" ]]; then
        log_info "Using manage.py from src directory"
        # Add src directory to Python path and change to src directory where manage.py is located
        export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
        cd "${DJANGO_PROJECT_DIR}/src"
    else
        log_error "manage.py not found in ${DJANGO_PROJECT_DIR} or ${DJANGO_PROJECT_DIR}/src"
        exit 1
    fi
    
    # Show migration plan first
    log_info "Migration plan:"
    if ! ${PROJECT_PYTHON_PATH} manage.py showmigrations --plan; then
        log_warn "Could not show migration plan (this is okay for new databases)"
    fi
    
    # Run migrations
    if ! ${PROJECT_PYTHON_PATH} manage.py migrate; then
        log_error "Database migrations failed"
        exit 1
    fi
    
    log_info "Database migrations completed successfully"
}

# Collect static files
collect_static() {
    log_info "Collecting static files..."
    
    cd "${DJANGO_PROJECT_DIR}"
    
    # Check if manage.py is in root or src directory and set up accordingly
    if [[ -f "${DJANGO_PROJECT_DIR}/manage.py" ]]; then
        log_info "Using manage.py from project root"
        # Add src directory to Python path so Django can find modules in src/
        export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
        cd "${DJANGO_PROJECT_DIR}"
    elif [[ -f "${DJANGO_PROJECT_DIR}/src/manage.py" ]]; then
        log_info "Using manage.py from src directory"
        # Add src directory to Python path and change to src directory where manage.py is located
        export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
        cd "${DJANGO_PROJECT_DIR}/src"
    else
        log_error "manage.py not found in ${DJANGO_PROJECT_DIR} or ${DJANGO_PROJECT_DIR}/src"
        exit 1
    fi
    
    # Collect static files (non-interactive)
    if ! ${PROJECT_PYTHON_PATH} manage.py collectstatic --noinput --clear; then
        log_warn "Static file collection failed (this may be okay if no static files are configured)"
    else
        log_info "Static files collected successfully"
    fi
}

# Verify migrations
verify_migrations() {
    log_info "Verifying migrations are applied..."
    
    cd "${DJANGO_PROJECT_DIR}"
    
    # Check if manage.py is in root or src directory and set up accordingly
    if [[ -f "${DJANGO_PROJECT_DIR}/manage.py" ]]; then
        log_info "Using manage.py from project root"
        # Add src directory to Python path so Django can find modules in src/
        export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
        cd "${DJANGO_PROJECT_DIR}"
    elif [[ -f "${DJANGO_PROJECT_DIR}/src/manage.py" ]]; then
        log_info "Using manage.py from src directory"
        # Add src directory to Python path and change to src directory where manage.py is located
        export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
        cd "${DJANGO_PROJECT_DIR}/src"
    else
        log_error "manage.py not found in ${DJANGO_PROJECT_DIR} or ${DJANGO_PROJECT_DIR}/src"
        exit 1
    fi
    
    # Check for unapplied migrations
    local unapplied_migrations
    unapplied_migrations=$(${PROJECT_PYTHON_PATH} manage.py showmigrations --plan | grep -c "\\[ \\]" || true)
    
    if [[ "$unapplied_migrations" -gt 0 ]]; then
        log_error "There are $unapplied_migrations unapplied migrations"
        ${PROJECT_PYTHON_PATH} manage.py showmigrations
        exit 1
    fi
    
    log_info "All migrations have been applied successfully"
}

# Main execution function
main() {
    log_info "Starting Django database migrations"
    log_info "Project directory: ${DJANGO_PROJECT_DIR}"
    log_info "Python executable: ${PROJECT_PYTHON_PATH}"
    
    # Run all operations
    check_python
    check_django_availability
    make_migrations
    run_migrations
    collect_static
    verify_migrations
    
    log_info "🎉 Django migrations completed successfully!"
}

# Help function
show_help() {
    cat << EOF
run-django-migrations.sh - Django Database Migrations Script

DESCRIPTION:
    This script runs Django database migrations using the project's virtual environment.
    It creates new migration files if needed, applies them to the database, and verifies completion.

REQUIRED ENVIRONMENT VARIABLES:
    PROJECT_PYTHON_PATH   Path to PROJECT Python executable (set by deployment orchestrator)

OPTIONAL ENVIRONMENT VARIABLES:
    DJANGO_PROJECT_DIR    Django project directory (default: current directory)
    DJANGO_SETTINGS_MODULE Django settings module (should be set)

USAGE:
    # Run migrations
    ./run-django-migrations.sh

    # With custom directory
    export DJANGO_PROJECT_DIR="/path/to/project"
    ./run-django-migrations.sh

OPERATIONS PERFORMED:
    ✓ Python executable validation
    ✓ Django availability check
    ✓ Create new migrations (if needed)
    ✓ Apply database migrations
    ✓ Collect static files
    ✓ Verify all migrations applied

EXIT CODES:
    0  Success - All migrations completed
    1  Error - Migration failed or validation error

EXAMPLES:
    # Basic migration run
    PROJECT_PYTHON_PATH=/path/to/venv/bin/python ./run-django-migrations.sh
    
    # With custom project directory
    PROJECT_PYTHON_PATH=/path/to/venv/bin/python DJANGO_PROJECT_DIR=/path/to/project ./run-django-migrations.sh
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
