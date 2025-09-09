#!/bin/bash
# install-nginx-configs.sh - Install Nginx configurations for deployment
#
# This script installs generated nginx configurations to the system nginx directory
# and enables them by creating symlinks in sites-enabled.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check required environment variables
check_environment() {
    local required_vars=(
        "PROJECT_NAME"
        "NORMALIZED_BRANCH"
        "CONFIG_PATH"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            print_error "Required environment variable $var is not set"
            exit 1
        fi
    done
}

# Install nginx configurations
install_nginx_configs() {
    local nginx_config_dir="${CONFIG_PATH}/nginx"
    local sites_available="/etc/nginx/sites-available"
    local sites_enabled="/etc/nginx/sites-enabled"
    
    print_info "Installing nginx configurations for ${PROJECT_NAME}-${NORMALIZED_BRANCH}"
    
    # Check if nginx config directory exists
    if [[ ! -d "$nginx_config_dir" ]]; then
        print_warning "No nginx configurations found at $nginx_config_dir"
        return 0
    fi
    
    # Find all .conf files in the nginx config directory
    local config_files=($(find "$nginx_config_dir" -name "*.conf" -type f))
    
    if [[ ${#config_files[@]} -eq 0 ]]; then
        print_warning "No nginx configuration files found"
        return 0
    fi
    
    print_info "Found ${#config_files[@]} nginx configuration file(s)"
    
    # Install each configuration file
    for config_file in "${config_files[@]}"; do
        local filename=$(basename "$config_file")
        local site_name="${filename%.conf}"
        
        print_info "Installing nginx config: $filename"
        
        # Copy to sites-available
        if sudo cp "$config_file" "$sites_available/"; then
            print_success "Copied $filename to sites-available"
        else
            print_error "Failed to copy $filename to sites-available"
            exit 1
        fi
        
        # Create symlink in sites-enabled
        if sudo ln -sf "$sites_available/$filename" "$sites_enabled/"; then
            print_success "Enabled site: $site_name"
        else
            print_error "Failed to enable site: $site_name"
            exit 1
        fi
    done
    
    # Test nginx configuration
    print_info "Testing nginx configuration..."
    if sudo nginx -t; then
        print_success "Nginx configuration test passed"
    else
        print_error "Nginx configuration test failed"
        exit 1
    fi
    
    # Reload nginx
    print_info "Reloading nginx..."
    if sudo systemctl reload nginx; then
        print_success "Nginx reloaded successfully"
    else
        print_error "Failed to reload nginx"
        exit 1
    fi
    
    print_success "Nginx configurations installed and enabled"
}

# Add domains to /etc/hosts for local testing
add_hosts_entries() {
    local nginx_config_dir="${CONFIG_PATH}/nginx"
    
    # Extract domains from nginx config files
    local domains=()
    if [[ -d "$nginx_config_dir" ]]; then
        while IFS= read -r domain; do
            if [[ -n "$domain" && "$domain" != "localhost" && "$domain" != "127.0.0.1" ]]; then
                domains+=("$domain")
            fi
        done < <(grep -h "server_name" "$nginx_config_dir"/*.conf 2>/dev/null | awk '{print $2}' | tr -d ';' | sort -u)
    fi
    
    if [[ ${#domains[@]} -gt 0 ]]; then
        print_info "Adding domains to /etc/hosts for local testing..."
        
        for domain in "${domains[@]}"; do
            # Check if domain already exists in /etc/hosts
            if ! grep -q "127.0.0.1.*$domain" /etc/hosts; then
                if echo "127.0.0.1 $domain" | sudo tee -a /etc/hosts > /dev/null; then
                    print_success "Added $domain to /etc/hosts"
                else
                    print_warning "Failed to add $domain to /etc/hosts"
                fi
            else
                print_info "Domain $domain already exists in /etc/hosts"
            fi
        done
    fi
}

# Display deployment information
show_deployment_info() {
    local nginx_config_dir="${CONFIG_PATH}/nginx"
    
    if [[ -d "$nginx_config_dir" ]]; then
        print_info "Nginx deployment completed for ${PROJECT_NAME}-${NORMALIZED_BRANCH}"
        
        # Show enabled sites
        local config_files=($(find "$nginx_config_dir" -name "*.conf" -type f))
        if [[ ${#config_files[@]} -gt 0 ]]; then
            echo
            print_info "Enabled sites:"
            for config_file in "${config_files[@]}"; do
                local domain=$(grep "server_name" "$config_file" | awk '{print $2}' | tr -d ';' | head -1)
                local port=$(grep -o "127.0.0.1:[0-9]*" "$config_file" | head -1 | cut -d: -f2)
                echo "  • http://$domain/ → http://127.0.0.1:$port/"
            done
            echo
        fi
        
        # Show instructions
        print_info "Test your deployment:"
        for config_file in "${config_files[@]}"; do
            local domain=$(grep "server_name" "$config_file" | awk '{print $2}' | tr -d ';' | head -1)
            echo "  curl http://$domain/"
        done
    fi
}

# Main execution
main() {
    print_info "Starting nginx configuration installation"
    
    check_environment
    install_nginx_configs
    add_hosts_entries
    show_deployment_info
    
    print_success "Nginx configuration installation completed"
}

# Execute main function
main "$@"
