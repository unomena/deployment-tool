# PyDeployer - Modular Django Deployment Automation Tool

PyDeployer is a lightweight, modular deployment automation tool designed specifically for Django applications on Ubuntu LTS systems. It uses a separation-of-concerns architecture where a Python orchestrator coordinates focused shell and Python scripts to handle different deployment aspects.

## Architecture

- **Lightweight Orchestrator**: `deploy.py` coordinates deployment workflow
- **Focused Scripts**: Each script in `scripts/` handles one specific deployment aspect
- **Environment Variables**: Configuration and data passing between orchestrator and scripts
- **Modular Design**: Testable, maintainable, and reusable components

## Features

- **Modular Script Architecture**: Separate scripts for each deployment concern
- **Automated Environment Setup**: Python virtual environments with version management
- **Dependency Management**: System and Python dependencies from YAML configuration
- **Database Integration**: PostgreSQL setup with user permissions and validation
- **Process Management**: Dynamic Supervisor configuration generation and installation
- **Git Integration**: Repository cloning with branch support and SSH keys
- **Comprehensive Validation**: Multi-level deployment validation and health checks
- **Hook System**: Pre/post-deploy hooks supporting both commands and scripts
- **Error Handling**: Detailed logging with color-coded output and proper exit codes

## Modular Scripts

### Core Deployment Scripts
- `install-system-dependencies.sh` - Ubuntu system package installation
- `setup-python-environment.sh` - Python virtual environment with version management
- `clone-repository.sh` - Git repository cloning with branch and SSH support
- `install-python-dependencies.sh` - Python packages and requirements installation
- `generate-supervisor-configs.py` - Dynamic Supervisor configuration generation
- `install-supervisor-configs.sh` - System Supervisor configuration installation
- `validate-deployment.sh` - Complete deployment validation

### Django-Specific Scripts
- `verify-postgresql-database.sh` - PostgreSQL database setup and verification
- `validate-django-environment.sh` - Django environment and configuration validation
- `create-django-superuser.sh` - Django admin user creation with validation

## Directory Structure

```
/srv/deployments/{project}/{environment}/{branch}/
├── code/           # Application source code (cloned repository)
├── config/         # Generated configuration files
│   ├── supervisor/ # Supervisor service configurations
│   └── nginx/      # Nginx configurations (if applicable)
├── logs/           # Application and service logs
│   ├── supervisor/ # Supervisor process logs
│   └── app/        # Application logs
└── venv/           # Python virtual environment
```

## Installation

### Prerequisites

- **Ubuntu LTS Server** (18.04, 20.04, 22.04, or later)
- **Python 3.8+** (Python 3.12 recommended)
- **Git** for repository operations
- **sudo privileges** for system package installation

### Setup on Ubuntu Server

1. Clone the repository:
```bash
git clone <repository-url>
cd deployment-tool
```

2. Install Python dependencies:
```bash
make build
```

3. Ensure scripts are executable (should already be set):
```bash
chmod +x scripts/*.sh scripts/*.py
```

## Quick Start

### Basic Usage

1. Configure your deployment in a YAML file (see `deploy-branch.yml` example):
```bash
cp deploy-branch.yml my-app-deploy.yml
# Edit my-app-deploy.yml with your project settings
```

2. Run the deployment:
```bash
make deploy CONFIG=my-app-deploy.yml BRANCH=main
```

Or run directly:
```bash
python3 deploy.py --config my-app-deploy.yml --branch main --verbose
```

### Development/Testing

For local testing with custom base directory:
```bash
chmod +x deploy.py
```

## Configuration File Format

The deployment script reads YAML configuration files. Here's the structure:

