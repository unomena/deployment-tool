# PyDeployer - Django Deployment Automation

A comprehensive deployment automation tool for Django applications that reads YAML configuration files and sets up complete deployment environments on Ubuntu LTS systems.

## Features

- **System Dependencies**: Automatically installs Ubuntu packages via `apt-get`
- **Python Environment**: Creates virtual environments with specific Python versions
- **Repository Management**: Clones Git repositories with branch support
- **Supervisor Integration**: Generates and installs Supervisor configurations for services
- **Multi-Environment Support**: Supports `prod`, `qa`, `stage`, and `dev` environments
- **Validation**: Comprehensive deployment validation and health checks
- **Structured Deployment**: Organized folder structure under `/srv/deployments/`

## Directory Structure

The tool creates a standardized directory structure:

```
/srv/deployments/
└── <project-name>/
    └── <environment>/
        └── <branch>/
            ├── code/           # Application code
            ├── config/         # Configuration files
            │   ├── supervisor/ # Supervisor service configs
            │   └── nginx/      # Nginx configs (future)
            ├── logs/           # Log files
            │   ├── supervisor/ # Supervisor logs
            │   └── app/        # Application logs
            └── venv/           # Python virtual environment
```

## Installation

1. Install Python dependencies:
```bash
pip install -r requirements.txt
```

2. Make the script executable:
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
