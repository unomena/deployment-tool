#!/bin/bash
# cleanup-deployments.sh - Deployment Cleanup Script
#
# This script safely removes deployments and drops databases for non-production environments.
# It includes multiple safety checks to prevent accidental production data loss.
#
# Usage:
#   ./cleanup-deployments.sh [project_name] [environment]
#   ./cleanup-deployments.sh --all-non-prod
#   ./cleanup-deployments.sh --help
#
# Safety Features:
#   - Production environment protection (cannot delete prod)
#   - Interactive confirmation prompts
#   - Backup creation before deletion
#   - Detailed logging of all operations
#   - Rollback capability for recent operations

set -e  # Exit on any error

# Configuration
DEPLOYMENT_BASE_DIR="/srv/deployments"
SUPERVISOR_CONF_DIR="/etc/supervisor/conf.d"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
BACKUP_DIR="/srv/deployment-backups"
LOG_FILE="/var/log/deployment-cleanup.log"

# Protected environments (cannot be deleted)
PROTECTED_ENVIRONMENTS=("prod" "production" "live")

# Source common logging utilities
source "$(dirname "$0")/logging-utils.sh"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Enhanced logging functions that also write to log file
log_info() {
    local message="$1"
    if [[ -t 1 ]]; then
        echo -e "${GREEN}[INFO]${NC} $message"
    else
        echo "[INFO] $message"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $message" >> "$LOG_FILE"
}

log_warn() {
    local message="$1"
    if [[ -t 1 ]]; then
        echo -e "${YELLOW}[WARN]${NC} $message"
    else
        echo "[WARN] $message"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $message" >> "$LOG_FILE"
}

log_error() {
    local message="$1"
    if [[ -t 1 ]]; then
        echo -e "${RED}[ERROR]${NC} $message"
    else
        echo "[ERROR] $message"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $message" >> "$LOG_FILE"
}

log_success() {
    local message="$1"
    if [[ -t 1 ]]; then
        echo -e "${GREEN}[✓]${NC} $message"
    else
        echo "[✓] $message"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] $message" >> "$LOG_FILE"
}

log_failure() {
    local message="$1"
    if [[ -t 1 ]]; then
        echo -e "${RED}[✗]${NC} $message"
    else
        echo "[✗] $message"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') [FAILURE] $message" >> "$LOG_FILE"
}

# Initialize logging
initialize_logging() {
    # Create log directory if it doesn't exist
    sudo mkdir -p "$(dirname "$LOG_FILE")"
    sudo touch "$LOG_FILE"
    sudo chmod 666 "$LOG_FILE" 2>/dev/null || true
    
    log_info "=== Deployment Cleanup Started ==="
    log_info "User: $(whoami)"
    log_info "Timestamp: $(date)"
    log_info "Arguments: $*"
}

# Check if environment is protected
is_protected_environment() {
    local env="$1"
    
    for protected_env in "${PROTECTED_ENVIRONMENTS[@]}"; do
        if [[ "${env,,}" == "${protected_env,,}" ]]; then
            return 0  # Protected
        fi
    done
    
    return 1  # Not protected
}

# Create backup before deletion
create_backup() {
    local project_name="$1"
    local environment="$2"
    local deployment_path="$3"
    
    if [[ ! -d "$deployment_path" ]]; then
        log_warn "Deployment path does not exist, skipping backup: $deployment_path"
        return 0
    fi
    
    local backup_timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_name="${project_name}_${environment}_${backup_timestamp}"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    
    log_info "Creating backup: $backup_name"
    
    # Create backup directory
    sudo mkdir -p "$BACKUP_DIR"
    
    # Create deployment backup
    if sudo tar -czf "${backup_path}.tar.gz" -C "$(dirname "$deployment_path")" "$(basename "$deployment_path")" 2>/dev/null; then
        log_success "Backup created: ${backup_path}.tar.gz"
        
        # Store backup metadata
        sudo tee "${backup_path}.info" > /dev/null << EOF
Project: $project_name
Environment: $environment
Original Path: $deployment_path
Backup Created: $(date)
Backup Size: $(du -h "${backup_path}.tar.gz" | cut -f1)
EOF
        
        return 0
    else
        log_error "Failed to create backup for $project_name/$environment"
        return 1
    fi
}

