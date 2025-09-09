#!/usr/bin/env python3
"""
Generate nginx reverse proxy configurations for deployed services.
This script creates nginx site configurations based on service domains and ports.
"""

import os
import sys
import json
import logging
from pathlib import Path
from typing import Dict, List, Any

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

class NginxConfigGenerator:
    def __init__(self):
        """Initialize the nginx configuration generator"""
        self.project_name = os.getenv('PROJECT_NAME', 'unknown')
        self.normalized_branch = os.getenv('NORMALIZED_BRANCH', 'main')
        self.base_path = Path(os.getenv('BASE_PATH', '/srv/deployments'))
        self.config_path = Path(os.getenv('CONFIG_PATH', self.base_path / self.project_name / self.normalized_branch / 'config'))
        
        # Load deployment configuration
        config_data = os.getenv('CONFIG_DATA', '{}')
        try:
            self.config = json.loads(config_data)
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse CONFIG_DATA: {e}")
            sys.exit(1)
        
        # Environment variables for template substitution
        self.env_vars = dict(os.environ)
        
        # Ensure nginx config directory exists
        self.nginx_config_path = self.config_path / 'nginx'
        self.nginx_config_path.mkdir(parents=True, exist_ok=True)
        
        logger.info(f"Generating nginx configs for {self.project_name}-{self.normalized_branch}")

    def _get_service_domain(self, service: Dict[str, Any]) -> str:
        """Get domain for service, with service-level override capability"""
        # Check for service-level domain override first
        if 'domain' in service:
            return service['domain']
        
        # Fall back to root domain or default pattern
        default_domain = f"{self.project_name}-{self.normalized_branch}"
        return self.config.get('domain', default_domain)

    def _get_service_port(self, service: Dict[str, Any]) -> int:
        """Get the port for a service"""
        return service.get('port', 8000)

    def _is_web_service(self, service: Dict[str, Any]) -> bool:
        """Check if service is a web service that needs nginx configuration"""
        service_type = service.get('type', '')
        return service_type in ['gunicorn', 'django', 'flask', 'fastapi'] or 'port' in service

    def _generate_nginx_site_config(self, service: Dict[str, Any]) -> str:
        """Generate nginx site configuration for a service"""
        service_name = service['name']
        domain = self._get_service_domain(service)
        port = self._get_service_port(service)
        
        # Generate nginx configuration
        config_content = f"""# Nginx configuration for {self.project_name}-{self.normalized_branch}-{service_name}
# Domain: {domain}
# Upstream port: {port}

upstream {self.project_name}_{self.normalized_branch}_{service_name} {{
    server 127.0.0.1:{port};
}}

server {{
    listen 80;
    server_name {domain};
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    
    # Logging
    access_log /var/log/nginx/{domain}_access.log;
    error_log /var/log/nginx/{domain}_error.log;
    
    # Client upload size
    client_max_body_size 50M;
    
    # Static files (if they exist)
    location /static/ {{
        alias {self.base_path}/{self.project_name}/{self.normalized_branch}/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }}
    
    # Media files (if they exist)
    location /media/ {{
        alias {self.base_path}/{self.project_name}/{self.normalized_branch}/media/;
        expires 1y;
        add_header Cache-Control "public";
    }}
    
    # Main application
    location / {{
        proxy_pass http://{self.project_name}_{self.normalized_branch}_{service_name};
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffer settings
        proxy_buffering on;
        proxy_buffer_size 8k;
        proxy_buffers 8 8k;
    }}
    
    # Health check endpoint
    location /nginx-health {{
        access_log off;
        return 200 "healthy\\n";
        add_header Content-Type text/plain;
    }}
}}

# HTTPS redirect (uncomment when SSL is configured)
# server {{
#     listen 443 ssl http2;
#     server_name {domain};
#     
#     ssl_certificate /etc/ssl/certs/{domain}.crt;
#     ssl_certificate_key /etc/ssl/private/{domain}.key;
#     
#     # Include SSL configuration
#     include /etc/nginx/snippets/ssl-params.conf;
#     
#     # Same location blocks as above
#     # ... (copy from HTTP server block)
# }}
"""
        return config_content

    def _write_nginx_config(self, service: Dict[str, Any], config_content: str):
        """Write nginx configuration to file"""
        service_name = service['name']
        domain = self._get_service_domain(service)
        
        # Create filename based on domain for easy identification
        config_filename = f"{domain}.conf"
        config_file_path = self.nginx_config_path / config_filename
        
        try:
            with open(config_file_path, 'w') as f:
                f.write(config_content)
            
            logger.info(f"Generated nginx config: {config_file_path}")
            logger.info(f"  Service: {self.project_name}-{self.normalized_branch}-{service_name}")
            logger.info(f"  Domain: {domain}")
            logger.info(f"  Port: {self._get_service_port(service)}")
            
        except IOError as e:
            logger.error(f"Failed to write nginx config {config_file_path}: {e}")
            raise

    def _generate_nginx_main_config(self) -> str:
        """Generate main nginx configuration snippet"""
        web_services = [s for s in self.config.get('services', []) if self._is_web_service(s)]
        
        if not web_services:
            return ""
        
        config_content = f"""# Main nginx configuration for {self.project_name}-{self.normalized_branch}
# Generated automatically - do not edit manually

# Rate limiting
limit_req_zone $binary_remote_addr zone={self.project_name}_{self.normalized_branch}:10m rate=10r/s;

# Gzip compression
gzip on;
gzip_vary on;
gzip_min_length 1024;
gzip_types
    text/plain
    text/css
    text/xml
    text/javascript
    application/javascript
    application/xml+rss
    application/json;

# Security settings
server_tokens off;
"""
        return config_content

    def generate_all_configs(self):
        """Generate nginx configurations for all web services"""
        services = self.config.get('services', [])
        web_services = [s for s in services if self._is_web_service(s)]
        
        if not web_services:
            logger.info("No web services found, skipping nginx configuration generation")
            return
        
        logger.info(f"Found {len(web_services)} web service(s) requiring nginx configuration")
        
        # Generate main nginx config
        main_config = self._generate_nginx_main_config()
        if main_config:
            main_config_path = self.nginx_config_path / f"{self.project_name}-{self.normalized_branch}-main.conf"
            with open(main_config_path, 'w') as f:
                f.write(main_config)
            logger.info(f"Generated main nginx config: {main_config_path}")
        
        # Generate individual service configs
        for service in web_services:
            try:
                config_content = self._generate_nginx_site_config(service)
                self._write_nginx_config(service, config_content)
            except Exception as e:
                logger.error(f"Failed to generate nginx config for service {service.get('name', 'unknown')}: {e}")
                raise
        
        # Generate deployment instructions
        self._generate_deployment_instructions(web_services)

    def _generate_deployment_instructions(self, web_services: List[Dict[str, Any]]):
        """Generate instructions for deploying nginx configurations"""
        instructions_path = self.nginx_config_path / "README.md"
        
        domains = [self._get_service_domain(s) for s in web_services]
        
        instructions = f"""# Nginx Configuration Deployment Instructions

## Generated Configurations

This directory contains nginx configurations for **{self.project_name}-{self.normalized_branch}**:

"""
        
        for service in web_services:
            domain = self._get_service_domain(service)
            port = self._get_service_port(service)
            instructions += f"- **{domain}.conf**: {service['name']} service (port {port})\\n"
        
        instructions += f"""
## Deployment Steps

1. **Copy configurations to nginx sites-available:**
   ```bash
   sudo cp *.conf /etc/nginx/sites-available/
   ```

2. **Enable sites:**
   ```bash
"""
        
        for service in web_services:
            domain = self._get_service_domain(service)
            instructions += f"   sudo ln -sf /etc/nginx/sites-available/{domain}.conf /etc/nginx/sites-enabled/\\n"
        
        instructions += f"""   ```

3. **Test nginx configuration:**
   ```bash
   sudo nginx -t
   ```

4. **Reload nginx:**
   ```bash
   sudo systemctl reload nginx
   ```

5. **Add domains to /etc/hosts (for local testing):**
   ```bash
"""
        
        for domain in domains:
            instructions += f"   echo '127.0.0.1 {domain}' | sudo tee -a /etc/hosts\\n"
        
        instructions += f"""   ```

## Service URLs

After deployment, the following URLs will be available:

"""
        
        for service in web_services:
            domain = self._get_service_domain(service)
            instructions += f"- **{service['name']}**: http://{domain}/\\n"
        
        instructions += f"""
## SSL Configuration

To enable HTTPS:

1. Obtain SSL certificates for each domain
2. Uncomment the HTTPS server blocks in the configuration files
3. Update certificate paths in the configuration
4. Test and reload nginx

## Troubleshooting

- Check nginx error logs: `sudo tail -f /var/log/nginx/error.log`
- Check service-specific logs: `sudo tail -f /var/log/nginx/[domain]_error.log`
- Verify upstream services are running: `sudo supervisorctl status`
- Test upstream connectivity: `curl http://127.0.0.1:[port]/`
"""
        
        with open(instructions_path, 'w') as f:
            f.write(instructions)
        
        logger.info(f"Generated deployment instructions: {instructions_path}")

def main():
    """Main entry point"""
    try:
        generator = NginxConfigGenerator()
        generator.generate_all_configs()
        logger.info("Nginx configuration generation completed successfully")
    except Exception as e:
        logger.error(f"Nginx configuration generation failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
