#!/bin/bash
# deployment-status.sh - Generate deployment status report
#
# This script provides a comprehensive overview of all current deployments,
# their running services, exposed ports, and system status.

set -e  # Exit on any error

# Source common logging utilities
source "$(dirname "$0")/logging-utils.sh"

# Configuration
DEPLOYMENT_BASE_DIR="/srv/deployments"
SUPERVISOR_CONF_DIR="/etc/supervisor/conf.d"
NGINX_SITES_DIR="/etc/nginx/sites-enabled"

# Colors for terminal output (will be stripped in logs)
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

# Print section header
print_header() {
    local title="$1"
    local separator=$(printf '=%.0s' {1..80})
    
    echo
    print_colored "$HEADER_COLOR" "$separator"
    print_colored "$HEADER_COLOR" "$title"
    print_colored "$HEADER_COLOR" "$separator"
    echo
}

# Print table header
print_table_header() {
    print_colored "$TABLE_HEADER" "$1"
    print_colored "$TABLE_HEADER" "$(printf '=%.0s' {1..${#1}})"
}

# Get deployment information
get_deployment_info() {
    local project="$1"
    local environment="$2"
    local branch="$3"
    local deployment_path="$DEPLOYMENT_BASE_DIR/$project/$environment/$branch"
    
    # Check if deployment exists
    if [[ ! -d "$deployment_path" ]]; then
        return 1
    fi
    
    # Get basic info
    local config_file=""
    local python_version=""
    local django_version=""
    local last_modified=""
    
    # Find config file
    if [[ -f "$deployment_path/config/deploy-$environment.yml" ]]; then
        config_file="deploy-$environment.yml"
    fi
    
    # Get Python version if venv exists
    if [[ -f "$deployment_path/venv/bin/python" ]]; then
        python_version=$("$deployment_path/venv/bin/python" --version 2>/dev/null | cut -d' ' -f2 || echo "Unknown")
    fi
    
    # Get Django version if available
    if [[ -f "$deployment_path/venv/bin/python" && -d "$deployment_path/code" ]]; then
        django_version=$(cd "$deployment_path/code" && "$deployment_path/venv/bin/python" -c "import django; print(django.get_version())" 2>/dev/null || echo "Unknown")
    fi
    
    # Get last modified time
    if [[ -d "$deployment_path/code" ]]; then
        last_modified=$(stat -c %y "$deployment_path/code" 2>/dev/null | cut -d'.' -f1 || echo "Unknown")
    fi
    
    echo "$deployment_path|$config_file|$python_version|$django_version|$last_modified"
}

# Get supervisor services for a project
get_supervisor_services() {
    local project="$1"
    local services=()
    
    # Get all running services for this project from supervisorctl
    local all_services=$(sudo supervisorctl status "$project:*" 2>/dev/null | grep -E "^$project:" || true)
    
    if [[ -n "$all_services" ]]; then
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local service_full_name=$(echo "$line" | awk '{print $1}')
                local service_name=$(echo "$service_full_name" | cut -d':' -f2)
                local status="STOPPED"
                local pid=""
                
                if echo "$line" | grep -q "RUNNING"; then
                    status="RUNNING"
                    pid=$(echo "$line" | grep -o "pid [0-9]*" | cut -d' ' -f2)
                elif echo "$line" | grep -q "STOPPED"; then
                    status="STOPPED"
                elif echo "$line" | grep -q "FATAL"; then
                    status="FATAL"
                fi
                
                services+=("$service_name|$status|$pid")
            fi
        done <<< "$all_services"
    fi
    
    # Also check individual config files for services not in groups
    if [[ -d "$SUPERVISOR_CONF_DIR" ]]; then
        for config_file in "$SUPERVISOR_CONF_DIR"/${project}-*.conf; do
            if [[ -f "$config_file" ]]; then
                # Skip group configuration files
                if grep -q "^\[group:" "$config_file" 2>/dev/null; then
                    continue
                fi
                
                local service_name=$(basename "$config_file" .conf)
                
                # Skip if we already found this service in the group listing
                # Also skip if this is a multi-process service (numprocs > 1) that creates _XX variants
                local already_found=false
                for existing_service in "${services[@]}"; do
                    local existing_name=$(echo "$existing_service" | cut -d'|' -f1)
                    if [[ "$existing_name" == "$service_name" ]] || [[ "$existing_name" == "${service_name}_"* ]]; then
                        already_found=true
                        break
                    fi
                done
                
                if [[ "$already_found" == false ]]; then
                    local status="STOPPED"
                    local pid=""
                    
                    local supervisor_status=$(sudo supervisorctl status "$service_name" 2>/dev/null || echo "")
                    if [[ -n "$supervisor_status" ]]; then
                        if echo "$supervisor_status" | grep -q "RUNNING"; then
                            status="RUNNING"
                            pid=$(echo "$supervisor_status" | grep -o "pid [0-9]*" | cut -d' ' -f2)
                        elif echo "$supervisor_status" | grep -q "STOPPED"; then
                            status="STOPPED"
                        elif echo "$supervisor_status" | grep -q "FATAL"; then
                            status="FATAL"
                        fi
                    fi
                    
                    services+=("$service_name|$status|$pid")
                fi
            fi
        done
    fi
    
    printf '%s\n' "${services[@]}"
}

