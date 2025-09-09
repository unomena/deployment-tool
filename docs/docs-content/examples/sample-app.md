# Sample App Deployment Guide

This comprehensive guide walks through deploying a sample Django application using PyDeployer, covering all major operations from initial deployment to ongoing management.

## Overview

We'll deploy a sample Django application called "sample-app" through multiple environments and demonstrate all PyDeployer features including:

- Initial deployment setup
- Database management
- Django operations
- Monitoring and maintenance
- Multi-environment workflows

## Prerequisites

Ensure PyDeployer is installed and configured:

```bash
# Verify installation
make check-system
make list-db-permissions
```

## Step 1: Initial Deployment

### Deploy to Development Environment

```bash
# Deploy sample-app to development
make deploy \
  REPO_URL=git@github.com:user/sample-app.git \
  BRANCH=main \
  ENV=dev
```

**What happens during deployment:**

1. Repository cloning to `/srv/deployments/sample-app/dev/main/`
2. Virtual environment creation
3. Dependency installation
4. Database creation (`sampleapp_dev`)
5. Database user creation (`sampleapp_user`)
6. Supervisor service configuration
7. Service startup

### Verify Deployment

```bash
# Check deployment status
make deployment-status PROJECT=sample-app ENV=dev BRANCH=main
```

**Expected output:**
```
✓ Deployment Status: sample-app (dev/main)
  Project Directory: /srv/deployments/sample-app/dev/main/code
  Services: web (running), worker (running), beat (running)
  Database: sampleapp_dev (connected)
  Last Updated: 2025-01-09 10:30:15
```

## Step 2: Database Operations

### Verify Database Setup

```bash
# Check database connection and permissions
make verify-database PROJECT=sample-app ENV=dev BRANCH=main
```

### List Database Permissions

```bash
# View all database permissions
make list-db-permissions

# View specific database
make list-db-permissions DB=sampleapp_dev
```

**Sample output:**
```
📁 Database: sampleapp_dev
--------------------------------------------------
  👤 User: sampleapp_user
     • CONNECT
     • CREATE
     • LOGIN
     • OWNER
     • TEMPORARY

  👤 User: postgres
     • CONNECT
     • CREATE
     • CREATEDB
     • LOGIN
     • SUPERUSER
     • TEMPORARY
```

### Run Database Migrations

```bash
# Run Django migrations
make run-migrations PROJECT_DIR=/srv/deployments/sample-app/dev/main/code
```

**Expected output:**
```
Running Django migrations...
Operations to perform:
  Apply all migrations: admin, auth, contenttypes, sessions, myapp
Running migrations:
  Applying contenttypes.0001_initial... OK
  Applying auth.0001_initial... OK
  Applying admin.0001_initial... OK
  ...
✓ Migrations completed successfully
```

## Step 3: Django Management

### Create Superuser

**Interactive method:**
```bash
make create-superuser PROJECT_DIR=/srv/deployments/sample-app/dev/main/code
```

**Automated method:**
```bash
make create-superuser \
  PROJECT_DIR=/srv/deployments/sample-app/dev/main/code \
  USERNAME=admin \
  EMAIL=admin@sampleapp.com \
  PASSWORD=admin123
```

### Collect Static Files

```bash
make collect-static PROJECT_DIR=/srv/deployments/sample-app/dev/main/code
```

### Validate Django Environment

```bash
make validate-django PROJECT_DIR=/srv/deployments/sample-app/dev/main/code
```

**Expected output:**
```
✓ Django settings module loaded successfully
✓ Database connection test passed
✓ Django management commands accessible
✓ Static files configuration valid
✓ Django environment validation complete
```

## Step 4: Monitoring and Logs

### View Application Logs

```bash
# View all service logs
make view-logs PROJECT=sample-app ENV=dev BRANCH=main

# View specific service logs
make view-logs PROJECT=sample-app ENV=dev BRANCH=main SERVICE=web
make view-logs PROJECT=sample-app ENV=dev BRANCH=main SERVICE=worker
make view-logs PROJECT=sample-app ENV=dev BRANCH=main SERVICE=beat
```

### Monitor Deployment Status

```bash
# Continuous status monitoring
watch -n 5 "make deployment-status PROJECT=sample-app ENV=dev BRANCH=main"
```

## Step 5: Multi-Environment Deployment

### Deploy to Staging

```bash
# Deploy to staging environment
make deploy \
  REPO_URL=git@github.com:user/sample-app.git \
  BRANCH=main \
  ENV=stage

# Verify staging deployment
make deployment-status PROJECT=sample-app ENV=stage BRANCH=main

# Check staging database
make list-db-permissions DB=sampleapp_stage
```

### Deploy Feature Branch

```bash
# Deploy feature branch
make deploy \
  REPO_URL=git@github.com:user/sample-app.git \
  BRANCH=feature/new-dashboard \
  ENV=branch

# Check branch deployment
make deployment-status PROJECT=sample-app ENV=branch BRANCH=feature/new-dashboard
```

### Production Deployment

```bash
# Deploy to production (requires production config)
make deploy \
  REPO_URL=git@github.com:user/sample-app.git \
  BRANCH=main \
  ENV=prod

# Production-specific operations
make run-migrations PROJECT_DIR=/srv/deployments/sample-app/prod/main/code
make collect-static PROJECT_DIR=/srv/deployments/sample-app/prod/main/code
make create-superuser PROJECT_DIR=/srv/deployments/sample-app/prod/main/code
```

## Step 6: Maintenance Operations

### Update Deployment

