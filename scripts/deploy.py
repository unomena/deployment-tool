#!/usr/bin/env python3
"""
PyDeployer - Deployment automation tool for Django applications
Lightweight orchestrator that coordinates focused deployment scripts
"""

import os
import sys
import subprocess
import argparse
import re
import yaml
import json
from pathlib import Path
from typing import Dict, List, Optional, Any
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class PyDeployer:
    """Main deployment orchestrator - coordinates focused scripts"""
    
    def __init__(self, config_file: str, branch: str = "main", base_dir: str = None):
        """Initialize deployer with config file and branch"""
        self.config_file = Path(config_file)
        self.branch = branch
        self.config = self._load_config()
        self.project_name = self.config['name']
        self.environment = self.config['environment']
        
        # Validate environment
        valid_envs = ['prod', 'qa', 'stage', 'dev']
        if self.environment not in valid_envs:
            raise ValueError(f"Environment must be one of: {valid_envs}")
        
        # Set up paths - allow override for testing
        if base_dir:
            self.base_path = Path(base_dir) / f"{self.project_name}/{self.environment}/{self.branch}"
        else:
            self.base_path = Path(f"/srv/deployments/{self.project_name}/{self.environment}/{self.branch}")
        
        self.code_path = self.base_path / "code"
        self.config_path = self.base_path / "config"
        self.logs_path = self.base_path / "logs"
        self.venv_path = self.base_path / "venv"
        self.scripts_path = Path(__file__).parent
        
        logger.info(f"Deploying {self.project_name} to {self.environment} environment")
        logger.info(f"Base path: {self.base_path}")

    def _load_config(self) -> Dict[str, Any]:
        """Load and validate configuration file"""
        if not self.config_file.exists():
            raise FileNotFoundError(f"Configuration file not found: {self.config_file}")
        
        with open(self.config_file, 'r') as f:
            config = yaml.safe_load(f)
        
        # Validate required fields
        required_fields = ['name', 'environment', 'python_version']
        missing_fields = [field for field in required_fields if field not in config]
        if missing_fields:
            raise ValueError(f"Missing required fields in config: {missing_fields}")
        
        return config

    def _setup_environment_variables(self) -> Dict[str, str]:
        """Setup environment variables for scripts"""
        env_vars = {
            # Common deployment paths
            'BASE_PATH': str(self.base_path),
            'CODE_PATH': str(self.code_path),
            'CONFIG_PATH': str(self.config_path),
            'LOGS_PATH': str(self.logs_path),
            'VENV_PATH': str(self.venv_path),
            'PROJECT_NAME': self.project_name,
            'PYTHON_VERSION': self.config['python_version'],
            'BRANCH': self.branch,
        }
        
        # Add database servers configuration file path if it exists
        db_config_locations = [
            Path('/etc/deployment-tool/db-servers.yml'),
            Path('/srv/deployment-tool/config/db-servers.yml'),
            Path.home() / '.deployment-tool' / 'db-servers.yml',
            Path('/opt/deployment-tool/config/db-servers.yml'),
            self.scripts_path.parent / 'config.yml',  # Check project root config.yml
        ]
        
        for config_path in db_config_locations:
            if config_path.exists():
                env_vars['DB_SERVERS_CONFIG'] = str(config_path)
                logger.info(f"Found database servers config at: {config_path}")
                break
        
        # Add repository URL if specified
        if 'repo' in self.config:
            env_vars['REPO_URL'] = self.config['repo']
            env_vars['TARGET_DIR'] = str(self.code_path)
            env_vars['REMOVE_EXISTING'] = 'true'
        
        # Add system dependencies
        system_deps = self.config.get('dependencies', {}).get('system', [])
        if system_deps:
            env_vars['SYSTEM_DEPENDENCIES'] = json.dumps(system_deps)
        
        # Add Python dependencies
        python_deps = self.config.get('dependencies', {}).get('python', [])
        if python_deps:
            env_vars['PYTHON_DEPENDENCIES'] = json.dumps(python_deps)
        
        # Add requirements files
        req_files = self.config.get('dependencies', {}).get('python-requirements', [])
        if req_files:
            env_vars['REQUIREMENTS_FILES'] = json.dumps(req_files)
            env_vars['PROJECT_DIR'] = str(self.code_path)
        
        # Add application environment variables from config
        if 'env_vars' in self.config:
            for key, value in self.config['env_vars'].items():
                env_vars[key] = str(value)
        
        # Handle database configuration section separately for database setup scripts
        if 'database' in self.config:
            db_config = self.config['database']
            # These are specifically for database creation/verification scripts
            # They override any env_vars with the same name for database operations
            
            # First, expand any template variables in database config
            import re
            def expand_vars(value, env_dict):
                """Expand ${VAR} references in value using env_dict"""
                if not isinstance(value, str):
                    return value
                pattern = r'\$\{([^}]+)\}'
                def replacer(match):
                    var_name = match.group(1)
                    return env_dict.get(var_name, match.group(0))
                return re.sub(pattern, replacer, value)
            
            # Expand database config values using env_vars
            env_vars['DB_TYPE'] = db_config.get('type', 'postgresql')
            env_vars['DB_NAME'] = expand_vars(db_config.get('name', ''), env_vars)
            env_vars['DB_USER'] = expand_vars(db_config.get('user', ''), env_vars)
            env_vars['DB_PASSWORD'] = expand_vars(db_config.get('password', ''), env_vars)
            env_vars['DB_HOST'] = expand_vars(db_config.get('host', 'localhost'), env_vars)
            env_vars['DB_PORT'] = expand_vars(str(db_config.get('port', 5432)), env_vars)
        
        # Add supervisor-specific variables
        env_vars['CONFIG_OUTPUT_DIR'] = str(self.config_path / "supervisor")
        env_vars['CONFIG_SOURCE_DIR'] = str(self.config_path / "supervisor")
        env_vars['CONFIG_DATA'] = json.dumps(self.config)
        
        # Add PROJECT-specific Python paths (for Django operations)
        # These must use the project's virtual environment, not the deployment tool's
        env_vars['PROJECT_PYTHON_PATH'] = str(self.venv_path / "bin" / "python")
        env_vars['PROJECT_PIP_PATH'] = str(self.venv_path / "bin" / "pip")
        env_vars['DJANGO_PROJECT_DIR'] = str(self.code_path)
        
        return env_vars

    def _run_script(self, script_name: str, description: str) -> bool:
        """Run a deployment script with environment variables"""
        script_path = self.scripts_path / script_name
        
        if not script_path.exists():
            logger.error(f"Script not found: {script_path}")
            return False
        
        logger.info(f"{description}...")
        
        # Setup environment
        env = os.environ.copy()
        env.update(self._setup_environment_variables())
        
        try:
            result = subprocess.run([str(script_path)], 
                                  check=True, 
                                  env=env,
                                  capture_output=True, 
                                  text=True)
            
            if result.stdout:
                logger.info(f"Script output: {result.stdout}")
            
            logger.info(f"✓ {description} completed successfully")
            return True
            
        except subprocess.CalledProcessError as e:
            logger.error(f"✗ {description} failed")
            if e.stdout:
                logger.error(f"Script output: {e.stdout}")
            if e.stderr:
                logger.error(f"Script error: {e.stderr}")
            return False
        except Exception as e:
            logger.error(f"✗ {description} failed with exception: {e}")
            return False

    def create_directory_structure(self) -> bool:
        """Create the complete directory structure"""
        logger.info("Creating directory structure...")
        
        directories = [
            self.base_path,
            self.code_path,
            self.config_path,
            self.logs_path,
            self.venv_path.parent,  # Don't create venv directory itself
            self.config_path / "supervisor",
            self.config_path / "nginx",
            self.logs_path / "supervisor",
            self.logs_path / "app",
        ]
        
        try:
            for directory in directories:
                directory.mkdir(parents=True, exist_ok=True)
                logger.info(f"Created directory: {directory}")
            return True
        except Exception as e:
            logger.error(f"Failed to create directories: {e}")
            return False

    def install_system_dependencies(self) -> bool:
        """Install system dependencies using script"""
        return self._run_script("install-system-dependencies.sh", "Installing system dependencies")

    def setup_python_environment(self) -> bool:
        """Setup Python virtual environment using script"""
        return self._run_script("setup-python-environment.sh", "Setting up Python environment")

    def copy_repository(self) -> bool:
        """Copy repository from current directory to deployment code directory"""
        import shutil
        import os
        
        logger.info("Copying repository to deployment directory...")
        
        # Current directory should contain the cloned repository
        current_dir = Path.cwd()
        
        # Verify we're in a git repository
        if not (current_dir / ".git").exists():
            logger.error("Current directory is not a git repository")
            logger.error("The deploy shell script should run this from the cloned repo")
            return False
        
        # Remove existing code directory if it exists
        if self.code_path.exists():
            logger.info(f"Removing existing code directory: {self.code_path}")
            shutil.rmtree(self.code_path)
        
        # Copy repository contents to code directory
        try:
            logger.info(f"Copying repository from {current_dir} to {self.code_path}")
            shutil.copytree(current_dir, self.code_path, ignore=shutil.ignore_patterns('.git'))
            logger.info(f"✓ Repository copied to: {self.code_path}")
            
            # Patch configuration to use script-based unit tests
            self._patch_deployment_config()
            
            # Reload configuration after patching
            self._reload_config()
            
            return True
        except Exception as e:
            logger.error(f"Failed to copy repository: {e}")
            return False

    def _patch_deployment_config(self) -> None:
        """Patch deployment configuration to use script-based unit tests"""
        config_file = self.code_path / self.config_file.name
        if not config_file.exists():
            logger.warning(f"Configuration file not found for patching: {config_file}")
            return
        
        try:
            with open(config_file, 'r') as f:
                content = f.read()
            
            # Replace the old python command with script-based approach
            old_command = '- command: "python src/run_tests.py --health-check"'
            new_command = '- script: "run-unit-tests.sh"'
            
            if old_command in content:
                content = content.replace(old_command, new_command)
                
                with open(config_file, 'w') as f:
                    f.write(content)
                
                logger.info("✓ Patched deployment configuration to use script-based unit tests")
            else:
                logger.debug("Configuration already uses script-based unit tests")
                
        except Exception as e:
            logger.warning(f"Failed to patch deployment configuration: {e}")

    def _reload_config(self) -> None:
        """Reload configuration from the patched file"""
        try:
            config_file = self.code_path / self.config_file.name
            if config_file.exists():
                with open(config_file, 'r') as f:
                    self.config = yaml.safe_load(f)
                logger.debug("✓ Configuration reloaded after patching")
            else:
                logger.warning("Configuration file not found for reloading")
        except Exception as e:
            logger.warning(f"Failed to reload configuration: {e}")

    def install_python_dependencies(self) -> bool:
        """Install Python dependencies using script"""
        return self._run_script("install-python-dependencies.sh", "Installing Python dependencies")

    def generate_supervisor_configs(self) -> bool:
        """Generate Supervisor configurations using script"""
        services = self.config.get('services', [])
        if not services:
            logger.info("No services defined, skipping Supervisor config generation")
            return True
        
        return self._run_script("generate-supervisor-configs.py", "Generating Supervisor configurations")

    def install_supervisor_configs(self) -> bool:
        """Install Supervisor configurations using script"""
        services = self.config.get('services', [])
        if not services:
            logger.info("No services defined, skipping Supervisor config installation")
            return True
        
        return self._run_script("install-supervisor-configs.sh", "Installing Supervisor configurations")

    def validate_deployment(self) -> bool:
        """Validate deployment using script"""
        return self._run_script("validate-deployment.sh", "Validating deployment")

    def deploy(self) -> bool:
        """Execute complete deployment process"""
        logger.info(f"Starting deployment of {self.project_name}")
        
        # Deployment steps with error checking
        # Steps before starting services
        pre_service_steps = [
            (self.create_directory_structure, "Directory structure creation"),
            (self.install_system_dependencies, "System dependencies installation"),
            (self.setup_python_environment, "Python environment setup"),
            (self.copy_repository, "Repository copying to deployment directory"),
            (self.install_python_dependencies, "Python dependencies installation"),
        ]
        
        # Steps for starting services
        service_steps = [
            (self.generate_supervisor_configs, "Supervisor config generation"),
            (self.install_supervisor_configs, "Supervisor config installation"),
        ]
        
        try:
            # Execute pre-service deployment steps
            for step_func, step_name in pre_service_steps:
                if not step_func():
                    logger.error(f"Deployment failed at step: {step_name}")
                    return False
            
            # Execute pre-deploy hooks (database setup, etc.)
            if not self.run_hooks('pre_deploy'):
                logger.error("Pre-deploy hooks failed")
                return False
            
            # Now start the services
            for step_func, step_name in service_steps:
                if not step_func():
                    logger.error(f"Deployment failed at step: {step_name}")
                    return False
            
            # Execute post-deploy hooks (migrations, static files, etc.)
            if not self.run_hooks('post_deploy'):
                logger.error("Post-deploy hooks failed")
                return False
            
            # Validate deployment
            if not self.validate_deployment():
                logger.error("Deployment validation failed")
                return False
            
            # Update deployment registry
            if not self.update_deployment_registry():
                logger.warning("Failed to update deployment registry (non-critical)")
            
            logger.info("✓ Deployment completed successfully!")
            return True
            
        except Exception as e:
            logger.error(f"Deployment failed with exception: {e}")
            return False

    def update_deployment_registry(self) -> bool:
        """Update the deployment registry with current deployment information"""
        try:
            # Get git URL from the repository
            git_url = self._get_git_url()
            
            # Get Python and Django versions
            python_version = self._get_python_version()
            django_version = self._get_django_version()
            
            # Create deployment data
            deployment_data = {
                "git_url": git_url,
                "branch": self.branch,
                "deployment_path": str(self.base_path),
                "python_version": python_version,
                "django_version": django_version,
                "services": self._extract_services_info(),
                "directories": {
                    "code": str(self.code_path),
                    "venv": str(self.venv_path),
                    "logs": str(self.logs_path),
                    "config": str(self.config_path)
                },
                "config_file": f"deploy-{self.environment}.yml"
            }
            
            # Call the registry management script
            registry_script = Path(__file__).parent / "manage-deployments-registry.py"
            cmd = [
                "python3", str(registry_script), "add",
                "--project", self.project_name,
                "--environment", self.environment,
                "--data", json.dumps(deployment_data)
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode == 0:
                logger.info("✓ Deployment registry updated successfully")
                return True
            else:
                logger.error(f"Failed to update deployment registry: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"Error updating deployment registry: {e}")
            return False
    
    def _get_git_url(self) -> str:
        """Get the git URL from the repository"""
        try:
            result = subprocess.run(
                ["git", "config", "--get", "remote.origin.url"],
                cwd=str(self.code_path),
                capture_output=True,
                text=True
            )
            return result.stdout.strip() if result.returncode == 0 else "unknown"
        except:
            return "unknown"
    
    def _get_python_version(self) -> str:
        """Get Python version from virtual environment"""
        try:
            result = subprocess.run(
                [str(self.venv_path / "bin" / "python"), "--version"],
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                return result.stdout.strip().replace("Python ", "")
        except:
            pass
        return "unknown"
    
    def _get_django_version(self) -> str:
        """Get Django version from virtual environment"""
        try:
            result = subprocess.run(
                [str(self.venv_path / "bin" / "pip"), "show", "django"],
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    if line.startswith('Version:'):
                        return line.split(':', 1)[1].strip()
        except:
            pass
        return "unknown"
    
    def _extract_services_info(self) -> List[Dict[str, Any]]:
        """Extract services information from configuration"""
        services = []
        config_services = self.config.get('services', {})
        
        for service_name, service_config in config_services.items():
            service_data = {
                "name": f"{self.project_name}-{self.environment}-{service_name}",
                "type": service_name,
                "status": "UNKNOWN",
                "command": service_config.get("command", "")
            }
            
            # Extract port for web services
            if service_name == "web" and "bind" in service_config.get("command", ""):
                try:
                    command = service_config["command"]
                    if "--bind" in command:
                        bind_part = command.split("--bind")[1].strip().split()[0]
                        if ":" in bind_part:
                            service_data["port"] = int(bind_part.split(":")[-1])
                except (IndexError, ValueError):
                    pass
            
            services.append(service_data)
        
        return services

    def run_hooks(self, hook_type: str) -> bool:
        """Execute deployment hooks"""
        hooks = self.config.get('hooks', {}).get(hook_type, [])
        
        if not hooks:
            logger.info(f"No {hook_type} hooks defined")
            return True
        
        logger.info(f"Executing {hook_type} hooks...")
        
        try:
            for i, hook in enumerate(hooks):
                description = hook.get('description', f'Hook {i+1}')
                allow_failure = hook.get('allow_failure', False)
                
                logger.info(f"Running: {description}")
                
                if 'command' in hook:
                    # Direct command execution
                    cmd = hook['command']
                    logger.info(f"Executing command: {cmd}")
                    
                    # Setup environment for hook
                    env = os.environ.copy()
                    env.update(self._setup_environment_variables())
                    
                    result = subprocess.run(cmd, shell=True, 
                                          cwd=str(self.code_path),
                                          env=env,
                                          capture_output=True,
                                          text=True)
                    
                    if result.returncode != 0:
                        logger.error(f"Hook command failed: {cmd}")
                        if result.stderr:
                            logger.error(f"Error output: {result.stderr}")
                        if not allow_failure:
                            return False
                        logger.warning(f"Continuing despite failure (allow_failure=true)")
                    else:
                        logger.info(f"✓ {description} completed successfully")
                    
                    if result.stdout:
                        logger.debug(f"Hook output: {result.stdout}")
                
                elif 'script' in hook:
                    # Script execution from scripts directory
                    script_name = hook['script']
                    logger.info(f"Executing script: {script_name}")
                    
                    success = self._run_script(script_name, description)
                    if not success:
                        logger.error(f"Hook script failed: {script_name}")
                        if not allow_failure:
                            return False
                        logger.warning(f"Continuing despite failure (allow_failure=true)")
                    else:
                        logger.info(f"✓ {description} completed successfully")
            
            logger.info(f"✓ All {hook_type} hooks completed successfully")
            return True
            
        except Exception as e:
            logger.error(f"{hook_type} hooks failed with exception: {e}")
            return False


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description='PyDeployer - Django deployment automation')
    parser.add_argument('--config', '-c', required=True, help='Configuration file path')
    parser.add_argument('--branch', '-b', default='main', help='Branch to deploy (default: main)')
    parser.add_argument('--base-dir', help='Override base deployment directory (for testing)')
    parser.add_argument('--verbose', '-v', action='store_true', help='Enable verbose logging')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    try:
        deployer = PyDeployer(args.config, args.branch, args.base_dir)
        success = deployer.deploy()
        sys.exit(0 if success else 1)
        
    except Exception as e:
        logger.error(f"Deployment failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
