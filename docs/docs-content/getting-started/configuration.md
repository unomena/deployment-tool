# Configuration Guide

PyDeployer uses YAML configuration files to define deployment settings for each project and environment. This guide covers all configuration options and best practices.

## Configuration File Structure

Configuration files follow the naming pattern: `deploy-{environment}.yml`

```
projects/
└── your-project/
    ├── deploy-dev.yml      # Development environment
    ├── deploy-stage.yml    # Staging environment
    ├── deploy-prod.yml     # Production environment
    └── deploy-qa.yml       # QA environment
```

## Basic Configuration

### Minimal Configuration

```yaml
# deploy-dev.yml
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

services:
  - name: web
    command: gunicorn sampleapp.wsgi:application
    port: 8000
```

### Complete Configuration

```yaml
# deploy-prod.yml
name: sample-app
repo: git@github.com:user/sample-app.git
branch: main
environment: prod

# Python version (optional, defaults to system python3)
python_version: "3.11"

# System packages to install
system_dependencies:
  - build-essential
  - libpq-dev
  - redis-server
  - nginx

# Python packages (in addition to requirements.txt)
python_dependencies:
  - gunicorn==21.2.0
  - psycopg2-binary==2.9.7

# Database configuration
database:
  name: sampleapp_prod
  user: sampleapp_user
  password: ${SAMPLEAPP_DB_PASSWORD}
  host: localhost
  port: 5432

# Environment variables passed to the application
env_vars:
  DJANGO_SETTINGS_MODULE: sampleapp.settings.prod
  DEBUG: "False"
  SECRET_KEY: ${DJANGO_SECRET_KEY}
  DATABASE_URL: postgresql://sampleapp_user:${SAMPLEAPP_DB_PASSWORD}@localhost/sampleapp_prod
  REDIS_URL: redis://localhost:6379/0
  CELERY_BROKER_URL: redis://localhost:6379/0
  ALLOWED_HOSTS: example.com,www.example.com

# Service definitions
services:
  - name: web
    command: gunicorn sampleapp.wsgi:application --bind 0.0.0.0:8000 --workers 4
    port: 8000
    workers: 4
    user: www-data
    
  - name: worker
    command: celery -A sampleapp worker -l info --concurrency=2
    user: www-data
    
  - name: beat
    command: celery -A sampleapp beat -l info
    user: www-data

# Pre-deployment hooks
pre_deploy_hooks:
  - echo "Starting deployment..."
  - python manage.py check --deploy

# Post-deployment hooks  
post_deploy_hooks:
  - python manage.py migrate
  - python manage.py collectstatic --noinput
  - echo "Deployment complete!"

# Health check configuration
health_check:
  url: http://localhost:8000/health/
  timeout: 30
  retries: 3
```

## Configuration Sections

### Project Information

```yaml
name: sample-app              # Project identifier (required)
repo: git@github.com:user/sample-app.git  # Git repository (required)
branch: main                  # Git branch (required)
environment: prod             # Environment name (required)
python_version: "3.11"       # Python version (optional)
```

### Dependencies

```yaml
system_dependencies:          # Ubuntu packages to install
  - build-essential
  - libpq-dev
  - redis-server
  - nginx
  - nodejs
  - npm

python_dependencies:          # Additional Python packages
  - gunicorn==21.2.0
  - redis==4.6.0
  - celery[redis]==5.3.1
```

### Database Configuration

```yaml
database:
  name: myapp_prod           # Database name
  user: myapp_user           # Database user
  password: ${DB_PASSWORD}   # Database password (use env vars)
  host: localhost            # Database host (optional, default: localhost)
  port: 5432                # Database port (optional, default: 5432)
```

### Environment Variables

```yaml
env_vars:
  # Django settings
  DJANGO_SETTINGS_MODULE: myapp.settings.prod
  DEBUG: "False"
  SECRET_KEY: ${DJANGO_SECRET_KEY}
  
  # Database
  DATABASE_URL: postgresql://myapp_user:${DB_PASSWORD}@localhost/myapp_prod
  
  # Cache and Queue
  REDIS_URL: redis://localhost:6379/0
  CELERY_BROKER_URL: redis://localhost:6379/0
  
  # Security
  ALLOWED_HOSTS: example.com,www.example.com
  SECURE_SSL_REDIRECT: "True"
  
  # External services
  EMAIL_HOST: smtp.example.com
  EMAIL_PORT: "587"
  EMAIL_HOST_USER: ${EMAIL_USER}
  EMAIL_HOST_PASSWORD: ${EMAIL_PASSWORD}
```

