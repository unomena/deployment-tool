#!/bin/bash
# validate-deployment.sh - Deployment Validation Script
# 
# This script validates a complete deployment setup by checking directories,
# virtual environment, dependencies, and configurations.
# Uses environment variables for configuration.
#
# Required Environment Variables:
#   BASE_PATH     - Base deployment path
#   CODE_PATH     - Application code path
#   VENV_PATH     - Virtual environment path
#   CONFIG_PATH   - Configuration files path
#   LOGS_PATH     - Log files path
#   PROJECT_NAME  - Project name for validation
#
# Optional Environment Variables:
#   SKIP_DEPENDENCY_CHECK    - Skip Python dependency validation (default: false)
#   SKIP_SUPERVISOR_CHECK    - Skip Supervisor config validation (default: false)
#   SUPERVISOR_CONF_DIR      - Supervisor config directory (default: /etc/supervisor/conf.d)

set -e  # Exit on any error

# Default values
SKIP_DEPENDENCY_CHECK="${SKIP_DEPENDENCY_CHECK:-false}"
SKIP_SUPERVISOR_CHECK="${SKIP_SUPERVISOR_CHECK:-false}"
SUPERVISOR_CONF_DIR="${SUPERVISOR_CONF_DIR:-/etc/supervisor/conf.d}"

# Source common logging utilities
source "$(dirname "$0")/logging-utils.sh"

# Check required environment variables
check_required_vars() {
    local missing_vars=()
    
    required_vars=("BASE_PATH" "CODE_PATH" "VENV_PATH" "CONFIG_PATH" "LOGS_PATH" "PROJECT_NAME")
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("${var}")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Required variables: ${required_vars[*]}"
        exit 1
    fi
}

