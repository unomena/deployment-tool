# Deployment Basics

This guide covers the fundamental concepts and workflows for deploying Django applications with PyDeployer.

## Core Concepts

### Project Structure

PyDeployer organizes deployments using a hierarchical structure:

```
/srv/deployments/{project}/{environment}/{branch}/
├── code/           # Cloned repository
├── venv/           # Python virtual environment
├── config/         # Generated configurations (supervisor, nginx)
└── logs/           # Application and service logs
```

**Example paths:**
- `/srv/deployments/sample-app/dev/main/code/`
- `/srv/deployments/sample-app/prod/main/code/`
- `/srv/deployments/sample-app/branch/feature-auth/code/`

### Environment Types

| Environment | Purpose | Branch | Database Suffix |
|-------------|---------|--------|-----------------|
| `dev` | Development | develop/main | `_dev` |
| `stage` | Staging | main | `_stage` |
| `qa` | Quality Assurance | main | `_qa` |
| `prod` | Production | main | `_prod` |
| `branch` | Feature branches | any | `_branch` |

### Configuration Files

Each project requires environment-specific configuration files:

```
projects/your-project/
├── deploy-dev.yml
├── deploy-stage.yml
├── deploy-qa.yml
└── deploy-prod.yml
```

## Basic Deployment Workflow

### 1. Initial Deployment

```bash
# Deploy to development environment
make deploy \
  REPO_URL=git@github.com:user/your-app.git \
  BRANCH=main \
  ENV=dev
```

**What happens during deployment:**

1. **Repository Cloning**: Code is cloned to deployment directory
2. **Environment Setup**: Python virtual environment is created
3. **Dependencies**: System and Python packages are installed
4. **Database Setup**: PostgreSQL database and user are created
5. **Configuration**: Supervisor services are configured
6. **Service Startup**: Application services are started

### 2. Database Operations

```bash
# Run database migrations
make run-migrations PROJECT_DIR=/srv/deployments/your-app/dev/main/code

# Create superuser
make create-superuser PROJECT_DIR=/srv/deployments/your-app/dev/main/code

# Collect static files
make collect-static PROJECT_DIR=/srv/deployments/your-app/dev/main/code
```

### 3. Verification

```bash
# Check deployment status
make deployment-status PROJECT=your-app ENV=dev BRANCH=main

# Validate Django environment
make validate-django PROJECT_DIR=/srv/deployments/your-app/dev/main/code

# View application logs
make view-logs PROJECT=your-app ENV=dev BRANCH=main
```

## Service Management

### Service Types

PyDeployer manages several types of services:

**Web Services:**
```yaml
services:
  - name: web
    command: gunicorn myapp.wsgi:application
    port: 8000
    workers: 4
```

**Background Workers:**
```yaml
  - name: worker
    command: celery -A myapp worker -l info
```

**Scheduled Tasks:**
```yaml
  - name: beat
    command: celery -A myapp beat -l info
```

### Service Naming Convention

Services are named using the pattern: `{project}-{environment}-{service}`

Examples:
- `sample-app-dev-web`
- `sample-app-prod-worker`
- `sample-app-stage-beat`

### Managing Services

```bash
# View all services
sudo supervisorctl status

# Restart specific service
sudo supervisorctl restart sample-app-dev-web

# Stop service
sudo supervisorctl stop sample-app-dev-worker

# Start service
sudo supervisorctl start sample-app-dev-beat
```

## Database Management

### Database Naming

Databases follow the pattern: `{project}_{environment}`

Examples:
- `sampleapp_dev`
- `sampleapp_prod`
- `sampleapp_stage`

### Database Users

Each deployment gets its own database user:
- Username: `{project}_user`
- Database: `{project}_{environment}`
- Permissions: Full access to assigned database

### Database Operations

```bash
# List all database permissions
make list-db-permissions

# Check specific database
make list-db-permissions DB=sampleapp_dev

# Verify database connection
make verify-database PROJECT=sample-app ENV=dev BRANCH=main
```

## Environment Variables

### Configuration

Environment variables are defined in deployment configuration files:

```yaml
env_vars:
  DJANGO_SETTINGS_MODULE: myapp.settings.dev
  DEBUG: "True"
  SECRET_KEY: ${DJANGO_SECRET_KEY}
  DATABASE_URL: postgresql://user:pass@localhost/db
```

### Security Best Practices

1. **Use environment variables** for sensitive data
2. **Never commit secrets** to version control
3. **Reference variables** using `${VARIABLE_NAME}` syntax
4. **Set variables** before deployment:

```bash
export DJANGO_SECRET_KEY=your_secret_key
export DB_PASSWORD=secure_password
make deploy REPO_URL=... BRANCH=main ENV=prod
```

## Multi-Environment Deployments