### Service Configuration

```yaml
services:
  - name: web                 # Service name (required)
    command: gunicorn myapp.wsgi:application --bind 0.0.0.0:8000
    port: 8000               # Port number (required for web services)
    workers: 4               # Number of worker processes
    user: www-data           # User to run service as (optional)
    autostart: true          # Start automatically (optional, default: true)
    autorestart: true        # Restart on failure (optional, default: true)
    
  - name: worker
    command: celery -A myapp worker -l info --concurrency=2
    user: www-data
    
  - name: beat
    command: celery -A myapp beat -l info
    user: www-data
    
  - name: flower              # Celery monitoring (optional)
    command: celery -A myapp flower --port=5555
    port: 5555
    user: www-data
```

### Hooks

```yaml
pre_deploy_hooks:            # Run before deployment
  - echo "Pre-deployment checks..."
  - python manage.py check --deploy
  - python manage.py test --keepdb
  
post_deploy_hooks:           # Run after deployment
  - python manage.py migrate
  - python manage.py collectstatic --noinput
  - python manage.py compress
  - echo "Deployment complete!"
```

### Health Checks

```yaml
health_check:
  url: http://localhost:8000/health/     # Health check endpoint
  timeout: 30                           # Timeout in seconds
  retries: 3                           # Number of retries
  interval: 60                         # Check interval in seconds
```

## Environment-Specific Configurations

### Development Environment

```yaml
# deploy-dev.yml
name: sample-app
repo: git@github.com:user/sample-app.git
branch: develop
environment: dev

database:
  name: sampleapp_dev
  user: sampleapp_user
  password: dev_password_123

env_vars:
  DJANGO_SETTINGS_MODULE: sampleapp.settings.dev
  DEBUG: "True"
  SECRET_KEY: dev-secret-key-not-secure

services:
  - name: web
    command: python manage.py runserver 0.0.0.0:8000
    port: 8000
```

### Staging Environment

```yaml
# deploy-stage.yml
name: sample-app
repo: git@github.com:user/sample-app.git
branch: main
environment: stage

database:
  name: sampleapp_stage
  user: sampleapp_user
  password: ${STAGE_DB_PASSWORD}

env_vars:
  DJANGO_SETTINGS_MODULE: sampleapp.settings.staging
  DEBUG: "False"
  SECRET_KEY: ${DJANGO_SECRET_KEY}

services:
  - name: web
    command: gunicorn sampleapp.wsgi:application --bind 0.0.0.0:8001
    port: 8001
    workers: 2
```

### Production Environment

```yaml
# deploy-prod.yml
name: sample-app
repo: git@github.com:user/sample-app.git
branch: main
environment: prod

system_dependencies:
  - nginx
  - redis-server

database:
  name: sampleapp_prod
  user: sampleapp_user
  password: ${PROD_DB_PASSWORD}

env_vars:
  DJANGO_SETTINGS_MODULE: sampleapp.settings.prod
  DEBUG: "False"
  SECRET_KEY: ${DJANGO_SECRET_KEY}
  ALLOWED_HOSTS: myapp.com,www.myapp.com

services:
  - name: web
    command: gunicorn sampleapp.wsgi:application --bind 0.0.0.0:8000 --workers 4
    port: 8000
    workers: 4
    user: www-data
    
  - name: worker
    command: celery -A sampleapp worker -l info --concurrency=4
    user: www-data
    
  - name: beat
    command: celery -A sampleapp beat -l info
    user: www-data

post_deploy_hooks:
  - python manage.py migrate
  - python manage.py collectstatic --noinput
  - sudo systemctl reload nginx
```

## Environment Variables and Secrets

### Using Environment Variables

Reference environment variables in configuration:

