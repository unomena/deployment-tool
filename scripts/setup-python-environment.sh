#!/bin/bash
# setup-python-environment.sh - Python Virtual Environment Setup Script
# 
# This script creates a Python virtual environment with the specified version.
# Uses environment variables for configuration.
#
# Required Environment Variables:
#   PYTHON_VERSION - Python version to use (e.g., "3.12", "3.11")
#   VENV_PATH      - Path where virtual environment should be created
#
# Optional Environment Variables:
#   UPGRADE_PIP    - Whether to upgrade pip after creating venv (default: true)
#   PYTHON_PPA     - Whether to use deadsnakes PPA for Python installation (default: true)

set -e  # Exit on any error

# Default values
UPGRADE_PIP="${UPGRADE_PIP:-true}"
PYTHON_PPA="${PYTHON_PPA:-true}"

# Source common logging utilities
source "$(dirname "$0")/logging-utils.sh"

# Check required environment variables
check_required_vars() {
    local missing_vars=()
    
    if [[ -z "${PYTHON_VERSION}" ]]; then
        missing_vars+=("PYTHON_VERSION")
    fi
    
    if [[ -z "${VENV_PATH}" ]]; then
        missing_vars+=("VENV_PATH")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Required variables: PYTHON_VERSION, VENV_PATH"
        log_error "Optional variables: UPGRADE_PIP (default: true), PYTHON_PPA (default: true)"
        exit 1
    fi
}

# Check if running with sudo privileges for system Python installation
check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        SUDO_CMD=""
    elif sudo -n true 2>/dev/null; then
        SUDO_CMD="sudo"
    else
        log_warn "Sudo privileges not available - may not be able to install Python versions"
        SUDO_CMD="sudo"  # Will prompt when needed
    fi
}

# Check if Python version is available
check_python_version() {
    local python_executable="python${PYTHON_VERSION}"
    
    log_info "Checking for Python ${PYTHON_VERSION}..."
    
    if command -v "${python_executable}" >/dev/null 2>&1; then
        local version_output
        version_output=$(${python_executable} --version 2>&1)
        log_info "Found: ${version_output}"
        PYTHON_EXECUTABLE="${python_executable}"
        return 0
    else
        log_warn "Python ${PYTHON_VERSION} not found"
        return 1
    fi
}

# Install Python version using deadsnakes PPA
install_python_version() {
    if [[ "${PYTHON_PPA}" != "true" ]]; then
        log_error "Python ${PYTHON_VERSION} not available and PPA installation disabled"
        exit 1
    fi
    
    log_info "Installing Python ${PYTHON_VERSION} using deadsnakes PPA..."
    
    # Add software-properties-common if needed
    if ! command -v add-apt-repository >/dev/null 2>&1; then
        log_info "Installing software-properties-common..."
        ${SUDO_CMD} apt-get update
        ${SUDO_CMD} apt-get install -y software-properties-common
    fi
    
    # Add deadsnakes PPA
    log_info "Adding deadsnakes PPA..."
    ${SUDO_CMD} add-apt-repository -y ppa:deadsnakes/ppa
    ${SUDO_CMD} apt-get update
    
    # Install Python packages
    local python_packages=(
        "python${PYTHON_VERSION}"
        "python${PYTHON_VERSION}-venv"
        "python${PYTHON_VERSION}-dev"
        "python${PYTHON_VERSION}-distutils"
    )
    
    log_info "Installing Python packages: ${python_packages[*]}"
    ${SUDO_CMD} apt-get install -y "${python_packages[@]}"
    
    # Verify installation
    local python_executable="python${PYTHON_VERSION}"
    if command -v "${python_executable}" >/dev/null 2>&1; then
        local version_output
        version_output=$(${python_executable} --version 2>&1)
        log_info "Successfully installed: ${version_output}"
        PYTHON_EXECUTABLE="${python_executable}"
    else
        log_error "Python installation failed"
        exit 1
    fi
}

# Create virtual environment
create_virtual_environment() {
    log_info "Creating virtual environment at: ${VENV_PATH}"
    
    # Remove existing virtual environment if it exists
    if [[ -d "${VENV_PATH}" ]]; then
        log_warn "Virtual environment already exists, removing..."
        rm -rf "${VENV_PATH}"
    fi
    
    # Create parent directories if they don't exist
    local venv_parent
    venv_parent=$(dirname "${VENV_PATH}")
    mkdir -p "${venv_parent}"
    
    # Create virtual environment
    if ${PYTHON_EXECUTABLE} -m venv "${VENV_PATH}"; then
        log_info "Virtual environment created successfully"
    else
        log_error "Failed to create virtual environment"
        exit 1
    fi
}

