#!/bin/bash
# view-logs.sh - View deployment service logs for debugging
# 
# Usage: ./logs <project> <environment> <service> [lines]
#
# Parameters:
#   project      - Project name (e.g., sampleapp, uno-admin)
#   environment  - Environment name (dev, stage, qa, prod)
#   service      - Service name (web, worker, beat, or supervisor service name)
#   lines        - Number of lines to show (optional, default: 50)
#
# Examples:
#   ./logs sampleapp dev web
#   ./logs sampleapp dev worker 100
#   ./logs sampleapp dev beat
#   ./logs uno-admin dev web 200

set -e  # Exit on any error

# Source common logging utilities
source "$(dirname "$0")/logging-utils.sh"

# Show usage information
show_usage() {
    cat << EOF
Usage: ./logs <project> <environment> <service> [lines]

PARAMETERS:
    project       Project name (e.g., sampleapp, uno-admin)
    environment   Environment name (dev, stage, qa, prod)
    service       Service name (web, worker, beat, or full supervisor name)
    lines         Number of lines to show (optional, default: 50)

SERVICES:
    web          - Web server (Gunicorn/Django)
    worker       - Background task workers (Celery)
    beat         - Task scheduler (Celery Beat)
    
    Or use full supervisor service names like:
    - sampleapp-web
    - sampleapp-worker_00
    - sampleapp-beat

LOG TYPES:
    - Supervisor logs (stdout/stderr from service processes)
    - Application logs (from deployment logs directory)
    - System logs (supervisor daemon logs)

EXAMPLES:
    # View web server logs
    ./logs sampleapp dev web
    
    # View worker logs with more lines
    ./logs sampleapp dev worker 100
    
    # View beat scheduler logs
    ./logs sampleapp dev beat
    
    # View specific worker process
    ./logs sampleapp dev sampleapp-worker_00
    
    # View logs with custom line count
    ./logs uno-admin dev web 200

NOTES:
    - Logs are shown from newest to oldest
    - Use Ctrl+C to exit if viewing large log files
    - Supervisor service names are auto-detected if not found

EOF
}

