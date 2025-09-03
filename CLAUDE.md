# Django Deployment Automation Tool - AI Developer Guide

## Project Overview & Purpose 🎯

This is a **modular Django deployment automation tool** specifically designed for **Ubuntu LTS servers**. The primary objective is to provide a maintainable, reliable, and easy-to-use deployment system that separates concerns through focused scripts while maintaining strict virtual environment isolation.

### Key Objectives
- **Simplicity**: Single command deployment with minimal parameters
- **Modularity**: Focused scripts handling specific deployment aspects
- **Isolation**: Strict separation between deployment tool and project environments
- **Reliability**: Comprehensive error handling and rollback capabilities
- **Maintainability**: Clean architecture allowing easy modification and testing

## Architecture & Design Philosophy 🏗️

### Core Architecture Principles

1. **Modular Script Architecture**
   - Lightweight Python orchestrator (`scripts/deploy.py`)
   - Focused shell scripts for specific tasks (system deps, venv setup, etc.)
   - Clear separation of concerns for maintainability

2. **Simplified User Interface**
   - Root-level `deploy` shell script with 3-parameter interface
   - Environment-based configuration selection
   - Minimal user input required: `./deploy <repo_url> <branch> <env>`

3. **Virtual Environment Isolation** (Critical Design Decision)
   - **Deployment tool** runs in its own `.venv` (managed by Makefile)
   - **Each deployed project** gets isolated venv at deployment location
   - **Django operations** execute in project venv, not deployment tool venv

### Directory Structure
```
deployment-tool/
├── deploy                      # Root deployment script (entry point)
├── scripts/
│   ├── deploy.py              # Python orchestrator
│   ├── clone-repository.sh    # Git operations
│   ├── setup-python-environment.sh
│   ├── install-python-dependencies.sh
│   ├── create-django-superuser.sh
│   ├── validate-django-environment.sh
│   ├── verify-postgresql-database.sh
│   ├── install-system-dependencies.sh
│   ├── install-supervisor-configs.sh
│   ├── generate-supervisor-configs.py
│   └── validate-deployment.sh
├── deploy-{env}.yml           # Environment-specific configs
├── Makefile                   # Development environment management
└── requirements.txt           # Deployment tool dependencies
```

## Critical Implementation Details ⚙️

### Virtual Environment Context (SOLVED ISSUE)
**Problem**: Initial implementation had virtual environment context confusion where Django management commands were running in the deployment tool's venv instead of the project's venv.

**Solution**: 
- `deploy.py` sets `PROJECT_PYTHON_PATH` environment variable pointing to project's venv Python
- Django scripts (`create-django-superuser.sh`, `validate-django-environment.sh`) use `PROJECT_PYTHON_PATH`
- Clear separation: deployment tool operations vs project operations

### Environment Variable Flow
```
deploy script → deploy.py → individual scripts
              ↓
          Environment variables:
          - BASE_PATH, CODE_PATH, VENV_PATH
          - PROJECT_PYTHON_PATH, PROJECT_PIP_PATH
          - DJANGO_PROJECT_DIR
          - All project env_vars from YAML config
```

### Configuration System
- **Environment-based selection**: `deploy-prod.yml`, `deploy-dev.yml`, etc.
- **YAML structure**:
  ```yaml
  project:
    name: "myapp"
    python_version: "3.12"
  
  environment: "prod"  # Deployment environment
  
  env_vars:            # Project environment variables
    DEBUG: "False"
    SECRET_KEY: "..."
  
  dependencies:
    system: ["nginx", "postgresql"]
    python: ["django", "psycopg2"]
    requirements_files: ["requirements.txt"]
  ```

## Key Features & Functionality 🚀

### 1. Simplified Deployment Interface
```bash
# Deploy main branch to production
./deploy https://github.com/user/repo.git main prod

# Deploy feature branch to development
./deploy git@github.com:user/repo.git feature/new-ui dev
```

### 2. Automatic Environment Selection
- `prod` environment → `deploy-prod.yml`
- `dev` environment → `deploy-dev.yml`  
- `branch` environment → `deploy-branch.yml`
- Custom environments supported

### 3. Comprehensive Deployment Steps
1. **Repository Operations**: Clone and checkout specific branch/SHA
2. **System Dependencies**: Install Ubuntu packages via apt-get
3. **Python Environment**: Create isolated project venv with specified version
4. **Python Dependencies**: Install packages and requirements files
5. **Database Setup**: Create PostgreSQL database and user
6. **Django Operations**: Run migrations, create superuser, collect static files
7. **Service Configuration**: Generate and install supervisor configs
8. **Health Checks**: Validate deployment success
9. **Rollback**: Automatic rollback on failure