# Get port information from config files
get_port_info() {
    local project="$1"
    local environment="$2"
    local branch="$3"
    local deployment_path="$DEPLOYMENT_BASE_DIR/$project/$environment/$branch"
    local ports=()
    
    # Check supervisor configs for port information
    if [[ -d "$SUPERVISOR_CONF_DIR" ]]; then
        for config_file in "$SUPERVISOR_CONF_DIR"/${project}-*.conf; do
            if [[ -f "$config_file" ]]; then
                # Look for port numbers in the config file
                local found_ports=$(grep -o ":[0-9]\{4,5\}" "$config_file" 2>/dev/null | tr -d ':' | sort -u || true)
                for port in $found_ports; do
                    local service_name=$(basename "$config_file" .conf)
                    ports+=("$port|$service_name|supervisor")
                done
            fi
        done
    fi
    
    # Check nginx configs
    if [[ -d "$NGINX_SITES_DIR" ]]; then
        for nginx_config in "$NGINX_SITES_DIR"/*; do
            if [[ -f "$nginx_config" ]] && grep -q "$project" "$nginx_config" 2>/dev/null; then
                local nginx_ports=$(grep -o "listen [0-9]\{2,5\}" "$nginx_config" 2>/dev/null | cut -d' ' -f2 | sort -u || true)
                for port in $nginx_ports; do
                    ports+=("$port|nginx|web")
                done
            fi
        done
    fi
    
    # Check for common Django development ports in use
    local common_ports=("8000" "8001" "8002" "8003" "8004" "8005")
    for port in "${common_ports[@]}"; do
        if netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            local process_info=$(netstat -tlnp 2>/dev/null | grep ":$port " | head -1 | awk '{print $7}' | cut -d'/' -f2)
            if [[ -n "$process_info" ]]; then
                ports+=("$port|$process_info|network")
            fi
        fi
    done
    
    printf '%s\n' "${ports[@]}" | sort -t'|' -k1 -n | uniq
}

# Get system resource usage
get_system_info() {
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    local memory_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    local disk_usage=$(df -h / | awk 'NR==2{print $5}' | tr -d '%')
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
    
    echo "CPU: ${cpu_usage}% | Memory: ${memory_usage}% | Disk: ${disk_usage}% | Load: ${load_avg}"
}

# Main report generation
generate_report() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')
    
    print_header "DEPLOYMENT STATUS REPORT - $timestamp"
    
    # System overview
    print_table_header "SYSTEM OVERVIEW"
    echo "$(get_system_info)"
    echo
    
    # Find all deployments
    local deployments=()
    if [[ -d "$DEPLOYMENT_BASE_DIR" ]]; then
        while IFS= read -r -d '' project_dir; do
            local project=$(basename "$project_dir")
            if [[ -d "$project_dir" ]]; then
                while IFS= read -r -d '' env_dir; do
                    local environment=$(basename "$env_dir")
                    if [[ -d "$env_dir" ]]; then
                        while IFS= read -r -d '' branch_dir; do
                            local branch=$(basename "$branch_dir")
                            if [[ -d "$branch_dir" ]]; then
                                deployments+=("$project|$environment|$branch")
                            fi
                        done < <(find "$env_dir" -maxdepth 1 -type d ! -path "$env_dir" -print0 2>/dev/null)
                    fi
                done < <(find "$project_dir" -maxdepth 1 -type d ! -path "$project_dir" -print0 2>/dev/null)
            fi
        done < <(find "$DEPLOYMENT_BASE_DIR" -maxdepth 1 -type d ! -path "$DEPLOYMENT_BASE_DIR" -print0 2>/dev/null)
    fi
    
    if [[ ${#deployments[@]} -eq 0 ]]; then
        print_colored "$WARNING_COLOR" "No deployments found in $DEPLOYMENT_BASE_DIR"
        return
    fi
    
    # Deployments overview
    print_table_header "DEPLOYMENTS OVERVIEW"
    printf "%-15s %-12s %-10s %-12s %-12s %-20s\n" "PROJECT" "ENVIRONMENT" "BRANCH" "PYTHON" "DJANGO" "LAST MODIFIED"
    printf "%-15s %-12s %-10s %-12s %-12s %-20s\n" "-------" "-----------" "------" "------" "------" "-------------"
    
    for deployment in "${deployments[@]}"; do
        IFS='|' read -r project environment branch <<< "$deployment"
        local info=$(get_deployment_info "$project" "$environment" "$branch")
        if [[ -n "$info" ]]; then
            IFS='|' read -r path config_file python_version django_version last_modified <<< "$info"
            printf "%-15s %-12s %-10s %-12s %-12s %-20s\n" \
                "$project" "$environment" "$branch" "$python_version" "$django_version" "$last_modified"
        fi
    done
    echo
    
    # Services status
    print_table_header "SUPERVISOR SERVICES STATUS"
    printf "%-20s %-15s %-10s %-10s\n" "SERVICE" "PROJECT" "STATUS" "PID"
    printf "%-20s %-15s %-10s %-10s\n" "-------" "-------" "------" "---"
    
    local all_services_found=false
    for deployment in "${deployments[@]}"; do
        IFS='|' read -r project environment branch <<< "$deployment"
        local services=$(get_supervisor_services "$project")
        if [[ -n "$services" ]]; then
            all_services_found=true
            while IFS='|' read -r service_name status pid; do
                local status_color=""
                case "$status" in
                    "RUNNING") status_color="$SUCCESS_COLOR" ;;
                    "STOPPED") status_color="$WARNING_COLOR" ;;
                    "FATAL") status_color="$ERROR_COLOR" ;;
                esac
                
                printf "%-20s %-15s " "$service_name" "$project"
                if [[ -t 1 ]]; then
                    printf "${status_color}%-10s${NC} %-10s\n" "$status" "${pid:-N/A}"
                else
                    printf "%-10s %-10s\n" "$status" "${pid:-N/A}"
                fi
            done <<< "$services"
        fi
    done
    
    if [[ "$all_services_found" == false ]]; then
        print_colored "$WARNING_COLOR" "No supervisor services found"
    fi
    echo
    
    # Ports and networking
    print_table_header "EXPOSED PORTS AND SERVICES"
    printf "%-8s %-20s %-15s %-15s\n" "PORT" "SERVICE/PROCESS" "TYPE" "PROJECT"
    printf "%-8s %-20s %-15s %-15s\n" "----" "---------------" "----" "-------"
    
    local all_ports_found=false
    for deployment in "${deployments[@]}"; do
        IFS='|' read -r project environment branch <<< "$deployment"
        local ports=$(get_port_info "$project" "$environment" "$branch")
        if [[ -n "$ports" ]]; then
            all_ports_found=true
            while IFS='|' read -r port service type; do
                printf "%-8s %-20s %-15s %-15s\n" "$port" "$service" "$type" "$project"
            done <<< "$ports"
        fi
    done
    
    if [[ "$all_ports_found" == false ]]; then
        print_colored "$WARNING_COLOR" "No exposed ports detected"
    fi
    echo
    
    # Quick health check
    print_table_header "QUICK HEALTH CHECK"
    
    # Check supervisor daemon
    if systemctl is-active --quiet supervisor; then
        print_colored "$SUCCESS_COLOR" "✓ Supervisor daemon is running"
    else
        print_colored "$ERROR_COLOR" "✗ Supervisor daemon is not running"
    fi
    
    # Check nginx
    if systemctl is-active --quiet nginx; then
        print_colored "$SUCCESS_COLOR" "✓ Nginx is running"
    else
        print_colored "$WARNING_COLOR" "! Nginx is not running"
    fi
    
    # Check postgresql
    if systemctl is-active --quiet postgresql; then
        print_colored "$SUCCESS_COLOR" "✓ PostgreSQL is running"
    else
        print_colored "$WARNING_COLOR" "! PostgreSQL is not running"
    fi
    
    echo
    print_header "END OF REPORT"
}

# Handle command line arguments
case "${1:-}" in
    -h|--help|help)
        cat << EOF
Usage: $0 [OPTIONS]

Generate a comprehensive deployment status report showing:
- All current deployments and their details
- Supervisor services status
- Exposed ports and networking
- System resource usage
- Quick health checks

OPTIONS:
    -h, --help    Show this help message
    -q, --quiet   Suppress colored output (same as redirecting to file)

EXAMPLES:
    $0                    # Generate full report
    $0 > report.txt       # Save report to file (colors automatically stripped)
    $0 | less -R          # View with pager (preserves colors)

EOF
        exit 0
        ;;
    -q|--quiet)
        # Redirect stdout to remove colors
        exec > >(cat)
        ;;
esac

# Check if running with appropriate permissions
if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    log_warn "Some information may be limited without sudo privileges"
    log_warn "Run with sudo for complete service status information"
    echo
fi

# Generate the report
generate_report