### Development → Staging → Production

```bash
# 1. Deploy to development
make deploy REPO_URL=git@github.com:user/app.git BRANCH=develop ENV=dev

# 2. Test and validate in development
make validate-django PROJECT_DIR=/srv/deployments/app/dev/develop/code
make deployment-status PROJECT=app ENV=dev BRANCH=develop

# 3. Deploy to staging
make deploy REPO_URL=git@github.com:user/app.git BRANCH=main ENV=stage

# 4. Deploy to production
make deploy REPO_URL=git@github.com:user/app.git BRANCH=main ENV=prod
```

### Feature Branch Deployment

```bash
# Deploy feature branch for testing
make deploy \
  REPO_URL=git@github.com:user/app.git \
  BRANCH=feature/new-authentication \
  ENV=branch

# Test feature branch
make deployment-status PROJECT=app ENV=branch BRANCH=feature/new-authentication

# Remove when done
make undeploy PROJECT=app ENV=branch BRANCH=feature/new-authentication
```

## Port Management

### Automatic Port Assignment

PyDeployer automatically assigns ports to avoid conflicts:

- **Development**: 8000, 8001, 8002...
- **Staging**: 8100, 8101, 8102...
- **Production**: 8200, 8201, 8202...
- **Branch**: 9000, 9001, 9002...

### Manual Port Configuration

```yaml
services:
  - name: web
    command: gunicorn myapp.wsgi:application --bind 0.0.0.0:8000
    port: 8000  # Explicitly set port
```

## Logging and Monitoring

### Log Locations

```
/srv/deployments/{project}/{env}/{branch}/logs/
├── web.log              # Web service logs
├── worker.log           # Celery worker logs
├── beat.log             # Celery beat logs
└── deployment.log       # Deployment logs
```

### Viewing Logs

```bash
# View all service logs
make view-logs PROJECT=sample-app ENV=dev BRANCH=main

# View specific service
make view-logs PROJECT=sample-app ENV=dev BRANCH=main SERVICE=web

# Real-time log monitoring
tail -f /srv/deployments/sample-app/dev/main/logs/web.log
```

## Updates and Maintenance

### Updating Deployments

```bash
# Redeploy with latest changes
make deploy REPO_URL=git@github.com:user/app.git BRANCH=main ENV=dev

# Run new migrations
make run-migrations PROJECT_DIR=/srv/deployments/app/dev/main/code

# Collect updated static files
make collect-static PROJECT_DIR=/srv/deployments/app/dev/main/code
```

### Cleanup

```bash
# Remove old deployments (30+ days old)
make cleanup-deployments

# Remove specific deployment
make undeploy PROJECT=sample-app ENV=dev BRANCH=main
```

## Troubleshooting Common Issues

### Deployment Failures

1. **Check deployment logs:**
   ```bash
   make view-logs PROJECT=your-app ENV=dev BRANCH=main
   ```

2. **Validate configuration:**
   ```bash
   make validate CONFIG=projects/your-app/deploy-dev.yml
   ```

3. **Check system requirements:**
   ```bash
   make check-system
   ```

### Service Issues

1. **Check service status:**
   ```bash
   sudo supervisorctl status
   make deployment-status PROJECT=your-app ENV=dev BRANCH=main
   ```

2. **Restart services:**
   ```bash
   sudo supervisorctl restart your-app-dev-web
   ```

3. **Check supervisor logs:**
   ```bash
   sudo tail -f /var/log/supervisor/supervisord.log
   ```

### Database Issues

1. **Verify database connection:**
   ```bash
   make verify-database PROJECT=your-app ENV=dev BRANCH=main
   ```

2. **Check database permissions:**
   ```bash
   make list-db-permissions DB=yourapp_dev
   ```

3. **Test manual connection:**
   ```bash
   psql -U yourapp_user -d yourapp_dev -h localhost
   ```

## Best Practices

### Development Workflow

1. **Start with development environment**
2. **Test thoroughly before promoting**
3. **Use feature branches for new features**
4. **Run migrations after code updates**
5. **Monitor logs after deployments**

### Security

1. **Use environment variables for secrets**
2. **Restrict database user permissions**
3. **Keep dependencies updated**
4. **Use HTTPS in production**
5. **Regular security audits**

### Performance

1. **Optimize worker counts for your server**
2. **Monitor resource usage**
3. **Use appropriate caching strategies**
4. **Regular database maintenance**
5. **Log rotation and cleanup**

## Next Steps

- **[Makefile Commands](makefile-commands.md)** - Complete command reference
- **[Database Management](database-management.md)** - Advanced database operations
- **[Django Operations](django-operations.md)** - Django-specific tasks
- **[Monitoring & Logs](monitoring-logs.md)** - Comprehensive monitoring guide