```yaml
database:
  password: ${DB_PASSWORD}    # Required variable
  host: ${DB_HOST:-localhost} # Optional with default

env_vars:
  SECRET_KEY: ${DJANGO_SECRET_KEY}
  EMAIL_PASSWORD: ${EMAIL_PASSWORD}
```

### Setting Environment Variables

```bash
# Set in shell
export DB_PASSWORD=secure_password_here
export DJANGO_SECRET_KEY=your_secret_key

# Or use .env file
cat > .env << EOF
DB_PASSWORD=secure_password_here
DJANGO_SECRET_KEY=your_secret_key
EMAIL_PASSWORD=email_password
EOF

# Source before deployment
source .env
make deploy REPO_URL=... BRANCH=main ENV=prod
```

## Advanced Configuration Options

### Custom Django Manage Module

For projects with `manage.py` in non-standard locations:

```yaml
env_vars:
  DJANGO_MANAGE_MODULE: /src/myapp/manage.py
```

### Multiple Requirements Files

```yaml
python_dependencies:
  - -r requirements/base.txt
  - -r requirements/prod.txt
```

### Custom Service Configuration

```yaml
services:
  - name: web
    command: gunicorn myapp.wsgi:application
    port: 8000
    workers: 4
    # Supervisor-specific options
    autostart: true
    autorestart: true
    redirect_stderr: true
    stdout_logfile: /srv/deployments/myapp/prod/main/logs/web.log
    stderr_logfile: /srv/deployments/myapp/prod/main/logs/web_error.log
```

## Configuration Validation

### Validate Configuration

```bash
# Validate specific configuration
make validate CONFIG=projects/sample-app/deploy-prod.yml

# Check YAML syntax
python -c "import yaml; yaml.safe_load(open('deploy-prod.yml'))"
```

### Common Validation Errors

**Missing Required Fields:**
```yaml
# ❌ Missing required fields
name: sample-app
# Missing: repo, branch, environment

# ✅ Correct
name: sample-app
repo: git@github.com:user/sample-app.git
branch: main
environment: prod
```

**Invalid Service Configuration:**
```yaml
# ❌ Web service without port
services:
  - name: web
    command: gunicorn app.wsgi:application
    # Missing: port

# ✅ Correct
services:
  - name: web
    command: gunicorn app.wsgi:application
    port: 8000
```

## Best Practices

### Security

1. **Never commit secrets** to version control
2. **Use environment variables** for sensitive data
3. **Set appropriate file permissions** on configuration files
4. **Use strong passwords** for database users

### Organization

1. **Use consistent naming** across environments
2. **Document environment variables** in README
3. **Version control configurations** (without secrets)
4. **Test configurations** in development first

### Performance

1. **Optimize worker counts** based on server resources
2. **Use appropriate timeouts** for health checks
3. **Configure logging levels** appropriately
4. **Monitor resource usage** after deployment

## Configuration Examples by Project Type

### Simple Django App

```yaml
name: blog-app
repo: git@github.com:user/blog-app.git
branch: main
environment: prod

database:
  name: blog_prod
  user: blog_user
  password: ${BLOG_DB_PASSWORD}

env_vars:
  DJANGO_SETTINGS_MODULE: blog.settings.prod
  SECRET_KEY: ${DJANGO_SECRET_KEY}

services:
  - name: web
    command: gunicorn blog.wsgi:application
    port: 8000
```

### Django + Celery + Redis

```yaml
name: ecommerce-app
repo: git@github.com:user/ecommerce-app.git
branch: main
environment: prod

system_dependencies:
  - redis-server

database:
  name: ecommerce_prod
  user: ecommerce_user
  password: ${ECOMMERCE_DB_PASSWORD}

env_vars:
  DJANGO_SETTINGS_MODULE: ecommerce.settings.prod
  CELERY_BROKER_URL: redis://localhost:6379/0
  CELERY_RESULT_BACKEND: redis://localhost:6379/0

services:
  - name: web
    command: gunicorn ecommerce.wsgi:application
    port: 8000
    workers: 4
    
  - name: worker
    command: celery -A ecommerce worker -l info
    
  - name: beat
    command: celery -A ecommerce beat -l info
```

For more examples, see the [Sample App Guide](../examples/sample-app.md) and [Production Deployment](../examples/production.md).
