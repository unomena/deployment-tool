#!/usr/bin/env python3
"""
generate-supervisor-configs.py - Supervisor Configuration Generator Script

This script generates Supervisor configuration files for services defined in deployment config.
Uses environment variables for configuration.

Required Environment Variables:
    CONFIG_DATA         - JSON string containing the deployment configuration
    PROJECT_NAME        - Name of the project
    CONFIG_OUTPUT_DIR   - Directory where Supervisor configs should be written
    VENV_PATH          - Path to Python virtual environment
    CODE_PATH          - Path to application code
    LOGS_PATH          - Path to log files

Optional Environment Variables:
    USER               - User to run services as (default: www-data)
    AUTOSTART          - Auto-start services (default: true)  
    AUTORESTART        - Auto-restart services (default: true)
"""

import os
import sys
import json
import logging
from pathlib import Path
from typing import Dict, List, Any, Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class SupervisorConfigGenerator:
    """Generates Supervisor configuration files for deployment services"""
    
    def __init__(self):
        """Initialize with environment variables"""
        self.config_data = self._load_config_data()
        self.project_name = self._get_required_env('PROJECT_NAME')
        self.config_output_dir = Path(self._get_required_env('CONFIG_OUTPUT_DIR'))
        self.venv_path = Path(self._get_required_env('VENV_PATH'))
        self.code_path = Path(self._get_required_env('CODE_PATH'))
        self.logs_path = Path(self._get_required_env('LOGS_PATH'))
        
        # Optional settings with defaults
        self.user = os.getenv('USER', 'www-data')
        self.autostart = os.getenv('AUTOSTART', 'true').lower() == 'true'
        self.autorestart = os.getenv('AUTORESTART', 'true').lower() == 'true'
        
        logger.info(f"Generating Supervisor configs for project: {self.project_name}")
        logger.info(f"Output directory: {self.config_output_dir}")

    def _get_required_env(self, var_name: str) -> str:
        """Get required environment variable or exit with error"""
        value = os.getenv(var_name)
        if not value:
            logger.error(f"Missing required environment variable: {var_name}")
            sys.exit(1)
        return value

    def _load_config_data(self) -> Dict[str, Any]:
        """Load and parse configuration data from environment variable"""
        config_json = self._get_required_env('CONFIG_DATA')
        
        try:
            config = json.loads(config_json)
            logger.info("Configuration data loaded successfully")
            return config
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse CONFIG_DATA JSON: {e}")
            sys.exit(1)

    def _find_available_port(self, preferred_port: int) -> int:
        """Find available port starting from preferred port"""
        import subprocess
        import sys
        
        try:
            # Use the find-available-port.py script
            script_path = Path(__file__).parent / "find-available-port.py"
            result = subprocess.run(
                [sys.executable, str(script_path), str(preferred_port)],
                capture_output=True,
                text=True,
                check=True
            )
            available_port = int(result.stdout.strip())
            
            if available_port != preferred_port:
                logger.info(f"Port {preferred_port} unavailable, using port {available_port}")
            else:
                logger.info(f"Using preferred port {preferred_port}")
                
            return available_port
            
        except (subprocess.CalledProcessError, ValueError) as e:
            logger.warning(f"Failed to find available port, falling back to {preferred_port}: {e}")
            return preferred_port

    def _substitute_environment_variables(self, value: str, env_vars: Dict[str, str]) -> str:
        """Substitute environment variables in configuration values"""
        if isinstance(value, str) and value.startswith('${') and value.endswith('}'):
            var_name = value[2:-1]
            if var_name in env_vars:
                return str(env_vars[var_name])
        return str(value)

    def _build_environment_string(self, env_vars: Dict[str, str]) -> str:
        """Build environment string for Supervisor configuration"""
        env_pairs = []
        
        for key, value in env_vars.items():
            # Handle variable substitution
            resolved_value = self._substitute_environment_variables(value, env_vars)
            # Quote the value to handle special characters
            # Escape any existing quotes in the value
            escaped_value = str(resolved_value).replace('"', '\\"')
            env_pairs.append(f'{key}="{escaped_value}"')
        
        return ','.join(env_pairs)

    def _merge_service_env_vars(self, service: Dict[str, Any]) -> Dict[str, str]:
        """Merge root env_vars with service-level env_vars, service takes precedence"""
        # Start with root environment variables
        merged_env = dict(self.env_vars)
        
        # Override with service-specific env_vars if they exist
        service_env_vars = service.get('env_vars', {})
        if service_env_vars:
            merged_env.update(service_env_vars)
            
        return merged_env

    def _get_service_domain(self, service: Dict[str, Any]) -> str:
        """Get domain for service, with service-level override capability"""
        # Check for service-level domain override first
        if 'domain' in service:
            return service['domain']
        
        # Fall back to root domain or default
        return self.env_vars.get('DEFAULT_DOMAIN', f"{self.project_name}-{self.env_vars.get('NORMALIZED_BRANCH', 'main')}")

    def _generate_service_config(self, service: Dict[str, Any]) -> str:
        """Generate Supervisor configuration for a single service"""
        service_name = service['name']
        command = service['command']
        
        # Get merged environment variables for this service
        service_env_vars = self._merge_service_env_vars(service)
        
        # Get domain for this service
        service_domain = self._get_service_domain(service)
        service_env_vars['SERVICE_DOMAIN'] = service_domain
        
        # Build full command with virtual environment
        if not command.startswith('/'):
            # Relative command, prepend venv path
            full_command = f"{self.venv_path}/bin/{command}"
        else:
            # Absolute command path
            full_command = command
        
        # Determine working directory
        working_dir = self.code_path
        if 'directory' in service:
            # If service specifies a directory, append it to code_path
            working_dir = self.code_path / service['directory']
        elif 'working_directory' in service:
            # If service specifies a working directory, append it to code_path (legacy support)
            working_dir = self.code_path / service['working_directory']
        
        # Build environment variables
        environment_string = self._build_environment_string(service_env_vars)
        
        # Handle gunicorn services specially
        if service.get('type') == 'gunicorn':
            # For gunicorn, use its own worker management instead of supervisor's
            workers = service.get('workers', 1)
            preferred_port = service.get('port', 8000)
            
            # Find available port starting from preferred port
            available_port = self._find_available_port(preferred_port)
            
            # Modify command to include workers and bind parameters
            if '--workers' not in command and '--bind' not in command:
                full_command = f"{self.venv_path}/bin/{command} --workers {workers} --bind 0.0.0.0:{available_port}"
            supervisor_numprocs = 1  # Only one supervisor process for gunicorn
        else:
            # For non-gunicorn services, use supervisor's process management
            supervisor_numprocs = service.get('workers', 1)
        
        # Generate configuration with branch-based naming
        normalized_branch = os.getenv('NORMALIZED_BRANCH', 'main')
        config_content = f"""[program:{self.project_name}-{normalized_branch}-{service_name}]
command={full_command}
directory={working_dir}
user={self.user}
autostart={'true' if self.autostart else 'false'}
autorestart={'true' if self.autorestart else 'false'}
startsecs=10
startretries=3
stdout_logfile={self.logs_path}/supervisor/{service_name}.log
stderr_logfile={self.logs_path}/supervisor/{service_name}_error.log
stdout_logfile_maxbytes=50MB
stderr_logfile_maxbytes=50MB
stdout_logfile_backups=5
stderr_logfile_backups=5
environment={environment_string}
numprocs={supervisor_numprocs}"""
        
        # Add process naming for multiple supervisor processes (non-gunicorn)
        if supervisor_numprocs > 1:
            config_content += f"\nprocess_name=%(program_name)s_%(process_num)02d"
        
        # Add service-specific configurations
        if service.get('type') == 'gunicorn':
            # Add gunicorn-specific settings
            if 'port' in service:
                config_content += f"\n# Gunicorn service on port {available_port} (preferred: {preferred_port})"
        elif service.get('type') == 'celery':
            # Add celery-specific settings
            config_content += f"\n# Celery {service_name} service"
            if 'worker' in service_name.lower():
                config_content += "\n# Celery worker process"
            elif 'beat' in service_name.lower():
                config_content += "\n# Celery beat scheduler"
        
        return config_content

    def _validate_service(self, service: Dict[str, Any]) -> bool:
        """Validate service configuration"""
        required_fields = ['name', 'command']
        missing_fields = [field for field in required_fields if field not in service]
        
        if missing_fields:
            logger.error(f"Service missing required fields: {missing_fields}")
            return False
        
        # Validate service name
        service_name = service['name']
        if not service_name.replace('-', '').replace('_', '').isalnum():
            logger.error(f"Invalid service name: {service_name}")
            return False
        
        return True

    def _create_output_directory(self) -> None:
        """Create output directory for configuration files"""
        try:
            self.config_output_dir.mkdir(parents=True, exist_ok=True)
            logger.info(f"Output directory ready: {self.config_output_dir}")
        except Exception as e:
            logger.error(f"Failed to create output directory: {e}")
            sys.exit(1)

    def _write_config_file(self, service_name: str, config_content: str) -> None:
        """Write configuration file for a service"""
        normalized_branch = os.getenv('NORMALIZED_BRANCH', 'main')
        config_filename = f"{self.project_name}-{normalized_branch}-{service_name}.conf"
        config_filepath = self.config_output_dir / config_filename
        
        try:
            with open(config_filepath, 'w') as f:
                f.write(config_content)
            
            logger.info(f"✓ Generated config: {config_filepath}")
            
        except Exception as e:
            logger.error(f"Failed to write config file {config_filepath}: {e}")
            sys.exit(1)

    def _generate_group_config(self, services: List[Dict[str, Any]]) -> str:
        """Generate Supervisor group configuration for all services"""
        if len(services) <= 1:
            return ""  # No group needed for single service
        
        normalized_branch = os.getenv('NORMALIZED_BRANCH', 'main')
        service_names = [f"{self.project_name}-{normalized_branch}-{service['name']}" for service in services]
        programs = ','.join(service_names)
        
        group_config = f"""[group:{self.project_name}-{normalized_branch}]
programs={programs}
priority=999
"""
        return group_config

    def _write_group_config(self, group_config: str) -> None:
        """Write group configuration file"""
        if not group_config:
            return
        
        normalized_branch = os.getenv('NORMALIZED_BRANCH', 'main')
        group_filename = f"{self.project_name}-{normalized_branch}-group.conf"
        group_filepath = self.config_output_dir / group_filename
        
        try:
            with open(group_filepath, 'w') as f:
                f.write(group_config)
            
            logger.info(f"✓ Generated group config: {group_filepath}")
            
        except Exception as e:
            logger.error(f"Failed to write group config file {group_filepath}: {e}")
            sys.exit(1)

    def generate_configs(self) -> bool:
        """Generate all Supervisor configuration files"""
        logger.info("Starting Supervisor configuration generation")
        
        # Get services from configuration
        services = self.config_data.get('services', [])
        
        if not services:
            logger.info("No services defined in configuration")
            return True
        
        logger.info(f"Found {len(services)} services to configure")
        
        # Create output directory
        self._create_output_directory()
        
        # Validate and generate configs for each service
        valid_services = []
        for service in services:
            if self._validate_service(service):
                try:
                    config_content = self._generate_service_config(service)
                    self._write_config_file(service['name'], config_content)
                    valid_services.append(service)
                except Exception as e:
                    logger.error(f"Failed to generate config for service {service['name']}: {e}")
                    return False
            else:
                logger.error(f"Skipping invalid service: {service.get('name', 'unnamed')}")
                return False
        
        # Generate group configuration
        group_config = self._generate_group_config(valid_services)
        if group_config:
            self._write_group_config(group_config)
        
        logger.info(f"🎉 Successfully generated {len(valid_services)} Supervisor configurations")
        return True

    def list_generated_configs(self) -> None:
        """List all generated configuration files"""
        logger.info("Generated Supervisor configuration files:")
        
        config_files = list(self.config_output_dir.glob(f"{self.project_name}-*.conf"))
        config_files.sort()
        
        for config_file in config_files:
            file_size = config_file.stat().st_size
            logger.info(f"  {config_file.name} ({file_size} bytes)")
        
        if not config_files:
            logger.warning("No configuration files found")


