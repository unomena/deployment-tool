#!/bin/bash
# install-python-dependencies.sh - Python Dependencies Installation Script
# 
# This script installs Python dependencies and requirements files in a virtual environment.
# Uses environment variables for configuration.
#
# Required Environment Variables:
#   VENV_PATH - Path to the Python virtual environment
#
# Optional Environment Variables:
#   PYTHON_DEPENDENCIES     - JSON array or space-separated list of Python packages
#   REQUIREMENTS_FILES      - JSON array or space-separated list of requirements files
#   PROJECT_DIR            - Project directory containing requirements files (default: .)
#   UPGRADE_PACKAGES       - Whether to upgrade packages during installation (default: false)
#   PIP_EXTRA_ARGS         - Additional arguments for pip install

set -e  # Exit on any error

# Default values
PROJECT_DIR="${PROJECT_DIR:-.}"
UPGRADE_PACKAGES="${UPGRADE_PACKAGES:-false}"
PIP_EXTRA_ARGS="${PIP_EXTRA_ARGS:-}"

# Source common logging utilities
source "$(dirname "$0")/logging-utils.sh"

# Check required environment variables
check_required_vars() {
    local missing_vars=()
    
    if [[ -z "${VENV_PATH}" ]]; then
        missing_vars+=("VENV_PATH")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Required variables: VENV_PATH"
        log_error "Optional variables: PYTHON_DEPENDENCIES, REQUIREMENTS_FILES, PROJECT_DIR (default: .), UPGRADE_PACKAGES (default: false)"
        exit 1
    fi
}

# Verify virtual environment exists
verify_virtual_environment() {
    log_info "Verifying virtual environment: ${VENV_PATH}"
    
    if [[ ! -d "${VENV_PATH}" ]]; then
        log_error "Virtual environment directory does not exist: ${VENV_PATH}"
        exit 1
    fi
    
    local python_path="${VENV_PATH}/bin/python"
    local pip_path="${VENV_PATH}/bin/pip"
    
    if [[ ! -f "${python_path}" ]]; then
        log_error "Python executable not found in virtual environment: ${python_path}"
        exit 1
    fi
    
    if [[ ! -f "${pip_path}" ]]; then
        log_error "Pip executable not found in virtual environment: ${pip_path}"
        exit 1
    fi
    
    # Test virtual environment
    local python_version
    python_version=$(${python_path} --version 2>&1)
    log_info "Using virtual environment: ${python_version}"
    
    local pip_version
    pip_version=$(${pip_path} --version)
    log_info "Using pip: ${pip_version}"
    
    PIP_CMD="${pip_path}"
}