### 4. Virtual Environment Management
- **Deployment Tool**: Uses `.venv` created by `make build`
- **Projects**: Each gets isolated venv at `{BASE_PATH}/{ENVIRONMENT}/{BRANCH}/venv`
- **Django Commands**: Execute in project venv via `PROJECT_PYTHON_PATH`

## Development Workflow 🔄

### Setting Up Development Environment
```bash
# Clone repository
git clone <repo-url>
cd deployment-tool

# Set up development environment
make build                    # Creates .venv and installs dependencies
make help                     # Show available commands

# Development helpers
make lint                     # Code linting
make format                   # Code formatting
make test                     # Run tests
```

### Making Changes
1. **Scripts**: Modify individual scripts in `scripts/` directory
2. **Orchestrator**: Update `scripts/deploy.py` for workflow changes
3. **Configuration**: Modify YAML configs for deployment settings
4. **Testing**: Use `make test` and validate on Ubuntu server

### Deployment Testing
```bash
# Validate configuration
make validate CONFIG=test-deploy.yml

# Test deployment (requires Ubuntu server)
./deploy <test-repo> main test
```

## Technical Constraints & Considerations 🔧

### Platform Requirements
- **Ubuntu LTS servers only** - Uses `apt-get`, `systemctl`, `supervisor`
- **Python 3.8+** preferred (3.12 recommended)
- **Sudo privileges required** for system package installation

### Security Considerations
- Environment variables for sensitive data (DB passwords, secret keys)
- SSH key authentication for git repositories
- Proper file permissions and ownership
- Service user isolation

### Known Dependencies
- **System**: git, python3, python3-venv, build-essential
- **Optional**: supervisor, nginx, postgresql, redis-server
- **Python**: PyYAML, pathlib, subprocess

## Usage Examples 📖

### Basic Django Project Deployment
```bash
# 1. Create deployment configuration
cp deploy-branch.yml deploy-myapp-prod.yml

# 2. Edit configuration
vim deploy-myapp-prod.yml

# 3. Deploy to production
./deploy https://github.com/user/myapp.git main prod
```

### Development Workflow
```bash
# Deploy feature branch for testing
./deploy git@github.com:user/myapp.git feature/auth-system dev

# Deploy specific commit
./deploy https://github.com/user/myapp.git abc1234 staging
```

### Makefile Usage
```bash
# Development setup
make build
make dev-setup               # Build + lint + format

# Deployment via Makefile
make deploy REPO_URL=<url> BRANCH=main ENV=prod
```

## Troubleshooting Common Issues 🔍

### Virtual Environment Issues
- **Problem**: Django commands fail with import errors
- **Solution**: Verify `PROJECT_PYTHON_PATH` is set correctly in Django scripts

### Permission Issues  
- **Problem**: Cannot write to deployment directories
- **Solution**: Check user permissions, may need `sudo` or different user context

### Service Startup Issues
- **Problem**: Supervisor services fail to start
- **Solution**: Check supervisor configs, verify service dependencies installed

### Database Connection Issues
- **Problem**: Django cannot connect to PostgreSQL
- **Solution**: Verify database creation, user permissions, and connection settings

## Future Enhancement Areas 🔮

### Potential Improvements
- **Docker Support**: Container-based deployments
- **Multi-Server Deployments**: Orchestrate across multiple servers  
- **Blue-Green Deployments**: Zero-downtime deployment strategy
- **Monitoring Integration**: Built-in monitoring and alerting
- **Web Dashboard**: GUI for deployment management

### Testing Enhancements
- **Unit Tests**: Comprehensive test coverage for all scripts
- **Integration Tests**: End-to-end deployment testing
- **CI/CD Integration**: GitHub Actions or similar

## Important Notes for AI Developers 🤖

### Virtual Environment Context is Critical
The most important aspect of this system is **virtual environment separation**. Always ensure:
- Django management commands use `PROJECT_PYTHON_PATH`
- Project dependencies install in project venv, not deployment tool venv
- Environment variables properly pass context between scripts

### Modular Design Philosophy
Each script should:
- Handle one specific responsibility
- Accept configuration via environment variables
- Provide comprehensive error handling and logging
- Be testable independently

### Ubuntu Server Focus
This tool is specifically designed for Ubuntu servers. Don't attempt to make it cross-platform without significant architectural changes.

### Error Handling Strategy
- Fail fast with clear error messages
- Provide rollback capabilities where possible
- Log all operations comprehensively
- Return appropriate exit codes

---

## Getting Started for AI Developers

1. **Read this document thoroughly**
2. **Review TODO.md for current priorities**
3. **Study the modular script architecture**
4. **Test on Ubuntu server environment**
5. **Focus on virtual environment isolation**
6. **Follow the existing patterns and conventions**

This tool represents a balance between simplicity and power - maintain that balance in any modifications or enhancements.
