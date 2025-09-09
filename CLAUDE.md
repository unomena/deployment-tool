# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PyDeployer is a modular Django deployment automation tool for Ubuntu LTS servers. It uses a Python orchestrator (`scripts/deploy.py`) to coordinate focused shell scripts that handle specific deployment tasks.

## Quick Start Commands

```bash
# Development setup
make build                          # Create deployment tool's .venv and install dependencies
make lint                           # Run flake8 on Python scripts  
make format                         # Format with black
make test                           # Run syntax validation and tests

# Deployment (2-parameter interface)
./deploy <repo_url> <branch>        # Deploy branch with automatic config fallback

# Examples
./deploy https://github.com/user/repo.git main          # Uses deploy-main.yml or deploy.yml
./deploy git@github.com:user/repo.git feature/new       # Uses deploy-feature-new.yml or deploy.yml
```

## Architecture

### Critical Design: Virtual Environment Isolation

**IMPORTANT**: This system maintains strict separation between:
1. **Deployment tool venv** (`.venv/`) - For running the orchestrator
2. **Project venvs** (`/srv/deployments/{project}/{branch}/venv/`) - For each deployed Django app

Django operations MUST use `PROJECT_PYTHON_PATH` environment variable pointing to the project's venv Python, not the deployment tool's venv.

### Directory Structure

```
/srv/deployments/{project}/{normalized-branch}/
├── code/           # Cloned repository
├── venv/           # Project's isolated virtual environment  
├── config/         # Generated configs (supervisor, nginx)
│   ├── supervisor/ # Supervisor service configurations
│   └── nginx/      # Nginx reverse proxy configurations
└── logs/           # Application and service logs
    ├── supervisor/ # Supervisor process logs
    └── app/        # Application logs
```

### Script Responsibilities

Each script in `scripts/` handles ONE specific concern:

- `deploy.py` - Python orchestrator that coordinates all scripts
- `clone-repository.sh` - Git operations
- `setup-python-environment.sh` - Create project venv with specified Python version
- `install-python-dependencies.sh` - Install packages in project venv
- `create-django-superuser.sh` - Create Django admin user (uses PROJECT_PYTHON_PATH)
- `validate-django-environment.sh` - Validate Django setup (uses PROJECT_PYTHON_PATH)
- `verify-postgresql-database.sh` - PostgreSQL database/user creation
- `generate-supervisor-configs.py` - Generate supervisor service configs
- `install-supervisor-configs.sh` - Install configs to system supervisor
- `generate-nginx-configs.py` - Generate nginx reverse proxy configurations
- `install-nginx-configs.sh` - Install nginx configs and setup domains

### Environment Variable Flow

The orchestrator passes configuration via environment variables:
- `BASE_PATH`, `CODE_PATH`, `VENV_PATH` - Directory paths
- `PROJECT_PYTHON_PATH`, `PROJECT_PIP_PATH` - Project venv executables
- `DJANGO_PROJECT_DIR` - Django project directory
- All `env_vars` from YAML config

## Configuration System

Branch-based YAML configs with fallback (`deploy-{branch}.yml` → `deploy.yml`):

```yaml
name: "myapp"
environment: "dev"               # Optional environment identifier
python_version: "3.12"

dependencies:
  system: ["postgresql", "nginx", "redis-server"]
  python: ["django", "psycopg2", "gunicorn", "celery"]  
  python-requirements: ["requirements.txt"]

env_vars:                        # Passed to Django app
  DJANGO_SETTINGS_MODULE: "project.settings"
  SECRET_KEY: "..."
  DB_NAME: "myapp_dev_db"

services:                        # Supervisor services with nginx integration
  - name: web
    type: gunicorn
    command: "gunicorn project.wsgi:application"
    workers: 3
    port: 8000                   # Auto-allocated if conflicts
    domain: "myapp-dev.local"    # Optional domain override
    
  - name: worker
    type: celery
    command: "celery -A project worker -l info"
    workers: 2
```

## Development Workflow

### Testing Changes

1. **Scripts**: Test individual scripts with proper environment variables
2. **Orchestrator**: Test `scripts/deploy.py` workflow locally  
3. **Full deployment**: Test on Ubuntu server with `./deploy` command

### Common Issues & Solutions

**Virtual Environment Context Issues**
- Symptom: Django commands fail with import errors
- Fix: Verify Django scripts use `$PROJECT_PYTHON_PATH` not system Python

**Permission Issues**  
- Symptom: Cannot write to `/srv/deployments/`
- Fix: Run with appropriate user/sudo privileges

**Service Startup Issues**
- Symptom: Supervisor services fail to start
- Fix: Check supervisor configs and service dependencies

## Key Implementation Rules

1. **Never mix virtual environments** - Django operations use project venv, not deployment tool venv
2. **Scripts handle one responsibility** - Each script does one thing well
3. **Environment variables pass context** - All configuration flows through env vars
4. **Ubuntu LTS only** - Uses apt-get, systemctl, supervisor (not cross-platform)
5. **Fail fast with clear errors** - Scripts should exit immediately on errors with descriptive messages

## Next Steps (from TODO.md)

Current priorities for Ubuntu server testing:
1. Test system dependency installation (`install-system-dependencies.sh`)
2. Validate PostgreSQL database creation and Django connectivity
3. Test supervisor service configuration and startup
4. Verify health checks and rollback mechanisms
5. Test multiple simultaneous environment deployments