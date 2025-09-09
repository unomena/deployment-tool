# Branch Deployment Examples

This document provides comprehensive examples of branch-based deployments using the PyDeployer tool. The deployment system supports any branch name with automatic normalization, fallback configuration, and flexible domain management.

## Overview

The deployment tool uses a **branch-only** architecture with advanced configuration features:

### Key Features

- **Branch-Only Deployment**: Deploy any branch without specifying environments
- **Fallback Configuration**: `deploy-{branch}.yml` → `deploy.yml` automatic fallback
- **Domain Configuration**: Flexible domain management with service-level overrides
- **Multi-Site Support**: Serve multiple sites from same codebase with different domains
- **Service-Level Overrides**: Per-service environment variables and domain configuration
- **Automatic Branch Normalization**: Slashes in branch names are converted to hyphens
- **Database Naming**: Consistent hyphen-based naming for databases and services
- **Directory Structure**: `/srv/deployments/{project}/{normalized-branch}/`
- **Nginx Integration**: Automatic reverse proxy configuration generation

## Branch Normalization

Branch names are automatically normalized for compatibility:

- `main` → `main`
- `dev` → `dev` 
- `feature/authentication` → `feature-authentication`
- `hotfix/critical-bug` → `hotfix-critical-bug`
- `release/v1.2.3` → `release-v1.2.3`

## Configuration System

### Fallback Configuration Priority

1. **Branch-specific**: `deploy-{normalized-branch}.yml`
2. **Default fallback**: `deploy.yml`

Examples:
- Branch `dev` → looks for `deploy-dev.yml`, falls back to `deploy.yml`
- Branch `feature/auth` → looks for `deploy-feature-auth.yml`, falls back to `deploy.yml`
- Branch `main` → looks for `deploy-main.yml`, falls back to `deploy.yml`

## Deployment Examples

### 1. Main Branch Deployment
```bash
# Deploy main branch
./deploy https://github.com/myorg/myapp.git main

# Results in:
# - Directory: /srv/deployments/myapp/main/
# - Database: myapp-main
# - Services: myapp-main-web, myapp-main-worker
# - Config: deploy-main.yml (or deploy.yml as fallback)
# - Domain: myapp-main (default) or custom domain from config
```

### 2. Development Branch Deployment
```bash
# Deploy dev branch
./deploy git@github.com:myorg/myapp.git dev

# Results in:
# - Directory: /srv/deployments/myapp/dev/
# - Database: myapp-dev
# - Services: myapp-dev-web, myapp-dev-worker
# - Config: deploy-dev.yml (or deploy.yml as fallback)
# - Domain: myapp-dev (default) or custom domain from config
```

### 3. Feature Branch Deployment
```bash
# Deploy feature branch with slash
./deploy git@github.com:myorg/myapp.git feature/authentication

# Results in:
# - Directory: /srv/deployments/myapp/feature-authentication/
# - Database: myapp-feature-authentication
# - Services: myapp-feature-authentication-web, myapp-feature-authentication-worker
# - Config: deploy-feature-authentication.yml (or deploy.yml as fallback)
# - Domain: myapp-feature-authentication (default) or custom domain from config
```

### 4. Multi-Site Deployment Example
```bash
# Deploy with multi-site configuration
./deploy git@github.com:myorg/ecommerce.git main

# With this deploy.yml configuration:
# domain: "shop.local"
# services:
#   - name: web
#     # Uses default domain: shop.local
#   - name: admin
#     domain: "admin.shop.local"
#   - name: api
#     domain: "api.shop.local"

# Results in:
# - shop.local → main ecommerce site
# - admin.shop.local → admin interface
# - api.shop.local → API service
# - All services share same database: ecommerce-main
```

## Configuration File Examples

### Main Branch Configuration (`deploy-main.yml`)
```yaml
name: myapp
python_version: "3.11"
repo: https://github.com/myorg/myapp.git

dependencies:
  system:
    - postgresql-client
    - redis-tools
  python-requirements:
    - requirements.txt

env_vars:
  DJANGO_SETTINGS_MODULE: "myapp.settings"
  SECRET_KEY: "production-secret-key"
  DEBUG: "False"
  DB_NAME: "${PROJECT_NAME}-${NORMALIZED_BRANCH}"
  DB_USER: "${PROJECT_NAME}-${NORMALIZED_BRANCH}"
  DB_PASSWORD: "secure-password"

database:
  type: postgresql
  name: ${DB_NAME}
  user: ${DB_USER}
  password: ${DB_PASSWORD}

services:
  - name: web
    type: gunicorn
    command: "gunicorn myapp.wsgi:application"
    workers: 4
    port: 8000
```