def show_help():
    """Display help information"""
    help_text = """
generate-supervisor-configs.py - Supervisor Configuration Generator Script

DESCRIPTION:
    This script generates Supervisor configuration files for services defined in 
    deployment configuration. It creates individual service configs and optionally
    a group configuration.

REQUIRED ENVIRONMENT VARIABLES:
    CONFIG_DATA       JSON string containing the deployment configuration
    PROJECT_NAME      Name of the project
    CONFIG_OUTPUT_DIR Directory where Supervisor configs should be written
    VENV_PATH        Path to Python virtual environment
    CODE_PATH        Path to application code
    LOGS_PATH        Path to log files

OPTIONAL ENVIRONMENT VARIABLES:
    USER             User to run services as (default: www-data)
    AUTOSTART        Auto-start services (default: true)
    AUTORESTART      Auto-restart services (default: true)

USAGE:
    # Set environment variables
    export CONFIG_DATA='{"services": [{"name": "web", "command": "gunicorn app:app"}]}'
    export PROJECT_NAME="myapp"
    export CONFIG_OUTPUT_DIR="/srv/myapp/config/supervisor"
    export VENV_PATH="/srv/myapp/venv"
    export CODE_PATH="/srv/myapp/code"
    export LOGS_PATH="/srv/myapp/logs"
    
    # Run the script
    ./generate-supervisor-configs.py

EXIT CODES:
    0  Success - All configurations generated
    1  Error - Generation failed

EXAMPLES:
    # Basic usage
    CONFIG_DATA='...' PROJECT_NAME=myapp CONFIG_OUTPUT_DIR=/etc/supervisor/conf.d ./generate-supervisor-configs.py
    
    # With custom user
    USER=myuser CONFIG_DATA='...' PROJECT_NAME=myapp CONFIG_OUTPUT_DIR=/tmp/supervisor ./generate-supervisor-configs.py
"""
    print(help_text)


def main():
    """Main entry point"""
    # Handle command line arguments
    if len(sys.argv) > 1 and sys.argv[1] in ['-h', '--help', 'help']:
        show_help()
        sys.exit(0)
    
    try:
        generator = SupervisorConfigGenerator()
        
        if generator.generate_configs():
            generator.list_generated_configs()
            logger.info("Supervisor configuration generation completed successfully")
            sys.exit(0)
        else:
            logger.error("Supervisor configuration generation failed")
            sys.exit(1)
            
    except KeyboardInterrupt:
        logger.info("Generation cancelled by user")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