```bash
# Redeploy with latest changes
make deploy \
  REPO_URL=git@github.com:user/sample-app.git \
  BRANCH=main \
  ENV=dev

# Run any new migrations
make run-migrations PROJECT_DIR=/srv/deployments/sample-app/dev/main/code
```

### Clean Up Old Deployments

```bash
# Clean deployments older than 30 days (default)
make cleanup-deployments

# Clean deployments older than 7 days
make cleanup-deployments DAYS_OLD=7
```

### Remove Deployment

```bash
# Remove feature branch deployment
make undeploy PROJECT=sample-app ENV=branch BRANCH=feature/new-dashboard

# Remove development deployment
make undeploy PROJECT=sample-app ENV=dev BRANCH=main
```

## Complete Workflow Example

Here's a complete workflow from deployment to production:

```bash
#!/bin/bash
# Complete sample-app deployment workflow

# 1. Deploy to development
echo "=== Deploying to Development ==="
make deploy REPO_URL=git@github.com:user/sample-app.git BRANCH=main ENV=dev

# 2. Set up database
echo "=== Setting up Database ==="
make verify-database PROJECT=sample-app ENV=dev BRANCH=main
make run-migrations PROJECT_DIR=/srv/deployments/sample-app/dev/main/code

# 3. Configure Django
echo "=== Configuring Django ==="
make collect-static PROJECT_DIR=/srv/deployments/sample-app/dev/main/code
make create-superuser \
  PROJECT_DIR=/srv/deployments/sample-app/dev/main/code \
  USERNAME=admin \
  EMAIL=admin@sampleapp.com \
  PASSWORD=dev_password_123

# 4. Validate deployment
echo "=== Validating Deployment ==="
make validate-django PROJECT_DIR=/srv/deployments/sample-app/dev/main/code
make deployment-status PROJECT=sample-app ENV=dev BRANCH=main

# 5. Deploy to staging
echo "=== Deploying to Staging ==="
make deploy REPO_URL=git@github.com:user/sample-app.git BRANCH=main ENV=stage
make run-migrations PROJECT_DIR=/srv/deployments/sample-app/stage/main/code
make collect-static PROJECT_DIR=/srv/deployments/sample-app/stage/main/code

# 6. Deploy to production
echo "=== Deploying to Production ==="
make deploy REPO_URL=git@github.com:user/sample-app.git BRANCH=main ENV=prod
make run-migrations PROJECT_DIR=/srv/deployments/sample-app/prod/main/code
make collect-static PROJECT_DIR=/srv/deployments/sample-app/prod/main/code
make create-superuser PROJECT_DIR=/srv/deployments/sample-app/prod/main/code

# 7. Final verification
echo "=== Final Verification ==="
make deployment-status PROJECT=sample-app ENV=dev BRANCH=main
make deployment-status PROJECT=sample-app ENV=stage BRANCH=main
make deployment-status PROJECT=sample-app ENV=prod BRANCH=main

echo "=== Deployment Complete ==="
```

## Directory Structure

After deployment, your directory structure will look like:

```
/srv/deployments/sample-app/
├── dev/
│   └── main/
│       ├── code/          # Django application code
│       ├── venv/          # Python virtual environment
│       ├── config/        # Supervisor configurations
│       └── logs/          # Application logs
├── stage/
│   └── main/
│       ├── code/
│       ├── venv/
│       ├── config/
│       └── logs/
└── prod/
    └── main/
        ├── code/
        ├── venv/
        ├── config/
        └── logs/
```

## Configuration Files

### Development Configuration (`deploy-dev.yml`)

```yaml
name: sample-app
repo: git@github.com:user/sample-app.git
branch: main
environment: dev

database:
  name: sampleapp_dev
  user: sampleapp_user
  password: dev_password_123

env_vars:
  DJANGO_SETTINGS_MODULE: sampleapp.settings.dev
  DEBUG: "True"
  DATABASE_URL: postgresql://sampleapp_user:dev_password_123@localhost/sampleapp_dev

services:
  - name: web
    command: gunicorn sampleapp.wsgi:application
    port: 8000
    workers: 2
  - name: worker
    command: celery -A sampleapp worker -l info
  - name: beat
    command: celery -A sampleapp beat -l info
```

## Troubleshooting Common Issues

### Database Connection Issues

```bash
# Check database permissions
make list-db-permissions DB=sampleapp_dev

# Verify database setup
make verify-database PROJECT=sample-app ENV=dev BRANCH=main

# Test manual connection
psql -U sampleapp_user -d sampleapp_dev -h localhost
```

### Service Issues

```bash
# Check service status
make deployment-status PROJECT=sample-app ENV=dev BRANCH=main

# View service logs
make view-logs PROJECT=sample-app ENV=dev BRANCH=main SERVICE=web

# Restart services (manual)
sudo supervisorctl restart sample-app-dev-web
sudo supervisorctl restart sample-app-dev-worker
```

### Django Issues

```bash
# Validate Django environment
make validate-django PROJECT_DIR=/srv/deployments/sample-app/dev/main/code

# Check Django settings
cd /srv/deployments/sample-app/dev/main/code
source ../venv/bin/activate
python manage.py check
```

## Next Steps

- **[Production Deployment](production.md)** - Production-specific considerations
- **[Multi-Environment Setup](multi-environment.md)** - Advanced environment management
- **[Monitoring & Logs](../user-guide/monitoring-logs.md)** - Comprehensive monitoring guide
- **[Troubleshooting](../reference/troubleshooting.md)** - Common issues and solutions
