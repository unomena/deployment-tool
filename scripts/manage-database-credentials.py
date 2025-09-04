#!/usr/bin/env python3
"""
manage-database-credentials.py - Database Credentials Manager

This script manages database server credentials and provides root access details
for database and user creation operations.

Required Environment Variables:
    DB_SERVERS_CONFIG - Path to the database servers configuration file
    DB_HOST           - Database host to look up credentials for
    
Optional Environment Variables:
    DB_TYPE          - Database type (default: postgresql)
"""

import os
import sys
import yaml
import json
import logging
from pathlib import Path
from typing import Dict, Optional, Any

# Configure logging to stderr to avoid interfering with shell eval
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    stream=sys.stderr
)
logger = logging.getLogger(__name__)


class DatabaseCredentialsManager:
    """Manages database server credentials for administrative operations"""
    
    def __init__(self):
        """Initialize with environment variables"""
        self.config_path = self._get_config_path()
        self.target_host = os.getenv('DB_HOST')
        self.target_type = os.getenv('DB_TYPE', 'postgresql')
        
        if not self.target_host:
            logger.error("DB_HOST environment variable is required")
            sys.exit(1)
        
        self.servers_config = self._load_servers_config()
        
    def _get_config_path(self) -> Path:
        """Get the database servers configuration file path"""
        # First check environment variable
        config_path = os.getenv('DB_SERVERS_CONFIG')
        
        if config_path:
            return Path(config_path)
        
        # Check default locations
        default_locations = [
            Path('/etc/deployment-tool/db-servers.yml'),
            Path('/srv/deployment-tool/config/db-servers.yml'),
            Path.home() / '.deployment-tool' / 'db-servers.yml',
            Path('/opt/deployment-tool/config/db-servers.yml'),
        ]
        
        for location in default_locations:
            if location.exists():
                logger.info(f"Using database servers config from: {location}")
                return location
        
        logger.error("No database servers configuration file found")
        logger.error("Searched locations:")
        for location in default_locations:
            logger.error(f"  - {location}")
        logger.error("Set DB_SERVERS_CONFIG environment variable or create config in one of the default locations")
        sys.exit(1)
    
    def _load_servers_config(self) -> Dict[str, Any]:
        """Load and parse the database servers configuration"""
        if not self.config_path.exists():
            logger.error(f"Database servers config file not found: {self.config_path}")
            sys.exit(1)
        
        try:
            with open(self.config_path, 'r') as f:
                config = yaml.safe_load(f)
            
            if not config or 'databases' not in config:
                logger.error("Invalid configuration file: missing 'databases' section")
                sys.exit(1)
            
            logger.info(f"Loaded {len(config['databases'])} database server configurations")
            return config
            
        except yaml.YAMLError as e:
            logger.error(f"Failed to parse YAML configuration: {e}")
            sys.exit(1)
        except Exception as e:
            logger.error(f"Failed to load configuration: {e}")
            sys.exit(1)
    
    def find_server_credentials(self) -> Optional[Dict[str, Any]]:
        """Find credentials for the target database server"""
        databases = self.servers_config.get('databases', [])
        
        # First try exact host match
        for db in databases:
            if db.get('host') == self.target_host and db.get('type', 'postgresql') == self.target_type:
                logger.info(f"Found exact match for host: {self.target_host}")
                return db
        
        # Try matching by name if it contains the host
        for db in databases:
            if self.target_host in db.get('name', '') and db.get('type', 'postgresql') == self.target_type:
                logger.info(f"Found match by name: {db['name']}")
                return db
        
        # Special case for localhost - try common localhost variations
        if self.target_host in ['localhost', '127.0.0.1', '::1']:
            for db in databases:
                if db.get('host') in ['localhost', '127.0.0.1', '::1'] and db.get('type', 'postgresql') == self.target_type:
                    logger.info(f"Found localhost match: {db['name']}")
                    return db
        
        return None
    
    def get_root_credentials(self) -> Dict[str, str]:
        """Get root credentials for database administration"""
        server_config = self.find_server_credentials()
        
        if not server_config:
            logger.error(f"No credentials found for host: {self.target_host}")
            logger.error("Available hosts in configuration:")
            for db in self.servers_config.get('databases', []):
                logger.error(f"  - {db.get('name')}: {db.get('host')} ({db.get('type', 'postgresql')})")
            sys.exit(1)
        
        # Validate required fields
        required_fields = ['root_user', 'root_password', 'host', 'port']
        missing_fields = [field for field in required_fields if field not in server_config]
        
        if missing_fields:
            logger.error(f"Missing required fields in server configuration: {missing_fields}")
            sys.exit(1)
        
        return {
            'user': server_config['root_user'],
            'password': server_config['root_password'],
            'host': server_config['host'],
            'port': str(server_config['port']),
            'type': server_config.get('type', 'postgresql'),
            'name': server_config.get('name', 'unnamed'),
        }
    
    def export_credentials(self) -> None:
        """Export root credentials as environment variables"""
        credentials = self.get_root_credentials()
        
        # Output as shell export commands (stdout only, no logging mixed in)
        print(f"export DB_ROOT_USER='{credentials['user']}'")
        print(f"export DB_ROOT_PASSWORD='{credentials['password']}'")
        print(f"export DB_ROOT_HOST='{credentials['host']}'")
        print(f"export DB_ROOT_PORT='{credentials['port']}'")
        print(f"export DB_ROOT_TYPE='{credentials['type']}'")
        print(f"export DB_SERVER_NAME='{credentials['name']}'")
        
        # Log to stderr so it doesn't interfere with shell eval
        logger.info(f"Exported root credentials for: {credentials['name']} ({credentials['host']})")
    
    def output_json(self) -> None:
        """Output credentials as JSON"""
        credentials = self.get_root_credentials()
        print(json.dumps(credentials, indent=2))