### Feature Branch Configuration (`deploy-feature-authentication.yml`)
```yaml
name: myapp
python_version: "3.11"
repo: https://github.com/myorg/myapp.git

dependencies:
  system:
    - postgresql-client
    - redis-tools
  python-requirements:
    - requirements.txt

env_vars:
  DJANGO_SETTINGS_MODULE: "myapp.settings"
  SECRET_KEY: "feature-dev-key"
  DEBUG: "True"
  # Database will be: myapp-feature-authentication
  DB_NAME: "${PROJECT_NAME}-${NORMALIZED_BRANCH}"
  DB_USER: "${PROJECT_NAME}-${NORMALIZED_BRANCH}"
  DB_PASSWORD: "dev-password"

database:
  type: postgresql
  name: ${DB_NAME}
  user: ${DB_USER}
  password: ${DB_PASSWORD}

services:
  - name: web
    type: gunicorn
    command: "gunicorn myapp.wsgi:application"
    workers: 2
    port: 8000
```

## Makefile Usage

### Deploy Commands
```bash
# Deploy main branch
make deploy REPO_URL=https://github.com/myorg/myapp.git BRANCH=main

# Deploy feature branch
make deploy REPO_URL=https://github.com/myorg/myapp.git BRANCH=feature/new-ui

# Check deployment status
make deployment-status PROJECT=myapp BRANCH=main

# View logs
make view-logs PROJECT=myapp BRANCH=feature-new-ui

# Undeploy
make undeploy PROJECT=myapp BRANCH=feature-auth
```

## Service Management

### Supervisor Service Names
Services are now named using the pattern: `{project}-{normalized_branch}-{service}`

```bash
# Check status of main branch services
sudo supervisorctl status myapp-main-web:*
sudo supervisorctl status myapp-main-worker:*

# Restart feature branch services
sudo supervisorctl restart myapp-feature-auth-web:*
sudo supervisorctl restart myapp-feature-auth-worker:*

# Check logs
sudo supervisorctl tail myapp-qa-web stderr
```

## Database Management

### Database Names
Databases use the pattern: `{project}-{normalized_branch}`

Examples:
- Main branch: `myapp-main`
- QA branch: `myapp-qa`
- Feature branch: `myapp-feature-authentication`
- Release branch: `myapp-release-v2.1.0`

### Database Users
Database users follow the same naming pattern as databases:
- Main branch: `myapp-main`
- Feature branch: `myapp-feature-authentication`

## Migration from Environment-Based Deployments

### Old vs New Comparison

| Aspect | Old (Environment-Based) | New (Branch-Only) |
|--------|-------------------------|-------------------|
| Command | `./deploy repo.git branch env` | `./deploy repo.git branch` |
| Directory | `/srv/deployments/app/dev/main/` | `/srv/deployments/app/main/` |
| Database | `app_dev` | `app-main` |
| Service | `app-dev-web` | `app-main-web` |
| Config | `deploy-dev.yml` | `deploy-main.yml` |

### Migration Steps
1. Remove `environment` field from all YAML configs
2. Update database names to use `${PROJECT_NAME}-${NORMALIZED_BRANCH}`
3. Rename config files to match branch names
4. Update any hardcoded environment references

## Best Practices

### Branch Naming
- Use descriptive branch names: `feature/user-auth`, `bugfix/login-issue`
- Avoid special characters other than `/`, `-`, `_`
- Keep branch names reasonably short for readability

### Configuration Management
- Create branch-specific configs for long-running branches
- Use template configs for temporary feature branches
- Maintain separate configs for different deployment scenarios

### Resource Management
- Monitor disk space as each branch creates separate deployments
- Clean up unused branch deployments regularly
- Use the `undeploy` command to remove old deployments

## Troubleshooting

### Common Issues

1. **Config file not found**: Ensure `deploy-{normalized-branch}.yml` exists
2. **Database connection errors**: Check database name normalization
3. **Service conflicts**: Verify port assignments in branch configs
4. **Permission issues**: Ensure proper database user permissions

### Debugging Commands
```bash
# Check deployment directory
ls -la /srv/deployments/myapp/

# Verify database exists
sudo -u postgres psql -l | grep myapp

# Check supervisor configs
ls -la /etc/supervisor/conf.d/myapp-*

# View deployment logs
tail -f /srv/deployments/myapp/main/logs/supervisor/web.log
```

This branch-only approach simplifies deployment management while providing greater flexibility for feature development and testing.