# Validation counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Helper function to track validation results
validate_check() {
    local check_name="$1"
    local check_result="$2"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if [[ "${check_result}" == "0" ]]; then
        log_success "${check_name}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        log_failure "${check_name}"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

# Check directory structure
check_directories() {
    log_info "Validating directory structure..."
    
    local directories=("${BASE_PATH}" "${CODE_PATH}" "${VENV_PATH}" "${CONFIG_PATH}" "${LOGS_PATH}")
    local dir_check_passed=0
    
    for dir in "${directories[@]}"; do
        if [[ -d "${dir}" ]]; then
            log_info "  ✓ Directory exists: ${dir}"
        else
            log_error "  ✗ Directory missing: ${dir}"
            dir_check_passed=1
        fi
    done
    
    validate_check "Directory structure" "${dir_check_passed}"
    return ${dir_check_passed}
}

# Check virtual environment
check_virtual_environment() {
    log_info "Validating virtual environment..."
    
    local python_path="${VENV_PATH}/bin/python"
    local pip_path="${VENV_PATH}/bin/pip"
    local venv_check_passed=0
    
    # Check Python executable
    if [[ -f "${python_path}" && -x "${python_path}" ]]; then
        local python_version
        python_version=$(${python_path} --version 2>&1 || echo "Unknown")
        log_info "  ✓ Python executable: ${python_version}"
    else
        log_error "  ✗ Python executable not found or not executable: ${python_path}"
        venv_check_passed=1
    fi
    
    # Check pip executable
    if [[ -f "${pip_path}" && -x "${pip_path}" ]]; then
        local pip_version
        pip_version=$(${pip_path} --version 2>&1 || echo "Unknown")
        log_info "  ✓ Pip executable: ${pip_version}"
    else
        log_error "  ✗ Pip executable not found or not executable: ${pip_path}"
        venv_check_passed=1
    fi
    
    # Test basic Python functionality
    if [[ ${venv_check_passed} -eq 0 ]]; then
        if ${python_path} -c "import sys; print('Python test successful')" >/dev/null 2>&1; then
            log_info "  ✓ Python functionality test passed"
        else
            log_error "  ✗ Python functionality test failed"
            venv_check_passed=1
        fi
    fi
    
    validate_check "Virtual environment" "${venv_check_passed}"
    return ${venv_check_passed}
}

# Check Python dependencies
check_python_dependencies() {
    if [[ "${SKIP_DEPENDENCY_CHECK}" == "true" ]]; then
        log_info "Skipping Python dependency check"
        return 0
    fi
    
    log_info "Validating Python dependencies..."
    
    local pip_path="${VENV_PATH}/bin/pip"
    local dep_check_passed=0
    
    if [[ ! -f "${pip_path}" ]]; then
        log_error "  ✗ Pip not available for dependency check"
        validate_check "Python dependencies" "1"
        return 1
    fi
    
    # Get installed packages count
    local package_count
    package_count=$(${pip_path} list 2>/dev/null | tail -n +3 | wc -l || echo "0")
    
    if [[ ${package_count} -gt 0 ]]; then
        log_info "  ✓ ${package_count} Python packages installed"
        
        # Check for common essential packages
        local essential_packages=("setuptools" "pip")
        for package in "${essential_packages[@]}"; do
            if ${pip_path} show "${package}" >/dev/null 2>&1; then
                log_info "  ✓ Essential package found: ${package}"
            else
                log_warn "  ! Essential package missing: ${package}"
            fi
        done
    else
        log_error "  ✗ No Python packages found"
        dep_check_passed=1
    fi
    
    # Check for requirements files in code directory
    if [[ -d "${CODE_PATH}" ]]; then
        local requirements_files
        requirements_files=$(find "${CODE_PATH}" -name "requirements*.txt" -type f 2>/dev/null | wc -l)
        
        if [[ ${requirements_files} -gt 0 ]]; then
            log_info "  ✓ Found ${requirements_files} requirements file(s) in code directory"
        else
            log_info "  ! No requirements files found in code directory"
        fi
    fi
    
    validate_check "Python dependencies" "${dep_check_passed}"
    return ${dep_check_passed}
}

# Check Supervisor configurations
check_supervisor_configs() {
    if [[ "${SKIP_SUPERVISOR_CHECK}" == "true" ]]; then
        log_info "Skipping Supervisor configuration check"
        return 0
    fi
    
    log_info "Validating Supervisor configurations..."
    
    local supervisor_check_passed=0
    
    # Check if Supervisor is installed
    if ! command -v supervisorctl >/dev/null 2>&1; then
        log_warn "  ! Supervisor not installed - skipping configuration check"
        validate_check "Supervisor configurations" "0"  # Not a failure if not needed
        return 0
    fi
    
    # Check system supervisor directory
    if [[ ! -d "${SUPERVISOR_CONF_DIR}" ]]; then
        log_error "  ✗ Supervisor configuration directory not found: ${SUPERVISOR_CONF_DIR}"
        validate_check "Supervisor configurations" "1"
        return 1
    fi
    
    # Look for project-specific configurations
    local project_configs
    project_configs=$(find "${SUPERVISOR_CONF_DIR}" -name "${PROJECT_NAME}-*.conf" -type f 2>/dev/null | wc -l)
    
    if [[ ${project_configs} -gt 0 ]]; then
        log_info "  ✓ Found ${project_configs} Supervisor configuration(s) for project"
        
        # List the configuration files
        find "${SUPERVISOR_CONF_DIR}" -name "${PROJECT_NAME}-*.conf" -type f 2>/dev/null | while read -r config_file; do
            local filename
            filename=$(basename "${config_file}")
            log_info "    - ${filename}"
        done
    else
        log_warn "  ! No Supervisor configurations found for project '${PROJECT_NAME}'"
        supervisor_check_passed=1
    fi
    
    # Check local supervisor configurations
    local local_supervisor_dir="${CONFIG_PATH}/supervisor"
    if [[ -d "${local_supervisor_dir}" ]]; then
        local local_configs
        local_configs=$(find "${local_supervisor_dir}" -name "*.conf" -type f 2>/dev/null | wc -l)
        
        if [[ ${local_configs} -gt 0 ]]; then
            log_info "  ✓ Found ${local_configs} local Supervisor configuration(s)"
        else
            log_warn "  ! No local Supervisor configurations found"
        fi
    else
        log_warn "  ! Local Supervisor configuration directory not found: ${local_supervisor_dir}"
    fi
    
    validate_check "Supervisor configurations" "${supervisor_check_passed}"
    return ${supervisor_check_passed}
}

# Check log directories and permissions
check_log_setup() {
    log_info "Validating log setup..."
    
    local log_check_passed=0
    
    # Check main logs directory
    if [[ -d "${LOGS_PATH}" ]]; then
        log_info "  ✓ Main logs directory exists: ${LOGS_PATH}"
        
        # Check subdirectories
        local log_subdirs=("supervisor" "app")
        for subdir in "${log_subdirs[@]}"; do
            local log_subdir="${LOGS_PATH}/${subdir}"
            if [[ -d "${log_subdir}" ]]; then
                log_info "  ✓ Log subdirectory exists: ${subdir}"
            else
                log_warn "  ! Log subdirectory missing: ${subdir}"
            fi
        done
        
        # Check if logs directory is writable
        if [[ -w "${LOGS_PATH}" ]]; then
            log_info "  ✓ Logs directory is writable"
        else
            log_warn "  ! Logs directory is not writable (may need different user)"
        fi
    else
        log_error "  ✗ Main logs directory missing: ${LOGS_PATH}"
        log_check_passed=1
    fi
    
    validate_check "Log setup" "${log_check_passed}"
    return ${log_check_passed}
}

# Check application code
check_application_code() {
    log_info "Validating application code..."
    
    local code_check_passed=0
    
    if [[ -d "${CODE_PATH}" ]]; then
        # Check if directory is not empty
        local file_count
        file_count=$(find "${CODE_PATH}" -type f 2>/dev/null | wc -l)
        
        if [[ ${file_count} -gt 0 ]]; then
            log_info "  ✓ Code directory contains ${file_count} files"
            
            # Check for common application files
            local common_files=("manage.py" "wsgi.py" "app.py" "main.py")
            local found_app_files=()
            
            for file in "${common_files[@]}"; do
                if find "${CODE_PATH}" -name "${file}" -type f 2>/dev/null | grep -q .; then
                    found_app_files+=("${file}")
                fi
            done
            
            if [[ ${#found_app_files[@]} -gt 0 ]]; then
                log_info "  ✓ Found application files: ${found_app_files[*]}"
            else
                log_info "  ! No common application files found (${common_files[*]})"
            fi
            
            # Check for Git repository
            if [[ -d "${CODE_PATH}/.git" ]]; then
                log_info "  ✓ Git repository found"
                
                # Get current branch and latest commit
                local current_branch
                current_branch=$(cd "${CODE_PATH}" && git branch --show-current 2>/dev/null || echo "Unknown")
                local latest_commit
                latest_commit=$(cd "${CODE_PATH}" && git log -1 --oneline 2>/dev/null || echo "Unknown")
                
                log_info "    Branch: ${current_branch}"
                log_info "    Latest commit: ${latest_commit}"
            else
                log_info "  ! No Git repository found"
            fi
        else
            log_error "  ✗ Code directory is empty"
            code_check_passed=1
        fi
    else
        log_error "  ✗ Code directory missing: ${CODE_PATH}"
        code_check_passed=1
    fi
    
    validate_check "Application code" "${code_check_passed}"
    return ${code_check_passed}
}

# Check system services
check_system_services() {
    log_info "Validating system services..."
    
    local service_check_passed=0
    
    # Check if systemctl is available
    if ! command -v systemctl >/dev/null 2>&1; then
        log_warn "  ! systemctl not available - skipping service checks"
        validate_check "System services" "0"
        return 0
    fi
    
    # Check Supervisor service if configurations exist
    if [[ "${SKIP_SUPERVISOR_CHECK}" != "true" ]] && command -v supervisorctl >/dev/null 2>&1; then
        if systemctl is-active --quiet supervisor 2>/dev/null; then
            log_info "  ✓ Supervisor service is running"
        else
            log_warn "  ! Supervisor service is not running"
        fi
        
        if systemctl is-enabled --quiet supervisor 2>/dev/null; then
            log_info "  ✓ Supervisor service is enabled"
        else
            log_warn "  ! Supervisor service is not enabled"
        fi
    fi
    
    validate_check "System services" "${service_check_passed}"
    return ${service_check_passed}
}

# Generate validation report
generate_report() {
    log_info "Deployment Validation Report"
    echo "=================================="
    echo "  Project: ${PROJECT_NAME}"
    echo "  Base path: ${BASE_PATH}"
    echo "  Validation timestamp: $(date)"
    echo ""
    echo "  Total checks: ${TOTAL_CHECKS}"
    echo "  Passed: ${PASSED_CHECKS}"
    echo "  Failed: ${FAILED_CHECKS}"
    echo ""
    
    local success_rate
    if [[ ${TOTAL_CHECKS} -gt 0 ]]; then
        success_rate=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
        echo "  Success rate: ${success_rate}%"
    else
        echo "  Success rate: N/A"
    fi
    
    echo "=================================="
    
    if [[ ${FAILED_CHECKS} -eq 0 ]]; then
        log_info "🎉 All validation checks passed!"
        return 0
    else
        log_error "❌ ${FAILED_CHECKS} validation check(s) failed"
        return 1
    fi
}

# Main execution function
main() {
    log_info "Starting deployment validation"
    log_info "Project: ${PROJECT_NAME}"
    log_info "Base path: ${BASE_PATH}"
    
    # Check required variables
    check_required_vars
    
    # Run all validation checks
    check_directories
    check_virtual_environment
    check_python_dependencies
    check_supervisor_configs
    check_log_setup
    check_application_code
    check_system_services
    
    # Generate final report
    if generate_report; then
        log_info "✅ Deployment validation completed successfully"
        return 0
    else
        log_error "🚨 Deployment validation completed with failures"
        return 1
    fi
}

# Help function
show_help() {
    cat << EOF
validate-deployment.sh - Deployment Validation Script

DESCRIPTION:
    This script validates a complete deployment setup by checking directories,
    virtual environment, dependencies, configurations, and services.

REQUIRED ENVIRONMENT VARIABLES:
    BASE_PATH     Base deployment path
    CODE_PATH     Application code path  
    VENV_PATH     Virtual environment path
    CONFIG_PATH   Configuration files path
    LOGS_PATH     Log files path
    PROJECT_NAME  Project name for validation

OPTIONAL ENVIRONMENT VARIABLES:
    SKIP_DEPENDENCY_CHECK   Skip Python dependency validation (default: false)
    SKIP_SUPERVISOR_CHECK   Skip Supervisor config validation (default: false)
    SUPERVISOR_CONF_DIR     Supervisor config directory (default: /etc/supervisor/conf.d)

USAGE:
    # Basic validation
    export BASE_PATH="/srv/deployments/myapp/dev/main"
    export CODE_PATH="/srv/deployments/myapp/dev/main/code"
    export VENV_PATH="/srv/deployments/myapp/dev/main/venv"
    export CONFIG_PATH="/srv/deployments/myapp/dev/main/config"
    export LOGS_PATH="/srv/deployments/myapp/dev/main/logs"
    export PROJECT_NAME="myapp"
    ./validate-deployment.sh
    
    # Skip specific checks
    export SKIP_DEPENDENCY_CHECK="true"
    export SKIP_SUPERVISOR_CHECK="true"
    ./validate-deployment.sh

VALIDATION CHECKS:
    ✓ Directory structure
    ✓ Virtual environment
    ✓ Python dependencies
    ✓ Supervisor configurations  
    ✓ Log setup
    ✓ Application code
    ✓ System services

EXIT CODES:
    0  Success - All validations passed
    1  Error - One or more validations failed

EXAMPLES:
    # Full validation
    BASE_PATH="/srv/app" CODE_PATH="/srv/app/code" VENV_PATH="/srv/app/venv" CONFIG_PATH="/srv/app/config" LOGS_PATH="/srv/app/logs" PROJECT_NAME="webapp" ./validate-deployment.sh
    
    # Skip dependency and supervisor checks
    BASE_PATH="/opt/app" CODE_PATH="/opt/app/src" VENV_PATH="/opt/app/venv" CONFIG_PATH="/opt/app/etc" LOGS_PATH="/opt/app/var/log" PROJECT_NAME="myapp" SKIP_DEPENDENCY_CHECK="true" SKIP_SUPERVISOR_CHECK="true" ./validate-deployment.sh
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
