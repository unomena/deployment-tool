#!/usr/bin/env python3
"""
update-deployment-ports.py - Update deployment configuration with allocated ports

This script updates the deployment configuration file with the actual ports
that were allocated during deployment, so health checks and other components
can use the correct ports.

Usage:
    python3 update-deployment-ports.py <config_file> <service_name> <allocated_port>

Arguments:
    config_file    - Path to deployment YAML configuration file
    service_name   - Name of the service (e.g., 'web')
    allocated_port - The actual port that was allocated

Examples:
    python3 update-deployment-ports.py deploy-dev.yml web 8001
"""

import sys
import yaml
import logging
from pathlib import Path
from typing import Dict, Any

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def load_config(config_file: Path) -> Dict[str, Any]:
    """Load YAML configuration file"""
    try:
        with open(config_file, 'r') as f:
            config = yaml.safe_load(f)
        logger.info(f"Loaded configuration from {config_file}")
        return config
    except Exception as e:
        logger.error(f"Failed to load configuration from {config_file}: {e}")
        raise


def save_config(config_file: Path, config: Dict[str, Any]) -> None:
    """Save YAML configuration file"""
    try:
        with open(config_file, 'w') as f:
            yaml.dump(config, f, default_flow_style=False, sort_keys=False)
        logger.info(f"Saved configuration to {config_file}")
    except Exception as e:
        logger.error(f"Failed to save configuration to {config_file}: {e}")
        raise


def update_service_port(config: Dict[str, Any], service_name: str, allocated_port: int) -> bool:
    """
    Update the port for a specific service in the configuration.
    
    Args:
        config: Configuration dictionary
        service_name: Name of the service to update
        allocated_port: The allocated port number
    
    Returns:
        True if service was found and updated, False otherwise
    """
    services = config.get('services', [])
    
    for service in services:
        if service.get('name') == service_name:
            old_port = service.get('port', 'not set')
            service['port'] = allocated_port
            logger.info(f"Updated service '{service_name}' port from {old_port} to {allocated_port}")
            
            # Add a comment about the port allocation
            if 'allocated_port' not in service:
                service['allocated_port'] = allocated_port
                service['port_allocation_time'] = str(sys.modules['datetime'].datetime.now())
            
            return True
    
    logger.warning(f"Service '{service_name}' not found in configuration")
    return False


def update_health_checks(config: Dict[str, Any], service_name: str, allocated_port: int) -> None:
    """Update health check URLs with the allocated port"""
    health_checks = config.get('health_checks', [])
    
    for health_check in health_checks:
        url = health_check.get('url', '')
        if service_name in health_check.get('name', '').lower() or 'web' in health_check.get('name', '').lower():
            # Update port in URL
            import re
            new_url = re.sub(r':(\d+)/', f':{allocated_port}/', url)
            if new_url != url:
                health_check['url'] = new_url
                logger.info(f"Updated health check URL from {url} to {new_url}")


def main():
    """Main entry point"""
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)
    
    try:
        config_file = Path(sys.argv[1])
        service_name = sys.argv[2]
        allocated_port = int(sys.argv[3])
        
        # Validate inputs
        if not config_file.exists():
            logger.error(f"Configuration file not found: {config_file}")
            sys.exit(1)
        
        if allocated_port < 1 or allocated_port > 65535:
            logger.error(f"Invalid port number: {allocated_port}")
            sys.exit(1)
        
        # Load configuration
        config = load_config(config_file)
        
        # Update service port
        if update_service_port(config, service_name, allocated_port):
            # Update health checks if applicable
            update_health_checks(config, service_name, allocated_port)
            
            # Save updated configuration
            save_config(config_file, config)
            logger.info("Configuration updated successfully")
        else:
            logger.error("Failed to update configuration")
            sys.exit(1)
            
    except ValueError as e:
        logger.error(f"Invalid port number: {sys.argv[3]}")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    import datetime
    main()
