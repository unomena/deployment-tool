# PyDeployer - Modular Django Deployment Automation Tool

PyDeployer is a lightweight, modular deployment automation tool designed specifically for Django applications on Ubuntu LTS systems. It uses a separation-of-concerns architecture where a Python orchestrator coordinates focused shell and Python scripts to handle different deployment aspects.

## Architecture

- **Lightweight Orchestrator**: `deploy.py` coordinates deployment workflow
- **Focused Scripts**: Each script in `scripts/` handles one specific deployment aspect
- **Environment Variables**: Configuration and data passing between orchestrator and scripts
- **Modular Design**: Testable, maintainable, and reusable components

## Features

- **Branch-Only Deployment**: Deploy any branch without environment parameters
- **Fallback Configuration**: `deploy-{branch}.yml` → `deploy.yml` automatic fallback
- **Domain Configuration**: Flexible domain management with service-level overrides
- **Multi-Site Support**: Serve multiple sites from same codebase with different domains
- **Service-Level Overrides**: Per-service environment variables and domain configuration
- **Modular Script Architecture**: Separate scripts for each deployment concern
- **Automated Environment Setup**: Python virtual environments with version management
- **Dependency Management**: System and Python dependencies from YAML configuration
- **Database Integration**: PostgreSQL setup with user permissions and validation
- **Process Management**: Dynamic Supervisor configuration generation and installation
- **Nginx Reverse Proxy**: Automatic nginx configuration with port 80 access for all services
- **Port Allocation**: Intelligent port assignment (8000, 8001, 8002...) for conflicting services
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
- `generate-nginx-configs.py` - Nginx reverse proxy configuration generation
- `install-nginx-configs.sh` - System nginx configuration installation and domain setup
- `validate-deployment.sh` - Complete deployment validation

### Django-Specific Scripts
- `verify-postgresql-database.sh` - PostgreSQL database setup and verification
- `validate-django-environment.sh` - Django environment and configuration validation
- `create-django-superuser.sh` - Django admin user creation with validation

## Directory Structure

```
/srv/deployments/{project}/{normalized-branch}/
├── code/           # Application source code (cloned repository)
├── config/         # Generated configuration files
│   ├── supervisor/ # Supervisor service configurations
│   └── nginx/      # Nginx reverse proxy configurations
├── logs/           # Application and service logs
│   ├── supervisor/ # Supervisor process logs
│   └── app/        # Application logs
├── static/         # Django static files (if applicable)
├── media/          # Django media files (if applicable)
└── venv/           # Python virtual environment
```

**Branch Normalization**: Branch names with slashes are normalized (e.g., `feature/auth` → `feature-auth`)

## Installation

### Prerequisites

- **Ubuntu LTS Server** (18.04, 20.04, 22.04, or later)
- **Python 3.8+** (Python 3.12 recommended)
- **Git** for repository operations
- **sudo privileges** for system package installation

### Setup on Ubuntu Server

1. Clone the repository:
```bash
git clone git@github.com:unomena/deployment-tool.git
cd deployment-tool
```

2. Install system dependencies (PostgreSQL, Redis, Supervisor, Nginx):
```bash
sudo ./install
# OR using Makefile
make system-install
```

3. Install Python dependencies:
```bash
make build
```

4. Ensure scripts are executable (should already be set):
```bash
chmod +x scripts/*.sh scripts/*.py
```

## Quick Start

The deployment tool uses a simplified 2-parameter interface:

```bash
./deploy <repository_url> <branch_or_sha>
```

### Configuration Files

The deployment tool uses a **fallback configuration system**:

1. **Branch-specific config**: `deploy-{normalized-branch}.yml` (e.g., `deploy-dev.yml`, `deploy-feature-auth.yml`)
2. **Default fallback**: `deploy.yml` (used when branch-specific config doesn't exist)

**Examples**:
- `deploy-main.yml` for main branch deployments
- `deploy-dev.yml` for dev branch deployments  
- `deploy-feature-auth.yml` for feature/auth branch deployments
- `deploy.yml` as fallback for any branch without specific config

### Basic Usage

Deploy directly from any repository:
```bash
# Deploy main branch
./deploy https://github.com/myorg/myapp.git main

# Deploy feature branch (creates feature-new-ui deployment)
./deploy git@github.com:myorg/myapp.git feature/new-ui

# Deploy specific version
./deploy https://github.com/myorg/myapp.git v1.2.3

# Deploy qa branch
./deploy git@github.com:myorg/myapp.git qa
```

### Using Makefile

```bash
# Deploy with Makefile
make deploy REPO_URL=https://github.com/myorg/myapp.git BRANCH=main
```

### Development/Testing

For development of the deployment tool itself:
```bash
chmod +x deploy.py
```

## Configuration File Format

The deployment script reads YAML configuration files with support for domain configuration and service-level overrides:

```yaml
name: sample-app                    # Project name
repo: git@github.com:user/repo.git  # Git repository (optional)
python_version: "3.12"              # Python version
domain: "myapp.local"               # Default domain for all web services

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

env_vars:                           # Root environment variables (inherited by all services)
  DJANGO_SETTINGS_MODULE: project.settings_dev
  DEBUG: "0"
  SECRET_KEY: "your-secret-key"
  DB_HOST: "localhost"
  DB_NAME: "${PROJECT_NAME}-${NORMALIZED_BRANCH}"  # Note: hyphens, not underscores

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
    port: 8000
    # Uses default domain: myapp.local
    # Uses all root env_vars

  - name: admin
    type: gunicorn
    command: "gunicorn project.wsgi:application"
    workers: 2
    port: 8001
    domain: "admin.myapp.local"      # Service-specific domain override
    env_vars:                        # Service-specific environment variables
      DJANGO_SETTINGS_MODULE: "project.settings.admin"  # Override root setting
      DEBUG: "True"                 # Override root setting
      ADMIN_ONLY: "True"            # New variable specific to this service
      # All other root env_vars are still inherited

  - name: worker
    type: celery
    command: "celery -A project worker -l info"
    workers: 4
    # No domain (not a web service)
    # Uses all root env_vars as-is
```

## Domain Configuration

### Default Domain Pattern
If no `domain` is specified in the configuration, the default pattern is:
```
{project-name}-{normalized-branch}
```

Examples:
- `sample-app` + `main` → `sample-app-main`
- `good-times-unomena` + `feature/auth` → `good-times-unomena-feature-auth`

### Root Domain Override
Set a default domain for all web services:
```yaml
domain: "myapp.local"  # All web services use this domain by default
```

### Service-Level Domain Override
Override domain for specific services:
```yaml
services:
  - name: web
    domain: "www.myapp.local"  # Override for this service only
  - name: admin
    domain: "admin.myapp.local"  # Different domain for admin
```

### Multi-Site Deployment
Serve completely different sites from the same codebase:
```yaml
domain: "myapp.local"  # Default domain

services:
  - name: web
    # Uses default domain: myapp.local
    
  - name: admin
    domain: "admin.myapp.local"
    env_vars:
      DJANGO_SETTINGS_MODULE: "myapp.settings.admin"
      SITE_THEME: "admin"
      
  - name: api
    domain: "api.myapp.local"
    env_vars:
      DJANGO_SETTINGS_MODULE: "myapp.settings.api"
      API_VERSION: "v2"
```

## Nginx Reverse Proxy Integration

The deployment tool automatically generates and installs nginx reverse proxy configurations for all web services, providing seamless port 80 access.

### Automatic Features
- **Port 80 Access**: All services accessible via standard HTTP port
- **Domain-Based Routing**: Each service gets its own domain/subdomain
- **Intelligent Port Allocation**: Automatic port assignment (8000, 8001, 8002...) for conflicting services
- **Automatic Installation**: Nginx configs generated and enabled during deployment
- **Domain Management**: Automatic `/etc/hosts` entries for local testing

### Generated Files
- `config/nginx/{domain}.conf` - Individual site configurations
- `config/nginx/README.md` - Deployment instructions and URLs

### Configuration Features
- Upstream configuration based on allocated service ports
- SSL-ready configurations (commented out by default)
- Static/media file serving for Django applications
- Security headers and performance optimizations
- Health check endpoints (`/nginx-health`)

### Access URLs
After deployment, services are accessible via:
- **Main service**: `http://{project-name}-{branch}/` → Django on port 8000
- **Additional services**: `http://{custom-domain}/` → Django on allocated ports
- **Example**: `http://sampleapp-dev/`, `http://goodtimes.local/`, `http://admin.goodtimes.local/`

### Manual Management
```bash
# Check nginx status
make nginx-status

# Test nginx configuration
make nginx-test

# Reload nginx after manual changes
make nginx-reload
```

## Usage

### Command Line Interface
```bash
# Basic deployment
./deploy <repository_url> <branch>

# Examples
./deploy https://github.com/myorg/myapp.git main
./deploy git@github.com:myorg/myapp.git feature/auth
```

### Makefile Interface
```bash
# Deploy using Makefile
make deploy REPO_URL=<url> BRANCH=<branch>

# Quick shortcuts
make deploy-main REPO_URL=<url>
make deploy-dev REPO_URL=<url>

# Configuration validation
make validate-config PROJECT=<project> BRANCH=<branch>
make show-config PROJECT=<project> BRANCH=<branch>
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
[program:sample-app-main-web]
command=/srv/deployments/sample-app/main/venv/bin/gunicorn project.wsgi:application
directory=/srv/deployments/sample-app/main/code
user=www-data
autostart=true
autorestart=true
startsecs=10
startretries=3
stdout_logfile=/srv/deployments/sample-app/main/logs/supervisor/web.log
stderr_logfile=/srv/deployments/sample-app/main/logs/supervisor/web_error.log
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
sudo supervisorctl restart sample-app-main-web:*
sudo supervisorctl restart sample-app-main-worker:*
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
sudo supervisorctl tail sample-app-main-web stderr
sudo tail -f /srv/deployments/sample-app/main/logs/supervisor/web_error.log
```

## Security Considerations

- The script requires `sudo` access for system operations
- Services run as `www-data` user for security
- Environment variables are passed securely to processes
- Logs are stored in project-specific directories

## License

This tool is designed for internal deployment automation. Modify as needed for your specific requirements.