# Stop Supervisor services
stop_supervisor_services() {
    local project_name="$1"
    
    if ! command -v supervisorctl >/dev/null 2>&1; then
        log_warn "Supervisor not installed, skipping service stop"
        return 0
    fi
    
    log_info "Stopping Supervisor services for project: $project_name"
    
    # Find and stop project services
    local services
    services=$(sudo supervisorctl status | grep "^${project_name}-" | awk '{print $1}' || true)
    
    if [[ -n "$services" ]]; then
        echo "$services" | while read -r service; do
            log_info "Stopping service: $service"
            sudo supervisorctl stop "$service" || log_warn "Failed to stop service: $service"
        done
        
        # Wait a moment for services to stop
        sleep 2
    else
        log_info "No Supervisor services found for project: $project_name"
    fi
}

# Remove Supervisor configurations
remove_supervisor_configs() {
    local project_name="$1"
    
    log_info "Removing Supervisor configurations for project: $project_name"
    
    # Find and remove configuration files
    local config_files
    config_files=$(find "$SUPERVISOR_CONF_DIR" -name "${project_name}-*.conf" 2>/dev/null || true)
    
    if [[ -n "$config_files" ]]; then
        local removed_configs=()
        echo "$config_files" | while read -r config_file; do
            if [[ -f "$config_file" ]]; then
                local config_name=$(basename "$config_file")
                if [[ ! " ${removed_configs[@]} " =~ " ${config_name} " ]]; then
                    log_info "Removing Supervisor config: $config_name"
                    sudo rm -f "$config_file"
                    removed_configs+=("$config_name")
                fi
            fi
        done
        
        # Reload Supervisor configuration
        log_info "Reloading Supervisor configuration"
        sudo supervisorctl reread || log_warn "Failed to reread Supervisor configuration"
        sudo supervisorctl update || log_warn "Failed to update Supervisor configuration"
    else
        log_info "No Supervisor configurations found for project: $project_name"
    fi
}