# Parse Python dependencies from environment variable
parse_python_dependencies() {
    PYTHON_DEPS_ARRAY=()
    
    if [[ -z "${PYTHON_DEPENDENCIES}" ]]; then
        log_info "No Python dependencies specified (PYTHON_DEPENDENCIES is empty)"
        return 0
    fi
    
    # Convert JSON array to bash array or handle space-separated format
    if [[ "${PYTHON_DEPENDENCIES}" == \[* ]]; then
        # JSON array format
        PYTHON_DEPS_ARRAY=($(echo "${PYTHON_DEPENDENCIES}" | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | tr ',' ' '))
    else
        # Space-separated format
        PYTHON_DEPS_ARRAY=(${PYTHON_DEPENDENCIES})
    fi
    
    if [[ ${#PYTHON_DEPS_ARRAY[@]} -gt 0 ]]; then
        log_info "Found ${#PYTHON_DEPS_ARRAY[@]} Python dependencies to install: ${PYTHON_DEPS_ARRAY[*]}"
    fi
}

# Parse requirements files from environment variable
parse_requirements_files() {
    REQUIREMENTS_ARRAY=()
    
    if [[ -z "${REQUIREMENTS_FILES}" ]]; then
        log_info "No requirements files specified (REQUIREMENTS_FILES is empty)"
        return 0
    fi
    
    # Convert JSON array to bash array or handle space-separated format
    if [[ "${REQUIREMENTS_FILES}" == \[* ]]; then
        # JSON array format
        REQUIREMENTS_ARRAY=($(echo "${REQUIREMENTS_FILES}" | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | tr ',' ' '))
    else
        # Space-separated format
        REQUIREMENTS_ARRAY=(${REQUIREMENTS_FILES})
    fi
    
    if [[ ${#REQUIREMENTS_ARRAY[@]} -gt 0 ]]; then
        log_info "Found ${#REQUIREMENTS_ARRAY[@]} requirements files to install: ${REQUIREMENTS_ARRAY[*]}"
    fi
}

# Install individual Python packages
install_python_packages() {
    if [[ ${#PYTHON_DEPS_ARRAY[@]} -eq 0 ]]; then
        log_info "No Python packages to install"
        return 0
    fi
    
    log_info "Installing Python packages: ${PYTHON_DEPS_ARRAY[*]}"
    
    # Build pip install command
    local pip_cmd="${PIP_CMD} install"
    
    # Add upgrade flag if requested
    if [[ "${UPGRADE_PACKAGES}" == "true" ]]; then
        pip_cmd="${pip_cmd} --upgrade"
    fi
    
    # Add extra arguments
    if [[ -n "${PIP_EXTRA_ARGS}" ]]; then
        pip_cmd="${pip_cmd} ${PIP_EXTRA_ARGS}"
    fi
    
    # Add packages
    for package in "${PYTHON_DEPS_ARRAY[@]}"; do
        pip_cmd="${pip_cmd} ${package}"
    done
    
    log_info "Running: ${pip_cmd}"
    
    if eval "${pip_cmd}"; then
        log_info "Python packages installed successfully"
        
        # Verify installation of each package
        log_info "Verifying package installation..."
        local failed_packages=()
        for package in "${PYTHON_DEPS_ARRAY[@]}"; do
            # Extract package name (remove version constraints)
            local package_name=$(echo "${package}" | sed 's/[<>=!].*//')
            
            if ${PIP_CMD} show "${package_name}" >/dev/null 2>&1; then
                log_info "✓ ${package_name} installed"
            else
                log_error "✗ ${package_name} installation failed"
                failed_packages+=("${package_name}")
            fi
        done
        
        if [[ ${#failed_packages[@]} -gt 0 ]]; then
            log_error "Some packages failed to install: ${failed_packages[*]}"
            return 1
        fi
        
        return 0
    else
        log_error "Failed to install Python packages"
        return 1
    fi
}

# Install requirements files
install_requirements_files() {
    if [[ ${#REQUIREMENTS_ARRAY[@]} -eq 0 ]]; then
        log_info "No requirements files to install"
        return 0
    fi
    
    # Change to project directory if specified
    local original_dir=$(pwd)
    if [[ "${PROJECT_DIR}" != "." ]]; then
        log_info "Changing to project directory: ${PROJECT_DIR}"
        cd "${PROJECT_DIR}"
    fi
    
    for req_file in "${REQUIREMENTS_ARRAY[@]}"; do
        log_info "Installing requirements from: ${req_file}"
        
        # Check if requirements file exists
        if [[ ! -f "${req_file}" ]]; then
            log_error "Requirements file not found: ${req_file}"
            cd "${original_dir}"
            return 1
        fi
        
        # Count packages in requirements file
        local package_count
        package_count=$(grep -v '^#' "${req_file}" | grep -v '^$' | wc -l || echo "0")
        log_info "Requirements file contains ${package_count} packages"
        
        # Build pip install command
        local pip_cmd="${PIP_CMD} install -r ${req_file}"
        
        # Add upgrade flag if requested
        if [[ "${UPGRADE_PACKAGES}" == "true" ]]; then
            pip_cmd="${pip_cmd} --upgrade"
        fi
        
        # Add extra arguments
        if [[ -n "${PIP_EXTRA_ARGS}" ]]; then
            pip_cmd="${pip_cmd} ${PIP_EXTRA_ARGS}"
        fi
        
        log_info "Running: ${pip_cmd}"
        
        if eval "${pip_cmd}"; then
            log_info "✓ Requirements installed from: ${req_file}"
        else
            log_error "✗ Failed to install requirements from: ${req_file}"
            cd "${original_dir}"
            return 1
        fi
    done
    
    cd "${original_dir}"
    log_info "All requirements files installed successfully"
    return 0
}

# Show installed packages summary
show_installed_packages() {
    log_info "Installed packages summary:"
    
    local total_packages
    total_packages=$(${PIP_CMD} list | wc -l)
    log_info "Total packages installed: $((total_packages - 2))"  # Subtract header lines
    
    # Show recently installed packages if we have dependencies
    if [[ ${#PYTHON_DEPS_ARRAY[@]} -gt 0 ]] || [[ ${#REQUIREMENTS_ARRAY[@]} -gt 0 ]]; then
        log_info "Recently installed packages:"
        
        # Show installed versions of our dependencies
        if [[ ${#PYTHON_DEPS_ARRAY[@]} -gt 0 ]]; then
            for package in "${PYTHON_DEPS_ARRAY[@]}"; do
                local package_name=$(echo "${package}" | sed 's/[<>=!].*//')
                local version=$(${PIP_CMD} show "${package_name}" 2>/dev/null | grep "Version:" | cut -d' ' -f2 || echo "Unknown")
                echo "  ${package_name}: ${version}"
            done
        fi
    fi
}

# Freeze current environment
freeze_environment() {
    log_info "Current environment packages:"
    ${PIP_CMD} freeze | head -20
    if [[ $(${PIP_CMD} freeze | wc -l) -gt 20 ]]; then
        echo "  ... and $(($(${PIP_CMD} freeze | wc -l) - 20)) more packages"
    fi
}

# Check for security vulnerabilities
check_vulnerabilities() {
    log_info "Checking for known security vulnerabilities..."
    
    # Try to install and run pip-audit if available
    if ${PIP_CMD} install pip-audit >/dev/null 2>&1; then
        if ${VENV_PATH}/bin/pip-audit >/dev/null 2>&1; then
            log_info "✓ No known security vulnerabilities found"
        else
            log_warn "Some packages may have security vulnerabilities"
            log_warn "Run 'pip-audit' manually for details"
        fi
    else
        log_info "pip-audit not available, skipping vulnerability check"
    fi
}

# Main execution function
main() {
    log_info "Starting Python dependencies installation"
    log_info "Virtual environment: ${VENV_PATH}"
    log_info "Project directory: ${PROJECT_DIR}"
    
    # Check required variables
    check_required_vars
    
    # Verify virtual environment
    verify_virtual_environment
    
    # Parse dependencies and requirements
    parse_python_dependencies
    parse_requirements_files
    
    # Check if there's anything to install
    if [[ ${#PYTHON_DEPS_ARRAY[@]} -eq 0 ]] && [[ ${#REQUIREMENTS_ARRAY[@]} -eq 0 ]]; then
        log_info "No dependencies or requirements files specified"
        show_installed_packages
        log_info "✓ Python dependencies installation completed (nothing to install)"
        return 0
    fi
    
    # Install Python packages
    if ! install_python_packages; then
        log_error "Failed to install Python packages"
        return 1
    fi
    
    # Install requirements files
    if ! install_requirements_files; then
        log_error "Failed to install requirements files"
        return 1
    fi
    
    # Show summary
    show_installed_packages
    freeze_environment
    check_vulnerabilities
    
    log_info "🎉 Python dependencies installation completed successfully"
    return 0
}

# Help function
show_help() {
    cat << EOF
install-python-dependencies.sh - Python Dependencies Installation Script

DESCRIPTION:
    This script installs Python dependencies and requirements files in a virtual environment.
    It supports both individual packages and requirements files.

REQUIRED ENVIRONMENT VARIABLES:
    VENV_PATH           Path to the Python virtual environment

OPTIONAL ENVIRONMENT VARIABLES:
    PYTHON_DEPENDENCIES JSON array or space-separated list of Python packages
                       Examples: '["django", "psycopg2"]' or "django psycopg2"
    REQUIREMENTS_FILES  JSON array or space-separated list of requirements files
                       Examples: '["requirements.txt"]' or "requirements.txt dev-requirements.txt"
    PROJECT_DIR        Project directory containing requirements files (default: .)
    UPGRADE_PACKAGES   Whether to upgrade packages during installation (default: false)
    PIP_EXTRA_ARGS     Additional arguments for pip install

USAGE:
    # Install individual packages
    export VENV_PATH="/srv/app/venv"
    export PYTHON_DEPENDENCIES="django psycopg2 redis"
    ./install-python-dependencies.sh
    
    # Install from requirements files
    export VENV_PATH="/srv/app/venv"
    export REQUIREMENTS_FILES="requirements.txt"
    export PROJECT_DIR="/srv/app/code"
    ./install-python-dependencies.sh
    
    # Install with upgrades
    export VENV_PATH="/srv/app/venv"
    export PYTHON_DEPENDENCIES='["django>=4.0", "psycopg2-binary"]'
    export UPGRADE_PACKAGES="true"
    ./install-python-dependencies.sh

OPERATIONS PERFORMED:
    ✓ Virtual environment verification
    ✓ Dependencies parsing
    ✓ Requirements files parsing
    ✓ Python packages installation
    ✓ Requirements files installation
    ✓ Installation verification
    ✓ Security vulnerability check

EXIT CODES:
    0  Success - All dependencies installed successfully
    1  Error - Installation or verification failed

EXAMPLES:
    # Basic package installation
    VENV_PATH="/opt/app/venv" PYTHON_DEPENDENCIES="django redis" ./install-python-dependencies.sh
    
    # Install from requirements with JSON format
    VENV_PATH="/srv/app/venv" REQUIREMENTS_FILES='["requirements.txt", "dev-requirements.txt"]' PROJECT_DIR="/srv/app" ./install-python-dependencies.sh
    
    # Install with upgrades and extra pip arguments
    VENV_PATH="/opt/venv" PYTHON_DEPENDENCIES="django" UPGRADE_PACKAGES="true" PIP_EXTRA_ARGS="--no-cache-dir" ./install-python-dependencies.sh
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