```yaml
name: sample-app                    # Project name
environment: dev                    # Environment (prod/qa/stage/dev)
repo: git@github.com:user/repo.git  # Git repository (optional)
python_version: "3.12"              # Python version

dependencies:
  system:                           # Ubuntu packages
    - postgresql-client
    - libpq-dev
    - python3-dev
    - build-essential
  python:                           # Python packages
    - postgresql
    - redis
    - celery
    - gunicorn
  python-requirements:              # Requirements files
    - requirements.txt

environment:                        # Environment variables
  DJANGO_SETTINGS_MODULE: project.settings_dev
  DEBUG: "0"
  SECRET_KEY: "your-secret-key"
  DB_HOST: "localhost"
  DB_NAME: "myapp-db"

database:                           # Database configuration
  type: postgresql
  name: ${DB_NAME}
  user: ${DB_USER}
  password: ${DB_PASSWORD}
  host: ${DB_HOST}
  port: ${DB_PORT}

services:                           # Services to run
  - name: web
    type: gunicorn
    command: "gunicorn project.wsgi:application"
    workers: 3
    port: 8010

  - name: worker
    type: celery
    command: "celery -A project worker -l info"
    workers: 4

  - name: beat
    type: celery
    command: "celery -A project beat -l info"
```

## Usage

### Basic Deployment
```bash
sudo python3 deploy.py deploy-branch.yml
```

### Deploy Specific Branch
```bash
sudo python3 deploy.py deploy-branch.yml --branch feature-branch
```

### Verbose Output
```bash
sudo python3 deploy.py deploy-branch.yml --verbose
```

## What the Script Does

1. **Reads Configuration**: Parses YAML config and validates required fields
2. **Creates Directory Structure**: Sets up organized folder hierarchy
3. **Installs System Dependencies**: Uses `apt-get` to install Ubuntu packages
4. **Sets Up Python Environment**: Creates virtual environment with specified Python version
5. **Clones Repository**: Downloads code from Git repository (if specified)
6. **Installs Python Dependencies**: Installs packages and requirements in virtual environment
7. **Generates Supervisor Configs**: Creates service configurations for each service
8. **Installs Supervisor Configs**: Copies configurations to system and reloads Supervisor
9. **Validates Deployment**: Runs comprehensive checks to ensure everything is working

## Supervisor Configuration

For each service, the script generates a Supervisor configuration like:

```ini
[program:sample-app-web]
command=/srv/deployments/sample-app/dev/main/venv/bin/gunicorn project.wsgi:application
directory=/srv/deployments/sample-app/dev/main/code
user=www-data
autostart=true
autorestart=true
startsecs=10
startretries=3
stdout_logfile=/srv/deployments/sample-app/dev/main/logs/supervisor/web.log
stderr_logfile=/srv/deployments/sample-app/dev/main/logs/supervisor/web_error.log
environment=DJANGO_SETTINGS_MODULE=project.settings_dev,DEBUG=0,SECRET_KEY=your-secret-key
numprocs=3
process_name=%(program_name)s_%(process_num)02d
```

## Prerequisites

- Ubuntu LTS system
- Python 3.8+ available on system
- `sudo` access for installing packages and Supervisor configs
- Git (if using repository cloning)
- Supervisor installed (`sudo apt-get install supervisor`)

## Validation Checks

The script performs these validation checks:

- ✓ Directory structure exists
- ✓ Virtual environment is functional
- ✓ Python dependencies are installed
- ✓ Supervisor configurations are in place

## Example Commands

### Install Supervisor (if not installed)
```bash
sudo apt-get update
sudo apt-get install supervisor
sudo systemctl enable supervisor
sudo systemctl start supervisor
```

### Check Supervisor Status
```bash
sudo supervisorctl status
```

### Restart Services
```bash
sudo supervisorctl restart sample-app-web:*
sudo supervisorctl restart sample-app-worker:*
```

## Troubleshooting

### Permission Issues
Make sure to run the script with `sudo` for system-level operations:
```bash
sudo python3 deploy.py config.yml
```

### Python Version Not Found
The script automatically installs Python versions using the deadsnakes PPA:
```bash
# This is done automatically by the script
sudo add-apt-repository ppa:deadsnakes/ppa
sudo apt-get install python3.12 python3.12-venv
```

### Supervisor Not Starting Services
Check Supervisor logs:
```bash
sudo supervisorctl tail sample-app-web stderr
sudo tail -f /srv/deployments/sample-app/dev/main/logs/supervisor/web_error.log
```

## Security Considerations

- The script requires `sudo` access for system operations
- Services run as `www-data` user for security
- Environment variables are passed securely to processes
- Logs are stored in project-specific directories

## License

This tool is designed for internal deployment automation. Modify as needed for your specific requirements.