# Validate parameters
validate_parameters() {
    if [[ $# -lt 3 ]]; then
        log_error "Missing required parameters"
        show_usage
        exit 1
    fi
    
    PROJECT="$1"
    ENVIRONMENT="$2"
    SERVICE="$3"
    LINES="${4:-50}"
    
    # Validate project name
    if [[ ! "$PROJECT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid project name '$PROJECT'. Use only letters, numbers, hyphens, and underscores."
        exit 1
    fi
    
    # Validate environment name
    if [[ ! "$ENVIRONMENT" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid environment name '$ENVIRONMENT'. Use only letters, numbers, hyphens, and underscores."
        exit 1
    fi
    
    # Validate service name
    if [[ ! "$SERVICE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid service name '$SERVICE'. Use only letters, numbers, hyphens, and underscores."
        exit 1
    fi
    
    # Validate lines parameter
    if ! [[ "$LINES" =~ ^[0-9]+$ ]]; then
        log_error "Invalid lines parameter '$LINES'. Must be a number."
        exit 1
    fi
    
    log_info "Project: $PROJECT"
    log_info "Environment: $ENVIRONMENT"
    log_info "Service: $SERVICE"
    log_info "Lines: $LINES"
}

# Find deployment path
find_deployment_path() {
    local deployment_base="/srv/deployments/$PROJECT/$ENVIRONMENT"
    
    # Try to find the branch directory
    if [[ -d "$deployment_base" ]]; then
        local branch_dirs=($(find "$deployment_base" -maxdepth 1 -type d ! -path "$deployment_base" 2>/dev/null))
        if [[ ${#branch_dirs[@]} -eq 1 ]]; then
            echo "${branch_dirs[0]}"
            return 0
        elif [[ ${#branch_dirs[@]} -gt 1 ]]; then
            # Multiple branches, try main first
            if [[ -d "$deployment_base/main" ]]; then
                echo "$deployment_base/main"
                return 0
            else
                echo "${branch_dirs[0]}"
                return 0
            fi
        fi
    fi
    
    log_error "Deployment not found for $PROJECT/$ENVIRONMENT"
    log_error "Available deployments:"
    if [[ -d "/srv/deployments" ]]; then
        find /srv/deployments -maxdepth 3 -type d -name "*" | grep -E "/[^/]+/[^/]+/[^/]+$" | sort || true
    fi
    exit 1
}

# Determine supervisor service name
get_supervisor_service_name() {
    local service="$1"
    local project="$2"
    
    # If service already looks like a full supervisor name, use it
    if [[ "$service" == *"-"* ]]; then
        echo "$service"
        return 0
    fi
    
    # Map common service names to supervisor names
    case "$service" in
        "web")
            echo "${project}-web"
            ;;
        "worker")
            echo "${project}-worker"
            ;;
        "beat")
            echo "${project}-beat"
            ;;
        *)
            echo "${project}-${service}"
            ;;
    esac
}

# Colors for output (matching status script)
HEADER_COLOR='\033[1;36m'  # Cyan bold
TABLE_HEADER='\033[1;37m'  # White bold
SUCCESS_COLOR='\033[0;32m' # Green
WARNING_COLOR='\033[1;33m' # Yellow
ERROR_COLOR='\033[0;31m'   # Red
NC='\033[0m'               # No Color

# Print colored text only if output is to terminal
print_colored() {
    local color="$1"
    local text="$2"
    if [[ -t 1 ]]; then
        echo -e "${color}${text}${NC}"
    else
        echo "$text"
    fi
}

# Show supervisor logs
show_supervisor_logs() {
    local service_name="$1"
    local lines="$2"
    local project="$3"
    
    log_info "Checking Supervisor logs for service: $service_name"
    
    # Try to get supervisor logs
    local supervisor_output=$(sudo supervisorctl tail "$service_name" "$lines" 2>/dev/null || sudo supervisorctl tail "$project:$service_name" "$lines" 2>/dev/null || echo "")
    
    if [[ -n "$supervisor_output" ]]; then
        echo
        print_colored "$HEADER_COLOR" "=== SUPERVISOR STDOUT LOGS ($service_name) ==="
        echo "$supervisor_output"
        echo
    fi
    
    # Try to get supervisor error logs
    local supervisor_error=$(sudo supervisorctl tail "$service_name" stderr "$lines" 2>/dev/null || sudo supervisorctl tail "$project:$service_name" stderr "$lines" 2>/dev/null || echo "")
    
    if [[ -n "$supervisor_error" ]]; then
        echo
        print_colored "$ERROR_COLOR" "=== SUPERVISOR STDERR LOGS ($service_name) ==="
        echo "$supervisor_error"
        echo
    fi
    
    # If no supervisor logs found, show available services
    if [[ -z "$supervisor_output" && -z "$supervisor_error" ]]; then
        log_warn "No supervisor logs found for '$service_name'"
        log_info "Available supervisor services:"
        sudo supervisorctl status | grep -E "^$project" || sudo supervisorctl status
    fi
}

# Show application logs from deployment directory
show_application_logs() {
    local deployment_path="$1"
    local service="$2"
    local lines="$3"
    
    local logs_dir="$deployment_path/logs"
    
    if [[ ! -d "$logs_dir" ]]; then
        log_warn "No application logs directory found at: $logs_dir"
        return
    fi
    
    log_info "Checking application logs in: $logs_dir"
    
    # Look for service-specific log files
    local log_files=()
    
    # Check supervisor logs directory
    if [[ -d "$logs_dir/supervisor" ]]; then
        case "$service" in
            "web"|"*-web")
                log_files+=("$logs_dir/supervisor/web.log" "$logs_dir/supervisor/web_error.log")
                ;;
            "worker"|"*-worker"*)
                log_files+=("$logs_dir/supervisor/worker.log" "$logs_dir/supervisor/worker_error.log")
                ;;
            "beat"|"*-beat")
                log_files+=("$logs_dir/supervisor/beat.log" "$logs_dir/supervisor/beat_error.log")
                ;;
        esac
    fi
    
    # Check app logs directory
    if [[ -d "$logs_dir/app" ]]; then
        log_files+=("$logs_dir/app/django.log" "$logs_dir/app/celery.log" "$logs_dir/app/application.log")
    fi
    
    # Show existing log files
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" && -s "$log_file" ]]; then
            echo
            print_colored "$HEADER_COLOR" "=== APPLICATION LOG: $(basename "$log_file") ==="
            tail -n "$lines" "$log_file" 2>/dev/null || log_warn "Could not read $log_file"
            echo
        fi
    done
    
    # If no specific logs found, show what's available
    if [[ ${#log_files[@]} -eq 0 ]] || ! ls "${log_files[@]}" >/dev/null 2>&1; then
        log_info "Available log files in $logs_dir:"
        find "$logs_dir" -name "*.log" -type f 2>/dev/null | head -10 || log_warn "No log files found"
    fi
}

# Show recent deployment logs
show_deployment_logs() {
    local project="$1"
    local lines="$2"
    
    local deployment_tool_logs="$(dirname "$(dirname "${BASH_SOURCE[0]}")")/logs"
    
    if [[ -d "$deployment_tool_logs" ]]; then
        log_info "Checking recent deployment logs..."
        
        # Find recent deployment logs for this project
        local recent_logs=$(find "$deployment_tool_logs" -name "*.log" -type f -exec grep -l "$project" {} \; 2>/dev/null | sort -r | head -3)
        
        if [[ -n "$recent_logs" ]]; then
            echo
            print_colored "$HEADER_COLOR" "=== RECENT DEPLOYMENT LOGS ==="
            for log_file in $recent_logs; do
                echo
                print_colored "$TABLE_HEADER" "--- $(basename "$log_file") ---"
                tail -n "$((lines / 3))" "$log_file" 2>/dev/null | grep -A5 -B5 "$project" || true
            done
            echo
        fi
    fi
}

# Main execution function
main() {
    # Validate input parameters
    validate_parameters "$@"
    
    # Find deployment path
    local deployment_path
    deployment_path=$(find_deployment_path)
    
    if [[ -z "$deployment_path" ]]; then
        exit 1
    fi
    
    log_info "Deployment path: $deployment_path"
    
    # Get supervisor service name
    local supervisor_service_name
    supervisor_service_name=$(get_supervisor_service_name "$SERVICE" "$PROJECT")
    
    echo
    print_colored "$HEADER_COLOR" "=================================================================================="
    print_colored "$HEADER_COLOR" "SERVICE LOGS: $PROJECT/$ENVIRONMENT/$SERVICE"
    print_colored "$HEADER_COLOR" "=================================================================================="
    
    # Show supervisor logs
    show_supervisor_logs "$supervisor_service_name" "$LINES" "$PROJECT"
    
    # Show application logs
    show_application_logs "$deployment_path" "$SERVICE" "$LINES"
    
    # Show recent deployment logs
    show_deployment_logs "$PROJECT" "$LINES"
    
    echo
    print_colored "$HEADER_COLOR" "=================================================================================="
    print_colored "$HEADER_COLOR" "END OF LOGS"
    print_colored "$HEADER_COLOR" "=================================================================================="
}

# Handle command line arguments
case "${1:-}" in
    -h|--help|help|"")
        show_usage
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