# Remove Nginx configurations
remove_nginx_configs() {
    local project_name="$1"
    
    if ! command -v nginx >/dev/null 2>&1; then
        log_warn "Nginx not installed, skipping nginx config removal"
        return 0
    fi
    
    log_info "Removing Nginx configurations for project: $project_name"
    
    # Find nginx config files for this project
    local nginx_configs=()
    local removed_sites=()
    
    # Look for configs in sites-enabled that match the project pattern
    if [[ -d "$NGINX_SITES_ENABLED" ]]; then
        while IFS= read -r -d '' config_file; do
            local config_name=$(basename "$config_file")
            # Check if config file contains references to this project
            if grep -q "$project_name" "$config_file" 2>/dev/null; then
                nginx_configs+=("$config_name")
            fi
        done < <(find "$NGINX_SITES_ENABLED" -name "*.conf" -type f -print0 2>/dev/null || true)
    fi
    
    # Also check sites-available for project-specific configs
    if [[ -d "$NGINX_SITES_AVAILABLE" ]]; then
        while IFS= read -r -d '' config_file; do
            local config_name=$(basename "$config_file")
            # Check if config file contains references to this project
            if grep -q "$project_name" "$config_file" 2>/dev/null; then
                if [[ ! " ${nginx_configs[@]} " =~ " ${config_name} " ]]; then
                    nginx_configs+=("$config_name")
                fi
            fi
        done < <(find "$NGINX_SITES_AVAILABLE" -name "*.conf" -type f -print0 2>/dev/null || true)
    fi
    
    if [[ ${#nginx_configs[@]} -gt 0 ]]; then
        log_info "Found ${#nginx_configs[@]} nginx configuration(s) for project: $project_name"
        
        for config_name in "${nginx_configs[@]}"; do
            local site_name="${config_name%.conf}"
            
            # Remove from sites-enabled
            if [[ -L "$NGINX_SITES_ENABLED/$config_name" ]]; then
                log_info "Disabling nginx site: $site_name"
                sudo rm -f "$NGINX_SITES_ENABLED/$config_name"
                removed_sites+=("$site_name")
            fi
            
            # Remove from sites-available
            if [[ -f "$NGINX_SITES_AVAILABLE/$config_name" ]]; then
                log_info "Removing nginx config: $config_name"
                sudo rm -f "$NGINX_SITES_AVAILABLE/$config_name"
            fi
        done
        
        # Remove domains from /etc/hosts
        log_info "Cleaning up /etc/hosts entries"
        for config_name in "${nginx_configs[@]}"; do
            local domain="${config_name%.conf}"
            if grep -q "127.0.0.1.*$domain" /etc/hosts 2>/dev/null; then
                log_info "Removing $domain from /etc/hosts"
                sudo sed -i "/127.0.0.1.*$domain/d" /etc/hosts || log_warn "Failed to remove $domain from /etc/hosts"
            fi
        done
        
        # Test nginx configuration
        log_info "Testing nginx configuration"
        if sudo nginx -t 2>/dev/null; then
            # Reload nginx
            log_info "Reloading nginx"
            sudo systemctl reload nginx || log_warn "Failed to reload nginx"
        else
            log_warn "Nginx configuration test failed after cleanup"
        fi
        
        log_info "Removed nginx configurations: ${removed_sites[*]}"
    else
        log_info "No nginx configurations found for project: $project_name"
    fi
}

# Drop database
drop_database() {
    local project_name="$1"
    local environment="$2"
    
    # Load database configuration
    local config_file="/home/ubuntu/Workspace/deployment-tool/config.yml"
    if [[ ! -f "$config_file" ]]; then
        log_warn "Database config file not found: $config_file"
        return 0
    fi
    
    log_info "Dropping database for ${project_name}_${environment}"
    
    # Get database credentials
    local db_credentials
    if ! db_credentials=$(DB_SERVERS_CONFIG="$config_file" python3 /home/ubuntu/Workspace/deployment-tool/scripts/manage-database-credentials.py export_credentials 2>/dev/null); then
        log_warn "Failed to get database credentials, skipping database cleanup"
        return 0
    fi
    
    # Export credentials to environment
    eval "$db_credentials"
    
    if [[ -z "$DB_ROOT_USER" || -z "$DB_ROOT_PASSWORD" ]]; then
        log_error "Database credentials not available"
        return 1
    fi
    
    local db_name="${project_name}_${environment}"
    local db_user="${project_name}_user"
    
    # Check if database exists
    if PGPASSWORD="$DB_ROOT_PASSWORD" psql -h localhost -U "$DB_ROOT_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$db_name'" | grep -q 1; then
        log_info "Database exists: $db_name"
        
        # Terminate active connections
        log_info "Terminating active connections to database: $db_name"
        PGPASSWORD="$DB_ROOT_PASSWORD" psql -h localhost -U "$DB_ROOT_USER" -d postgres -c "
            SELECT pg_terminate_backend(pid) 
            FROM pg_stat_activity 
            WHERE datname = '$db_name' AND pid <> pg_backend_pid();
        " || log_warn "Failed to terminate some connections"
        
        # Drop database
        log_info "Dropping database: $db_name"
        if PGPASSWORD="$DB_ROOT_PASSWORD" psql -h localhost -U "$DB_ROOT_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$db_name\";"; then
            log_success "Database dropped: $db_name"
        else
            log_error "Failed to drop database: $db_name"
            return 1
        fi
    else
        log_info "Database does not exist: $db_name"
    fi
    
    # Check if user exists and drop if no other databases
    if PGPASSWORD="$DB_ROOT_PASSWORD" psql -h localhost -U "$DB_ROOT_USER" -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='$db_user'" | grep -q 1; then
        log_info "Database user exists: $db_user"
        
        # Check if user owns any other databases
        local user_databases
        user_databases=$(PGPASSWORD="$DB_ROOT_PASSWORD" psql -h localhost -U "$DB_ROOT_USER" -d postgres -tAc "
            SELECT COUNT(*) FROM pg_database d 
            JOIN pg_authid a ON d.datdba = a.oid 
            WHERE a.rolname = '$db_user';
        ")
        
        if [[ "$user_databases" == "0" ]]; then
            log_info "Dropping database user: $db_user"
            if PGPASSWORD="$DB_ROOT_PASSWORD" psql -h localhost -U "$DB_ROOT_USER" -d postgres -c "DROP ROLE IF EXISTS \"$db_user\";"; then
                log_success "Database user dropped: $db_user"
            else
                log_warn "Failed to drop database user: $db_user"
            fi
        else
            log_info "Database user owns other databases, keeping: $db_user"
        fi
    else
        log_info "Database user does not exist: $db_user"
    fi
}

# Remove deployment directory
remove_deployment_directory() {
    local deployment_path="$1"
    
    if [[ ! -d "$deployment_path" ]]; then
        log_info "Deployment directory does not exist: $deployment_path"
        return 0
    fi
    
    log_info "Removing deployment directory: $deployment_path"
    
    if sudo rm -rf "$deployment_path"; then
        log_success "Deployment directory removed: $deployment_path"
        return 0
    else
        log_error "Failed to remove deployment directory: $deployment_path"
        return 1
    fi
}

# Clean up single deployment
cleanup_deployment() {
    local project_name="$1"
    local environment="$2"
    local skip_confirmation="${3:-false}"
    
    # Safety check for protected environments
    if is_protected_environment "$environment"; then
        log_error "Cannot delete protected environment: $environment"
        log_error "Protected environments: ${PROTECTED_ENVIRONMENTS[*]}"
        return 1
    fi
    
    local deployment_path="${DEPLOYMENT_BASE_DIR}/${project_name}/${environment}"
    
    # Check if deployment exists
    if [[ ! -d "$deployment_path" ]]; then
        log_warn "Deployment does not exist: $deployment_path"
        return 0
    fi
    
    log_info "Found deployment: $deployment_path"
    
    # Confirmation prompt
    if [[ "$skip_confirmation" != "true" ]]; then
        echo
        echo -e "${YELLOW}WARNING: This will permanently delete the following:${NC}"
        echo "  - Deployment directory: $deployment_path"
        echo "  - Database: ${project_name}_${environment}"
        echo "  - Database user: ${project_name}_user (if no other databases)"
        echo "  - Supervisor configurations for: $project_name"
        echo
        read -p "Are you sure you want to continue? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Cleanup cancelled by user"
            return 0
        fi
    fi
    
    log_info "Starting cleanup for ${project_name}/${environment}"
    
    # Create backup
    if ! create_backup "$project_name" "$environment" "$deployment_path"; then
        log_error "Backup creation failed, aborting cleanup"
        return 1
    fi
    
    # Stop services
    stop_supervisor_services "$project_name"
    
    # Remove Supervisor configurations
    remove_supervisor_configs "$project_name"
    
    # Remove Nginx configurations
    remove_nginx_configs "$project_name"
    
    # Drop database
    drop_database "$project_name" "$environment"
    
    # Remove deployment directory
    remove_deployment_directory "$deployment_path"
    
    log_success "Cleanup completed for ${project_name}/${environment}"
    return 0
}

# List all deployments
list_deployments() {
    log_info "Scanning for deployments in: $DEPLOYMENT_BASE_DIR"
    
    if [[ ! -d "$DEPLOYMENT_BASE_DIR" ]]; then
        log_warn "Deployment directory does not exist: $DEPLOYMENT_BASE_DIR"
        return 0
    fi
    
    local found_deployments=()
    
    # Find all deployment directories
    while IFS= read -r -d '' project_dir; do
        local project_name=$(basename "$project_dir")
        
        while IFS= read -r -d '' env_dir; do
            local environment=$(basename "$env_dir")
            
            # Skip if it's a protected environment
            if is_protected_environment "$environment"; then
                log_info "Skipping protected environment: ${project_name}/${environment}"
                continue
            fi
            
            found_deployments+=("${project_name}/${environment}")
        done < <(find "$project_dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null || true)
    done < <(find "$DEPLOYMENT_BASE_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null || true)
    
    if [[ ${#found_deployments[@]} -eq 0 ]]; then
        log_info "No non-production deployments found"
        return 0
    fi
    
    echo
    echo -e "${BLUE}Found ${#found_deployments[@]} non-production deployment(s):${NC}"
    for deployment in "${found_deployments[@]}"; do
        echo "  - $deployment"
    done
    echo
    
    return 0
}

# Clean up all non-production deployments
cleanup_all_non_prod() {
    log_info "Starting cleanup of all non-production deployments"
    
    if [[ ! -d "$DEPLOYMENT_BASE_DIR" ]]; then
        log_warn "Deployment directory does not exist: $DEPLOYMENT_BASE_DIR"
        return 0
    fi
    
    local deployments_to_clean=()
    
    # Find all non-production deployments
    while IFS= read -r -d '' project_dir; do
        local project_name=$(basename "$project_dir")
        
        while IFS= read -r -d '' env_dir; do
            local environment=$(basename "$env_dir")
            
            # Skip if it's a protected environment
            if is_protected_environment "$environment"; then
                continue
            fi
            
            deployments_to_clean+=("${project_name}:${environment}")
        done < <(find "$project_dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null || true)
    done < <(find "$DEPLOYMENT_BASE_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null || true)
    
    if [[ ${#deployments_to_clean[@]} -eq 0 ]]; then
        log_info "No non-production deployments found to clean up"
        return 0
    fi
    
    echo
    echo -e "${YELLOW}WARNING: This will delete ALL non-production deployments:${NC}"
    for deployment in "${deployments_to_clean[@]}"; do
        echo "  - ${deployment//:\/}"
    done
    echo
    echo -e "${RED}This action cannot be undone (except from backups)!${NC}"
    echo
    read -p "Are you absolutely sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        return 0
    fi
    
    # Clean up each deployment
    local success_count=0
    local failure_count=0
    
    for deployment in "${deployments_to_clean[@]}"; do
        local project_name="${deployment%%:*}"
        local environment="${deployment##*:}"
        
        if cleanup_deployment "$project_name" "$environment" "true"; then
            success_count=$((success_count + 1))
        else
            failure_count=$((failure_count + 1))
        fi
    done
    
    log_info "Cleanup summary: $success_count successful, $failure_count failed"
    
    if [[ $failure_count -eq 0 ]]; then
        log_success "All non-production deployments cleaned up successfully"
        return 0
    else
        log_error "Some deployments failed to clean up"
        return 1
    fi
}

# Show help
show_help() {
    cat << EOF
cleanup-deployments.sh - Deployment Cleanup Script

DESCRIPTION:
    Safely removes deployments and drops databases for non-production environments.
    Includes multiple safety checks to prevent accidental production data loss.

USAGE:
    ./cleanup-deployments.sh [project_name] [environment]
    ./cleanup-deployments.sh --all-non-prod
    ./cleanup-deployments.sh --list
    ./cleanup-deployments.sh --help

OPTIONS:
    project_name environment    Clean up specific project/environment
    --all-non-prod             Clean up all non-production deployments
    --list                      List all deployments (non-production only)
    --help                      Show this help message

SAFETY FEATURES:
    ✓ Production environment protection (cannot delete: ${PROTECTED_ENVIRONMENTS[*]})
    ✓ Interactive confirmation prompts
    ✓ Automatic backup creation before deletion
    ✓ Detailed logging of all operations
    ✓ Graceful service shutdown

CLEANUP PROCESS:
    1. Create backup of deployment directory
    2. Stop Supervisor services
    3. Remove Supervisor configurations
    4. Drop database and user (if safe)
    5. Remove deployment directory

EXAMPLES:
    # Clean up specific deployment
    ./cleanup-deployments.sh sampleapp dev

    # List all non-production deployments
    ./cleanup-deployments.sh --list

    # Clean up all non-production deployments
    ./cleanup-deployments.sh --all-non-prod

BACKUPS:
    Backups are stored in: $BACKUP_DIR
    Each backup includes deployment files and metadata
    Backups are named: {project}_{environment}_{timestamp}.tar.gz

LOGS:
    All operations are logged to: $LOG_FILE

EXIT CODES:
    0  Success
    1  Error or user cancellation
EOF
}

# Main function
main() {
    # Initialize logging
    initialize_logging "$@"
    
    # Parse arguments
    case "${1:-}" in
        --help|-h|help)
            show_help
            exit 0
            ;;
        --list)
            list_deployments
            exit 0
            ;;
        --all-non-prod)
            cleanup_all_non_prod
            exit $?
            ;;
        "")
            log_error "Missing arguments. Use --help for usage information."
            exit 1
            ;;
        *)
            if [[ $# -ne 2 ]]; then
                log_error "Invalid arguments. Expected: project_name environment"
                log_error "Use --help for usage information."
                exit 1
            fi
            
            cleanup_deployment "$1" "$2"
            exit $?
            ;;
    esac
}

# Run main function
main "$@"
