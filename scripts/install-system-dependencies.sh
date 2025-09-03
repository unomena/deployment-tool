#!/bin/bash
# install-system-dependencies.sh - System Dependencies Installation Script
# 
# This script installs Ubuntu system dependencies via apt-get.
# Uses environment variables for configuration.
#
# Required Environment Variables:
#   SYSTEM_DEPENDENCIES - JSON array of system packages to install
#
# Optional Environment Variables:
#   UPDATE_PACKAGE_LIST - Whether to update apt package list first (default: true)
#   DEBIAN_FRONTEND     - Set to noninteractive to avoid prompts (default: noninteractive)

set -e  # Exit on any error

# Default values
UPDATE_PACKAGE_LIST="${UPDATE_PACKAGE_LIST:-true}"
export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"

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

# Check if running with sudo privileges
check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        log_info "Running as root"
        SUDO_CMD=""
    elif sudo -n true 2>/dev/null; then
        log_info "Sudo privileges available"
        SUDO_CMD="sudo"
    else
        log_error "This script requires sudo privileges to install system packages"
        log_error "Please run with sudo or ensure sudo is configured"
        exit 1
    fi
}

# Parse dependencies from environment variable
parse_dependencies() {
    if [[ -z "${SYSTEM_DEPENDENCIES}" ]]; then
        log_info "No system dependencies specified (SYSTEM_DEPENDENCIES is empty)"
        return 0
    fi
    
    # Convert JSON array to bash array
    # Handle both JSON array format ["pkg1","pkg2"] and space-separated format "pkg1 pkg2"
    if [[ "${SYSTEM_DEPENDENCIES}" == \[* ]]; then
        # JSON array format
        DEPS_ARRAY=($(echo "${SYSTEM_DEPENDENCIES}" | sed 's/\[//g' | sed 's/\]//g' | sed 's/"//g' | tr ',' ' '))
    else
        # Space-separated format
        DEPS_ARRAY=(${SYSTEM_DEPENDENCIES})
    fi
    
    if [[ ${#DEPS_ARRAY[@]} -eq 0 ]]; then
        log_info "No system dependencies to install"
        return 0
    fi
    
    log_info "Found ${#DEPS_ARRAY[@]} system dependencies to install: ${DEPS_ARRAY[*]}"
}

# Update package list
update_package_list() {
    if [[ "${UPDATE_PACKAGE_LIST}" == "true" ]]; then
        log_info "Updating apt package list..."
        if ${SUDO_CMD} apt-get update; then
            log_info "Package list updated successfully"
        else
            log_error "Failed to update package list"
            exit 1
        fi
    else
        log_info "Skipping package list update"
    fi
}

# Check if packages are already installed
check_installed_packages() {
    local installed_packages=()
    local missing_packages=()
    
    for package in "${DEPS_ARRAY[@]}"; do
        if dpkg -l | grep -q "^ii  ${package} "; then
            installed_packages+=("${package}")
        else
            missing_packages+=("${package}")
        fi
    done
    
    if [[ ${#installed_packages[@]} -gt 0 ]]; then
        log_info "Already installed: ${installed_packages[*]}"
    fi
    
    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        log_info "All packages are already installed"
        return 1  # No installation needed
    fi
    
    log_info "Need to install: ${missing_packages[*]}"
    DEPS_ARRAY=("${missing_packages[@]}")
    return 0  # Installation needed
}

# Install system dependencies
install_dependencies() {
    if [[ ${#DEPS_ARRAY[@]} -eq 0 ]]; then
        log_info "No packages to install"
        return 0
    fi
    
    log_info "Installing system dependencies: ${DEPS_ARRAY[*]}"
    
    # Build install command
    local install_cmd="${SUDO_CMD} apt-get install -y"
    
    # Add packages to command
    for package in "${DEPS_ARRAY[@]}"; do
        install_cmd="${install_cmd} ${package}"
    done
    
    log_info "Running: ${install_cmd}"
    
    if eval "${install_cmd}"; then
        log_info "System dependencies installed successfully"
        return 0
    else
        log_error "Failed to install some system dependencies"
        return 1
    fi
}

# Verify installation
verify_installation() {
    log_info "Verifying package installation..."
    
    local failed_packages=()
    
    for package in "${DEPS_ARRAY[@]}"; do
        if dpkg -l | grep -q "^ii  ${package} "; then
            log_info "✓ ${package} installed successfully"
        else
            log_error "✗ ${package} installation failed"
            failed_packages+=("${package}")
        fi
    done
    
    if [[ ${#failed_packages[@]} -gt 0 ]]; then
        log_error "Failed to install packages: ${failed_packages[*]}"
        return 1
    fi
    
    log_info "All packages verified successfully"
    return 0
}

# Clean up apt cache (optional)
cleanup_apt_cache() {
    log_info "Cleaning up apt cache..."
    ${SUDO_CMD} apt-get clean
    ${SUDO_CMD} apt-get autoclean
    log_info "Apt cache cleaned"
}

# Main execution function
main() {
    log_info "Starting system dependencies installation"
    
    # Check sudo privileges
    check_sudo
    
    # Parse dependencies
    parse_dependencies
    
    if [[ ${#DEPS_ARRAY[@]} -eq 0 ]]; then
        log_info "✓ No system dependencies to install"
        return 0
    fi
    
    # Update package list
    update_package_list
    
    # Check what's already installed
    if ! check_installed_packages; then
        log_info "✓ All packages already installed"
        return 0
    fi
    
    # Install dependencies
    if install_dependencies; then
        # Verify installation
        if verify_installation; then
            # Clean up
            cleanup_apt_cache
            log_info "🎉 System dependencies installation completed successfully"
            return 0
        else
            log_error "Package verification failed"
            return 1
        fi
    else
        log_error "Package installation failed"
        return 1
    fi
}

# Help function
show_help() {
    cat << EOF
install-system-dependencies.sh - System Dependencies Installation Script

DESCRIPTION:
    This script installs Ubuntu system dependencies via apt-get.
    It handles package checking, installation, and verification.

REQUIRED ENVIRONMENT VARIABLES:
    SYSTEM_DEPENDENCIES   JSON array or space-separated list of packages to install
                         Examples: '["git", "curl", "vim"]' or "git curl vim"

OPTIONAL ENVIRONMENT VARIABLES:
    UPDATE_PACKAGE_LIST   Update apt package list first (default: true)
    DEBIAN_FRONTEND      Set to noninteractive to avoid prompts (default: noninteractive)

USAGE:
    # With JSON array format
    export SYSTEM_DEPENDENCIES='["git", "curl", "build-essential"]'
    ./install-system-dependencies.sh
    
    # With space-separated format
    export SYSTEM_DEPENDENCIES="git curl build-essential"
    ./install-system-dependencies.sh
    
    # Skip package list update
    export UPDATE_PACKAGE_LIST="false"
    export SYSTEM_DEPENDENCIES="git curl"
    ./install-system-dependencies.sh

OPERATIONS PERFORMED:
    ✓ Sudo privileges check
    ✓ Dependencies parsing
    ✓ Package list update (optional)
    ✓ Installed packages check
    ✓ Missing packages installation
    ✓ Installation verification
    ✓ Apt cache cleanup

EXIT CODES:
    0  Success - All packages installed successfully
    1  Error - Installation or verification failed

EXAMPLES:
    # Basic installation
    SYSTEM_DEPENDENCIES="git curl vim" ./install-system-dependencies.sh
    
    # With JSON format (for programmatic use)
    SYSTEM_DEPENDENCIES='["postgresql-client", "libpq-dev"]' ./install-system-dependencies.sh
    
    # Skip update and cleanup
    UPDATE_PACKAGE_LIST=false SYSTEM_DEPENDENCIES="git" ./install-system-dependencies.sh
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
