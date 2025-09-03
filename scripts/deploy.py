#!/usr/bin/env python3
"""
PyDeployer - Deployment automation tool for Django applications
Lightweight orchestrator that coordinates focused deployment scripts
"""

import os
import sys
import subprocess
import argparse
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
        self.scripts_path = Path(__file__).parent / "scripts"
        
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
        
        # Add supervisor-specific variables
        env_vars['CONFIG_OUTPUT_DIR'] = str(self.config_path / "supervisor")
        env_vars['CONFIG_SOURCE_DIR'] = str(self.config_path / "supervisor")
        env_vars['CONFIG_DATA'] = json.dumps(self.config)
        
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
            return True
        except Exception as e:
            logger.error(f"Failed to copy repository: {e}")
            return False

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
        deployment_steps = [
            (self.create_directory_structure, "Directory structure creation"),
            (self.install_system_dependencies, "System dependencies installation"),
            (self.setup_python_environment, "Python environment setup"),
            (self.copy_repository, "Repository copying to deployment directory"),
            (self.install_python_dependencies, "Python dependencies installation"),
            (self.generate_supervisor_configs, "Supervisor config generation"),
            (self.install_supervisor_configs, "Supervisor config installation"),
        ]
        
        try:
            # Execute deployment steps
            for step_func, step_name in deployment_steps:
                if not step_func():
                    logger.error(f"Deployment failed at step: {step_name}")
                    return False
            
            # Execute pre-deploy hooks
            if not self.run_hooks('pre-deploy'):
                logger.error("Pre-deploy hooks failed")
                return False
            
            # Execute post-deploy hooks
            if not self.run_hooks('post-deploy'):
                logger.error("Post-deploy hooks failed")
                return False
            
            # Validate deployment
            if not self.validate_deployment():
                logger.error("Deployment validation failed")
                return False
            
            logger.info("✓ Deployment completed successfully!")
            return True
            
        except Exception as e:
            logger.error(f"Deployment failed with exception: {e}")
            return False

    def run_hooks(self, hook_type: str) -> bool:
        """Execute deployment hooks"""
        hooks = self.config.get('hooks', {}).get(hook_type, [])
        
        if not hooks:
            logger.info(f"No {hook_type} hooks defined")
            return True
        
        logger.info(f"Executing {hook_type} hooks...")
        
        try:
            for i, hook in enumerate(hooks):
                if hook.get('type') == 'command':
                    cmd = hook['command']
                    logger.info(f"Running hook command: {cmd}")
                    
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
                        return False
                    
                    if result.stdout:
                        logger.info(f"Hook output: {result.stdout}")
                
                elif hook.get('type') == 'script':
                    script_name = hook['script']
                    logger.info(f"Running hook script: {script_name}")
                    
                    if not self._run_script(script_name, f"Hook script {script_name}"):
                        logger.error(f"Hook script failed: {script_name}")
                        return False
            
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
