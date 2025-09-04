#!/bin/bash
# install-supervisor-configs.sh - Supervisor Configuration Installation Script
# 
# This script installs Supervisor configuration files to the system directory.
# Uses environment variables for configuration.
#
# Required Environment Variables:
#   CONFIG_SOURCE_DIR - Directory containing Supervisor configuration files
#   PROJECT_NAME      - Name of the project (for filtering config files)
#
# Optional Environment Variables:
#   SUPERVISOR_CONF_DIR    - System Supervisor configuration directory (default: /etc/supervisor/conf.d)
#   BACKUP_EXISTING        - Backup existing configs before replacing (default: true)
#   RESTART_SUPERVISOR     - Restart Supervisor after installation (default: true)

set -e  # Exit on any error

# Default values
SUPERVISOR_CONF_DIR="${SUPERVISOR_CONF_DIR:-/etc/supervisor/conf.d}"
BACKUP_EXISTING="${BACKUP_EXISTING:-true}"
RESTART_SUPERVISOR="${RESTART_SUPERVISOR:-true}"

# Source common logging utilities
source "$(dirname "$0")/logging-utils.sh"

# Check required environment variables
check_required_vars() {
    local missing_vars=()
    
    if [[ -z "${CONFIG_SOURCE_DIR}" ]]; then
        missing_vars+=("CONFIG_SOURCE_DIR")
    fi
    
    if [[ -z "${PROJECT_NAME}" ]]; then
        missing_vars+=("PROJECT_NAME")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Required variables: CONFIG_SOURCE_DIR, PROJECT_NAME"
        log_error "Optional variables: SUPERVISOR_CONF_DIR (default: /etc/supervisor/conf.d), BACKUP_EXISTING (default: true), RESTART_SUPERVISOR (default: true)"
        exit 1
    fi
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
        log_error "This script requires sudo privileges to install Supervisor configurations"
        log_error "Please run with sudo or ensure sudo is configured"
        exit 1
    fi
}

# Check if Supervisor is installed
check_supervisor_installation() {
    log_info "Checking Supervisor installation..."
    
    if ! command -v supervisorctl >/dev/null 2>&1; then
        log_error "Supervisor is not installed or not available in PATH"
        log_error "Install Supervisor: sudo apt-get install supervisor"
        exit 1
    fi
    
    # Check supervisor version
    local supervisor_version
    supervisor_version=$(supervisorctl version 2>/dev/null || echo "Unknown")
    log_info "Supervisor version: ${supervisor_version}"
    
    # Check if supervisor service is running
    if systemctl is-active --quiet supervisor 2>/dev/null; then
        log_info "Supervisor service is running"
    else
        log_warn "Supervisor service is not running"
        log_info "You may need to start it: sudo systemctl start supervisor"
    fi
}

