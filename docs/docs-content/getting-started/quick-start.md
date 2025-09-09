# Quick Start Guide

Get up and running with PyDeployer in minutes. This guide covers the essential steps to deploy your first Django application.

## Prerequisites Check

Before starting, verify your system is ready:

```bash
# Check system requirements
make check-system

# Verify PyDeployer installation
make build
make venv-info
```

## 5-Minute Deployment

### Step 1: Deploy Your Application

```bash
# Replace with your repository URL
make deploy \
  REPO_URL=git@github.com:user/your-django-app.git \
  BRANCH=main
```

This single command will:
- Clone your repository
- Set up a virtual environment
- Install dependencies
- Create database and user
- Configure services
- Start your application

### Step 2: Complete Django Setup

```bash
# Set your project directory (adjust path as needed)
PROJECT_DIR=/srv/deployments/your-django-app/main/code

# Run database migrations
make run-migrations PROJECT_DIR=$PROJECT_DIR

# Collect static files
make collect-static PROJECT_DIR=$PROJECT_DIR

# Create admin user
make create-superuser PROJECT_DIR=$PROJECT_DIR
```

### Step 3: Verify Deployment

```bash
# Check deployment status
make deployment-status PROJECT=your-django-app BRANCH=main

# View application logs
make view-logs PROJECT=your-django-app BRANCH=main
```

## Your Application is Live!

Your Django application should now be running. The default configuration typically serves on:

- **Web Interface**: `http://your-server:8000`
- **Admin Interface**: `http://your-server:8000/admin`

## Common Next Steps

### Database Management

```bash
# View database permissions
make list-db-permissions DB=yourapp_dev

# Verify database connection
make verify-database PROJECT=your-django-app BRANCH=main
```

### Monitoring

```bash
# Real-time log monitoring
make view-logs PROJECT=your-django-app BRANCH=main SERVICE=web

# Check all services
make deployment-status PROJECT=your-django-app BRANCH=main
```

### Updates and Maintenance

```bash
# Redeploy with latest changes
make deploy \
  REPO_URL=git@github.com:user/your-django-app.git \
  BRANCH=main

# Run new migrations after updates
make run-migrations PROJECT_DIR=/srv/deployments/your-django-app/main/code
```

## Configuration Template

Create a deployment configuration file for your project:

```yaml
# projects/your-django-app/deploy-main.yml
name: your-django-app
repo: git@github.com:user/your-django-app.git

python_version: "3.11"

dependencies:
  system:
    - build-essential
    - libpq-dev
  python-requirements:
    - requirements.txt

database:
  type: postgresql
  name: ${DB_NAME}
  user: ${DB_USER}
  password: ${DB_PASSWORD}

env_vars:
  DJANGO_SETTINGS_MODULE: yourapp.settings
  DEBUG: "True"
  SECRET_KEY: ${DJANGO_SECRET_KEY}
  DB_NAME: "${PROJECT_NAME}_${NORMALIZED_BRANCH}"
  DB_USER: "${PROJECT_NAME}_${NORMALIZED_BRANCH}"
  DB_PASSWORD: ${YOURAPP_DB_PASSWORD}

services:
  - name: web
    command: gunicorn yourapp.wsgi:application --bind 0.0.0.0:8000
    port: 8000
    workers: 2
    
  - name: worker
    command: celery -A yourapp worker -l info
    
  - name: beat
    command: celery -A yourapp beat -l info
```

## Environment Variables

Set up your environment variables:

```bash
# Create environment file
cat > .env << EOF
YOURAPP_DB_PASSWORD=secure_password_here
DJANGO_SECRET_KEY=your_secret_key_here
EOF

# Source environment variables
source .env
```

## Multiple Branch Deployments

Deploy different branches:

```bash
# Development branch
make deploy REPO_URL=git@github.com:user/your-app.git BRANCH=develop

# Feature branch
make deploy REPO_URL=git@github.com:user/your-app.git BRANCH=feature/new-ui

# Main/Production branch
make deploy REPO_URL=git@github.com:user/your-app.git BRANCH=main
```

## Troubleshooting Quick Fixes

### Deployment Fails

```bash
# Check logs for errors
make view-logs PROJECT=your-django-app BRANCH=main

# Validate configuration
make validate CONFIG=projects/your-django-app/deploy-main.yml

# Clean and retry
make undeploy PROJECT=your-django-app BRANCH=main
make deploy REPO_URL=git@github.com:user/your-app.git BRANCH=main
```

### Database Issues

```bash
# Check database connection
make verify-database PROJECT=your-django-app BRANCH=main

# List database users and permissions
make list-db-permissions DB=yourapp_main

# Validate Django database settings
make validate-django PROJECT_DIR=/srv/deployments/your-django-app/main/code
```

### Service Issues

```bash
# Check service status
sudo supervisorctl status

# Restart specific service
sudo supervisorctl restart your-django-app-main-web

# View supervisor logs
sudo tail -f /var/log/supervisor/supervisord.log
```

## What's Next?

- **[Complete Sample App Example](../examples/sample-app.md)** - Detailed walkthrough
- **[Makefile Commands](../user-guide/makefile-commands.md)** - All available commands
- **[Configuration Guide](configuration.md)** - Advanced configuration options
- **[Production Deployment](../examples/production.md)** - Production best practices

## Getting Help

- Check the [Troubleshooting Guide](../reference/troubleshooting.md)
- Review [Common Examples](../examples/sample-app.md)
- Consult the [Script Reference](../reference/scripts.md)

---

*You're now ready to use PyDeployer for your Django deployments!*