def show_help():
    """Display help information"""
    help_text = """
manage-database-credentials.py - Database Credentials Manager

DESCRIPTION:
    This script manages database server credentials for administrative operations.
    It reads from a central configuration file containing root/admin credentials
    for various database servers and provides them for database creation operations.

REQUIRED ENVIRONMENT VARIABLES:
    DB_HOST          Database host to look up credentials for

OPTIONAL ENVIRONMENT VARIABLES:
    DB_SERVERS_CONFIG  Path to database servers configuration file
    DB_TYPE           Database type (default: postgresql)

CONFIGURATION FILE FORMAT:
    databases:
      - name: localhost-postgresql
        type: postgresql
        user: postgres
        password: postgres_root_password
        host: localhost
        port: 5432
      
      - name: production-db
        type: postgresql
        user: root
        password: production_root_password
        host: prod.example.com
        port: 5432

DEFAULT CONFIG LOCATIONS:
    - /etc/deployment-tool/db-servers.yml
    - /srv/deployment-tool/config/db-servers.yml
    - ~/.deployment-tool/db-servers.yml
    - /opt/deployment-tool/config/db-servers.yml

USAGE:
    # Export credentials as shell variables
    eval $(DB_HOST=localhost ./manage-database-credentials.py)
    
    # Output credentials as JSON
    DB_HOST=prod.example.com ./manage-database-credentials.py --json
    
    # Use specific config file
    DB_SERVERS_CONFIG=/path/to/config.yml DB_HOST=localhost ./manage-database-credentials.py

EXIT CODES:
    0  Success - Credentials found and exported
    1  Error - Configuration error or credentials not found

EXAMPLES:
    # In a shell script, load root credentials
    eval $(DB_HOST="$DB_HOST" ./manage-database-credentials.py)
    echo "Using root user: $DB_ROOT_USER"
    
    # Get JSON output
    credentials=$(DB_HOST=localhost ./manage-database-credentials.py --json)
    echo "$credentials" | jq '.user'
"""
    print(help_text)


def main():
    """Main entry point"""
    # Handle command line arguments
    if len(sys.argv) > 1:
        if sys.argv[1] in ['-h', '--help', 'help']:
            show_help()
            sys.exit(0)
        elif sys.argv[1] == '--json':
            try:
                manager = DatabaseCredentialsManager()
                manager.output_json()
                sys.exit(0)
            except Exception as e:
                logger.error(f"Failed to get credentials: {e}")
                sys.exit(1)
    
    try:
        manager = DatabaseCredentialsManager()
        manager.export_credentials()
        sys.exit(0)
        
    except KeyboardInterrupt:
        logger.info("Operation cancelled by user")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
