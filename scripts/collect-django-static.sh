#!/bin/bash
# collect-django-static.sh - Django Static Files Collection Script
# 
# This script collects Django static files using the project's virtual environment.
# Uses environment variables for configuration.
#
# Required Environment Variables:
#   PROJECT_PYTHON_PATH  - Path to PROJECT Python executable (required for Django operations)
#   DJANGO_PROJECT_DIR   - Django project directory (default: current directory)
#
# Optional Environment Variables:
#   DJANGO_SETTINGS_MODULE - Django settings module (should be set)
#

set -e  # Exit on any error

# Source common logging utilities
source "$(dirname "$0")/logging-utils.sh"

# Check required environment variables
if [[ -z "$PROJECT_PYTHON_PATH" ]]; then
    log_error "PROJECT_PYTHON_PATH environment variable is required"
    exit 1
fi

# Set default values
DJANGO_PROJECT_DIR="${DJANGO_PROJECT_DIR:-$(pwd)}"

# Validate Django project directory
if [[ ! -d "$DJANGO_PROJECT_DIR" ]]; then
    log_error "Django project directory not found: $DJANGO_PROJECT_DIR"
    exit 1
fi

# Validate Python executable
if [[ ! -f "$PROJECT_PYTHON_PATH" ]]; then
    log_error "Python executable not found: $PROJECT_PYTHON_PATH"
    exit 1
fi

# Function to collect static files
collect_static_files() {
    log_info "Collecting Django static files..."
    
    cd "${DJANGO_PROJECT_DIR}"
    
    # Add src directory to Python path and change to src directory
    export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
    # Check if manage.py is in root or src directory and set up accordingly
    if [[ -f "${DJANGO_PROJECT_DIR}/manage.py" ]]; then
        log_info "Using manage.py from project root"
        # Add src directory to Python path so Django can find modules in src/
        export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
        cd "${DJANGO_PROJECT_DIR}"
    elif [[ -f "${DJANGO_PROJECT_DIR}/src/manage.py" ]]; then
        log_info "Using manage.py from src directory"
        # Add src directory to Python path and change to src directory
        export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
        cd "${DJANGO_PROJECT_DIR}/src"
    else
        log_error "manage.py not found in ${DJANGO_PROJECT_DIR} or ${DJANGO_PROJECT_DIR}/src"
        exit 1
    fi
    
    # Run collectstatic command
    if ! ${PROJECT_PYTHON_PATH} manage.py collectstatic --noinput --clear; then
        log_error "Static files collection failed"
        exit 1
    fi
    
    log_info "✓ Static files collected successfully"
}

# Main execution
main() {
    log_info "Starting Django static files collection"
    log_info "Project directory: $DJANGO_PROJECT_DIR"
    log_info "Python executable: $PROJECT_PYTHON_PATH"
    
    # Check if Django settings module is set
    if [[ -z "$DJANGO_SETTINGS_MODULE" ]]; then
        log_warn "DJANGO_SETTINGS_MODULE not set, Django may use default settings"
    else
        log_info "Using Django settings: $DJANGO_SETTINGS_MODULE"
    fi
    
    collect_static_files
    
    log_info "🎉 Django static files collection completed successfully"
}

# Execute main function
main "$@"