# Upgrade pip in virtual environment
upgrade_pip() {
    if [[ "${UPGRADE_PIP}" != "true" ]]; then
        log_info "Skipping pip upgrade"
        return 0
    fi
    
    log_info "Upgrading pip in virtual environment..."
    
    local pip_path="${VENV_PATH}/bin/pip"
    
    if [[ -f "${pip_path}" ]]; then
        if ${pip_path} install --upgrade pip; then
            log_info "Pip upgraded successfully"
            
            # Show pip version
            local pip_version
            pip_version=$(${pip_path} --version)
            log_info "Using: ${pip_version}"
        else
            log_warn "Failed to upgrade pip"
        fi
    else
        log_error "Pip not found in virtual environment"
        exit 1
    fi
}

# Verify virtual environment
verify_virtual_environment() {
    log_info "Verifying virtual environment..."
    
    local python_path="${VENV_PATH}/bin/python"
    local pip_path="${VENV_PATH}/bin/pip"
    
    # Check Python executable
    if [[ -f "${python_path}" ]]; then
        local python_version
        python_version=$(${python_path} --version 2>&1)
        log_info "✓ Python executable: ${python_version}"
    else
        log_error "✗ Python executable not found in virtual environment"
        return 1
    fi
    
    # Check pip executable
    if [[ -f "${pip_path}" ]]; then
        local pip_version
        pip_version=$(${pip_path} --version)
        log_info "✓ Pip available: ${pip_version}"
    else
        log_error "✗ Pip not found in virtual environment"
        return 1
    fi
    
    # Test basic Python functionality
    if ${python_path} -c "import sys; print(f'Python {sys.version_info.major}.{sys.version_info.minor} working')"; then
        log_info "✓ Python functionality verified"
    else
        log_error "✗ Python functionality test failed"
        return 1
    fi
    
    log_info "Virtual environment verification completed successfully"
    return 0
}

# Show virtual environment information
show_venv_info() {
    log_info "Virtual Environment Information:"
    echo "  Path: ${VENV_PATH}"
    echo "  Python: $(${VENV_PATH}/bin/python --version 2>&1)"
    echo "  Pip: $(${VENV_PATH}/bin/pip --version)"
    echo "  Activate command: source ${VENV_PATH}/bin/activate"
}

# Main execution function
main() {
    log_info "Starting Python virtual environment setup"
    log_info "Python version: ${PYTHON_VERSION}"
    log_info "Virtual environment path: ${VENV_PATH}"
    
    # Check required variables
    check_required_vars
    
    # Check sudo privileges
    check_sudo
    
    # Check if Python version is available, install if needed
    if ! check_python_version; then
        install_python_version
    fi
    
    # Create virtual environment
    create_virtual_environment
    
    # Upgrade pip
    upgrade_pip
    
    # Verify virtual environment
    if verify_virtual_environment; then
        show_venv_info
        log_info "🎉 Python virtual environment setup completed successfully"
        return 0
    else
        log_error "Virtual environment verification failed"
        return 1
    fi
}

# Help function
show_help() {
    cat << EOF
setup-python-environment.sh - Python Virtual Environment Setup Script

DESCRIPTION:
    This script creates a Python virtual environment with the specified version.
    It can automatically install Python versions using the deadsnakes PPA if needed.

REQUIRED ENVIRONMENT VARIABLES:
    PYTHON_VERSION    Python version to use (e.g., "3.12", "3.11", "3.10")
    VENV_PATH        Full path where virtual environment should be created

OPTIONAL ENVIRONMENT VARIABLES:
    UPGRADE_PIP      Upgrade pip after creating venv (default: true)
    PYTHON_PPA      Use deadsnakes PPA for Python installation (default: true)

USAGE:
    # Basic usage
    export PYTHON_VERSION="3.12"
    export VENV_PATH="/path/to/venv"
    ./setup-python-environment.sh
    
    # Skip pip upgrade
    export UPGRADE_PIP="false"
    export PYTHON_VERSION="3.11"
    export VENV_PATH="/srv/app/venv"
    ./setup-python-environment.sh
    
    # Disable automatic Python installation
    export PYTHON_PPA="false"
    export PYTHON_VERSION="3.10"
    export VENV_PATH="/opt/myapp/venv"
    ./setup-python-environment.sh

OPERATIONS PERFORMED:
    ✓ Environment variables validation
    ✓ Python version availability check
    ✓ Python installation (if needed via deadsnakes PPA)
    ✓ Virtual environment creation
    ✓ Pip upgrade (optional)
    ✓ Virtual environment verification

EXIT CODES:
    0  Success - Virtual environment created and verified
    1  Error - Setup or verification failed

EXAMPLES:
    # Create Python 3.12 venv
    PYTHON_VERSION="3.12" VENV_PATH="/srv/myapp/venv" ./setup-python-environment.sh
    
    # Create venv without pip upgrade
    PYTHON_VERSION="3.11" VENV_PATH="/opt/app/venv" UPGRADE_PIP="false" ./setup-python-environment.sh

NOTES:
    - The script will remove existing virtual environments at the target path
    - Requires sudo privileges for Python installation via PPA
    - Creates parent directories for the virtual environment path if needed
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