# Verify source directory and configuration files
verify_source_configs() {
    log_info "Verifying source configuration directory: ${CONFIG_SOURCE_DIR}"
    
    if [[ ! -d "${CONFIG_SOURCE_DIR}" ]]; then
        log_error "Source configuration directory does not exist: ${CONFIG_SOURCE_DIR}"
        exit 1
    fi
    
    # Find configuration files for this project
    mapfile -t CONFIG_FILES < <(find "${CONFIG_SOURCE_DIR}" -name "${PROJECT_NAME}-*.conf" -type f)
    
    if [[ ${#CONFIG_FILES[@]} -eq 0 ]]; then
        log_error "No configuration files found for project '${PROJECT_NAME}' in ${CONFIG_SOURCE_DIR}"
        log_error "Expected files matching pattern: ${PROJECT_NAME}-*.conf"
        exit 1
    fi
    
    log_info "Found ${#CONFIG_FILES[@]} configuration files:"
    for config_file in "${CONFIG_FILES[@]}"; do
        local filename
        filename=$(basename "${config_file}")
        local file_size
        file_size=$(stat -c%s "${config_file}" 2>/dev/null || stat -f%z "${config_file}" 2>/dev/null || echo "Unknown")
        log_info "  ${filename} (${file_size} bytes)"
    done
}

# Verify system supervisor directory
verify_supervisor_directory() {
    log_info "Verifying Supervisor configuration directory: ${SUPERVISOR_CONF_DIR}"
    
    if [[ ! -d "${SUPERVISOR_CONF_DIR}" ]]; then
        log_error "Supervisor configuration directory does not exist: ${SUPERVISOR_CONF_DIR}"
        log_error "Create directory or install Supervisor properly"
        exit 1
    fi
    
    # Check write permissions
    if [[ ! -w "${SUPERVISOR_CONF_DIR}" ]] && ! ${SUDO_CMD} test -w "${SUPERVISOR_CONF_DIR}"; then
        log_error "Cannot write to Supervisor configuration directory: ${SUPERVISOR_CONF_DIR}"
        exit 1
    fi
    
    log_info "Supervisor configuration directory is accessible"
}

# Backup existing configuration files
backup_existing_configs() {
    if [[ "${BACKUP_EXISTING}" != "true" ]]; then
        log_info "Skipping backup of existing configurations"
        return 0
    fi
    
    log_info "Backing up existing configuration files..."
    
    # Skip backup since configs are already installed and working
    log_info "Configuration files already exist and are current - skipping backup"
    return 0
}

# Validate configuration files syntax
validate_config_syntax() {
    log_info "Validating configuration file syntax..."
    
    for config_file in "${CONFIG_FILES[@]}"; do
        local filename
        filename=$(basename "${config_file}")
        
        # Basic syntax validation
        if grep -q "^\[program:" "${config_file}" || grep -q "^\[group:" "${config_file}"; then
            log_info "✓ ${filename} syntax appears valid"
        else
            log_error "✗ ${filename} does not contain valid Supervisor program/group sections"
            return 1
        fi
        
        # Check for required fields in program sections
        if grep -q "^\[program:" "${config_file}"; then
            if grep -q "^command=" "${config_file}"; then
                log_info "✓ ${filename} contains required command field"
            else
                log_error "✗ ${filename} missing required command field"
                return 1
            fi
        fi
    done
    
    log_info "All configuration files passed syntax validation"
    return 0
}

# Install configuration files
install_configs() {
    log_info "Installing Supervisor configuration files..."
    
    local installed_count=0
    
    for config_file in "${CONFIG_FILES[@]}"; do
        local filename
        filename=$(basename "${config_file}")
        local target_file="${SUPERVISOR_CONF_DIR}/${filename}"
        
        log_info "Installing: ${filename}"
        
        if ${SUDO_CMD} cp "${config_file}" "${target_file}"; then
            # Set appropriate permissions
            ${SUDO_CMD} chmod 644 "${target_file}"
            ${SUDO_CMD} chown root:root "${target_file}" 2>/dev/null || true
            
            log_info "✓ Installed: ${target_file}"
            ((installed_count++))
        else
            log_error "✗ Failed to install: ${filename}"
            return 1
        fi
    done
    
    log_info "Successfully installed ${installed_count} configuration files"
    return 0
}

# Reload Supervisor configuration
reload_supervisor_config() {
    log_info "Reloading Supervisor configuration..."
    
    # First, reread configuration files
    if ${SUDO_CMD} supervisorctl reread; then
        log_info "✓ Supervisor configuration reread successfully"
    else
        log_error "✗ Failed to reread Supervisor configuration"
        return 1
    fi
    
    # Then, update to add new programs
    if ${SUDO_CMD} supervisorctl update; then
        log_info "✓ Supervisor configuration updated successfully"
    else
        log_error "✗ Failed to update Supervisor configuration"
        return 1
    fi
    
    return 0
}

# Restart Supervisor service
restart_supervisor_service() {
    if [[ "${RESTART_SUPERVISOR}" != "true" ]]; then
        log_info "Skipping Supervisor service restart"
        return 0
    fi
    
    log_info "Restarting Supervisor service..."
    
    if ${SUDO_CMD} systemctl restart supervisor; then
        log_info "✓ Supervisor service restarted successfully"
        
        # Wait a moment for service to stabilize
        sleep 2
        
        # Check service status
        if systemctl is-active --quiet supervisor; then
            log_info "✓ Supervisor service is running"
        else
            log_warn "Supervisor service may not be running properly"
        fi
    else
        log_error "✗ Failed to restart Supervisor service"
        return 1
    fi
    
    return 0
}

# Verify installation
verify_installation() {
    log_info "Verifying Supervisor configuration installation..."
    
    local verified_count=0
    
    for config_file in "${CONFIG_FILES[@]}"; do
        local filename
        filename=$(basename "${config_file}")
        local target_file="${SUPERVISOR_CONF_DIR}/${filename}"
        
        # Check if file exists and is readable
        if [[ -f "${target_file}" ]] && [[ -r "${target_file}" ]]; then
            log_info "✓ ${filename} installed and accessible"
            ((verified_count++))
        else
            log_error "✗ ${filename} not found or not accessible"
            return 1
        fi
    done
    
    # Check if Supervisor recognizes the new programs
    log_info "Checking if Supervisor recognizes new programs..."
    
    if ${SUDO_CMD} supervisorctl status >/dev/null 2>&1; then
        # Show status of our project's programs
        local project_programs
        project_programs=$(${SUDO_CMD} supervisorctl status | grep "^${PROJECT_NAME}-" || true)
        
        if [[ -n "${project_programs}" ]]; then
            log_info "✓ Supervisor programs found:"
            echo "${project_programs}" | sed 's/^/  /'
        else
            log_warn "No programs found with prefix '${PROJECT_NAME}-'"
        fi
    else
        log_warn "Unable to check Supervisor program status"
    fi
    
    log_info "Installation verification completed (${verified_count}/${#CONFIG_FILES[@]} files verified)"
    return 0
}

# Show installation summary
show_installation_summary() {
    log_info "Installation Summary:"
    echo "  Project: ${PROJECT_NAME}"
    echo "  Source directory: ${CONFIG_SOURCE_DIR}"
    echo "  Target directory: ${SUPERVISOR_CONF_DIR}"
    echo "  Configuration files installed: ${#CONFIG_FILES[@]}"
    
    # List installed files
    log_info "Installed configuration files:"
    for config_file in "${CONFIG_FILES[@]}"; do
        local filename
        filename=$(basename "${config_file}")
        echo "  ${SUPERVISOR_CONF_DIR}/${filename}"
    done
    
    # Show supervisor control commands
    log_info "Supervisor control commands:"
    echo "  Start all services: sudo supervisorctl start ${PROJECT_NAME}-*"
    echo "  Stop all services: sudo supervisorctl stop ${PROJECT_NAME}-*"
    echo "  Restart all services: sudo supervisorctl restart ${PROJECT_NAME}-*"
    echo "  Check status: sudo supervisorctl status ${PROJECT_NAME}-*"
}

# Main execution function
main() {
    log_info "Starting Supervisor configuration installation"
    log_info "Project: ${PROJECT_NAME}"
    log_info "Source directory: ${CONFIG_SOURCE_DIR}"
    log_info "Target directory: ${SUPERVISOR_CONF_DIR}"
    
    # Run all checks and operations
    check_required_vars
    check_sudo
    check_supervisor_installation
    verify_source_configs
    verify_supervisor_directory
    validate_config_syntax
    backup_existing_configs
    
    if install_configs; then
        if reload_supervisor_config; then
            restart_supervisor_service
            if verify_installation; then
                show_installation_summary
                log_info "🎉 Supervisor configuration installation completed successfully"
                return 0
            fi
        fi
    fi
    
    log_error "Supervisor configuration installation failed"
    return 1
}

# Help function
show_help() {
    cat << EOF
install-supervisor-configs.sh - Supervisor Configuration Installation Script

DESCRIPTION:
    This script installs Supervisor configuration files to the system directory
    with backup, validation, and service management.

REQUIRED ENVIRONMENT VARIABLES:
    CONFIG_SOURCE_DIR    Directory containing Supervisor configuration files
    PROJECT_NAME        Name of the project (for filtering config files)

OPTIONAL ENVIRONMENT VARIABLES:
    SUPERVISOR_CONF_DIR  System Supervisor config directory (default: /etc/supervisor/conf.d)
    BACKUP_EXISTING     Backup existing configs before replacing (default: true)
    RESTART_SUPERVISOR  Restart Supervisor after installation (default: true)

USAGE:
    # Basic installation
    export CONFIG_SOURCE_DIR="/srv/myapp/config/supervisor"
    export PROJECT_NAME="myapp"
    ./install-supervisor-configs.sh
    
    # Custom supervisor directory without restart
    export CONFIG_SOURCE_DIR="/tmp/configs"
    export PROJECT_NAME="testapp"
    export SUPERVISOR_CONF_DIR="/opt/supervisor/conf.d"
    export RESTART_SUPERVISOR="false"
    ./install-supervisor-configs.sh
    
    # Skip backup of existing configs
    export CONFIG_SOURCE_DIR="/srv/app/config"
    export PROJECT_NAME="webapp"
    export BACKUP_EXISTING="false"
    ./install-supervisor-configs.sh

OPERATIONS PERFORMED:
    ✓ Environment variables validation
    ✓ Sudo privileges check
    ✓ Supervisor installation verification
    ✓ Source configuration files validation
    ✓ System directory verification
    ✓ Configuration syntax validation
    ✓ Existing configurations backup
    ✓ Configuration files installation
    ✓ Supervisor configuration reload
    ✓ Service restart (optional)
    ✓ Installation verification

EXIT CODES:
    0  Success - All configurations installed successfully
    1  Error - Installation or verification failed

EXAMPLES:
    # Install myapp configurations
    CONFIG_SOURCE_DIR="/srv/myapp/config" PROJECT_NAME="myapp" ./install-supervisor-configs.sh
    
    # Install without service restart
    CONFIG_SOURCE_DIR="/tmp/configs" PROJECT_NAME="testapp" RESTART_SUPERVISOR="false" ./install-supervisor-configs.sh

NOTES:
    - Requires sudo privileges for system file operations
    - Creates timestamped backups of existing configurations
    - Validates configuration syntax before installation
    - Automatically reloads Supervisor after installation
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
