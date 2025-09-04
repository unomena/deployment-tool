#!/bin/bash
# run-unit-tests.sh - Django Unit Tests and Health Check Script
# 
# This script runs Django unit tests and health check validation using the project's virtual environment.
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

# Run unit tests and health checks
run_tests() {
    log_info "Running unit tests and health check validation..."
    
    cd "${DJANGO_PROJECT_DIR}"
    
    # Add src directory to Python path and change to src directory
    export PYTHONPATH="${DJANGO_PROJECT_DIR}/src:${PYTHONPATH}"
    cd "${DJANGO_PROJECT_DIR}/src"
    
    # Run the test script with health check validation
    if ! ${PROJECT_PYTHON_PATH} run_tests.py --health-check; then
        log_error "Unit tests and health check validation failed"
        exit 1
    fi
    
    log_info "Unit tests and health check validation completed successfully"
}

# Main execution
main() {
    log_info "Starting Django unit tests and health check validation"
    log_info "Project directory: ${DJANGO_PROJECT_DIR}"
    log_info "Python executable: ${PROJECT_PYTHON_PATH}"
    
    check_python
    run_tests
    
    log_info "🎉 Unit tests and health check validation completed successfully!"
}

# Execute main function
main "$@"
