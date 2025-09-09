# Makefile Commands Reference

PyDeployer provides a comprehensive set of Makefile commands for managing deployments, databases, and Django operations. This guide covers all available commands with practical examples using the sample-app project.

## Core Deployment Commands

### `make deploy`
Deploy an application using the simplified interface.

**Syntax:**
```bash
make deploy REPO_URL=<repository-url> BRANCH=<branch> ENV=<environment>
```

**Parameters:**
- `REPO_URL`: Git repository URL (required)
- `BRANCH`: Git branch to deploy (required)
- `ENV`: Target environment - prod, stage, qa, dev, or branch (required)

**Examples:**
```bash
# Deploy sample-app to development
make deploy REPO_URL=git@github.com:user/sample-app.git BRANCH=main ENV=dev

# Deploy to production
make deploy REPO_URL=git@github.com:user/sample-app.git BRANCH=main ENV=prod

# Deploy feature branch
make deploy REPO_URL=git@github.com:user/sample-app.git BRANCH=feature/new-ui ENV=branch
```

### `make undeploy`
Remove a deployment completely.

**Syntax:**
```bash
make undeploy PROJECT=<project-name> ENV=<environment> BRANCH=<branch>
```

**Examples:**
```bash
# Remove sample-app development deployment
make undeploy PROJECT=sample-app ENV=dev BRANCH=main

# Remove feature branch deployment
make undeploy PROJECT=sample-app ENV=branch BRANCH=feature/new-ui
```

## Database Management Commands

### `make list-db-permissions`
List PostgreSQL databases and their user permissions.

**Syntax:**
```bash
make list-db-permissions [DB=<database-name>]
```

**Examples:**
```bash
# List all databases and users
make list-db-permissions

# List permissions for specific database
make list-db-permissions DB=sampleapp_dev
```

**Sample Output:**
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

### `make verify-database`
Verify PostgreSQL database connection and setup.

**Syntax:**
```bash
make verify-database PROJECT=<project> ENV=<environment> BRANCH=<branch>
```

**Examples:**
```bash
# Verify sample-app database setup
make verify-database PROJECT=sample-app ENV=dev BRANCH=main

# Verify production database
make verify-database PROJECT=sample-app ENV=prod BRANCH=main
```

## Django Management Commands

### `make create-superuser`
Create a Django superuser for the application.

**Syntax:**
```bash
make create-superuser PROJECT_DIR=<path> [USERNAME=<user>] [EMAIL=<email>] [PASSWORD=<pass>]
```

**Examples:**
```bash
# Interactive superuser creation
make create-superuser PROJECT_DIR=/srv/deployments/sample-app/dev/main/code

# Automated superuser creation
make create-superuser \
  PROJECT_DIR=/srv/deployments/sample-app/dev/main/code \
  USERNAME=admin \
  EMAIL=admin@example.com \
  PASSWORD=secure_password_123
```

### `make run-migrations`
Run Django database migrations.

**Syntax:**
```bash
make run-migrations PROJECT_DIR=<path-to-project>
```

**Examples:**
```bash
# Run migrations for sample-app
make run-migrations PROJECT_DIR=/srv/deployments/sample-app/dev/main/code

# Run migrations for production
make run-migrations PROJECT_DIR=/srv/deployments/sample-app/prod/main/code
```

### `make collect-static`
Collect Django static files.

**Syntax:**
```bash
make collect-static PROJECT_DIR=<path-to-project>
```

**Examples:**
```bash
# Collect static files for sample-app
make collect-static PROJECT_DIR=/srv/deployments/sample-app/dev/main/code
```

### `make validate-django`
Validate Django environment and configuration.

**Syntax:**
```bash
make validate-django PROJECT_DIR=<path-to-project>
```

**Examples:**
```bash
# Validate sample-app Django setup
make validate-django PROJECT_DIR=/srv/deployments/sample-app/dev/main/code
```

## Monitoring and Logs Commands

### `make deployment-status`
Check the status of a deployment.

**Syntax:**
```bash
make deployment-status PROJECT=<project> ENV=<environment> BRANCH=<branch>
```

**Examples:**
```bash
# Check sample-app status
make deployment-status PROJECT=sample-app ENV=dev BRANCH=main

# Check production status
make deployment-status PROJECT=sample-app ENV=prod BRANCH=main
```

### `make view-logs`
View deployment and application logs.

**Syntax:**
```bash
make view-logs PROJECT=<project> ENV=<environment> BRANCH=<branch> [SERVICE=<service>]
```

**Examples:**
```bash
# View all logs for sample-app
make view-logs PROJECT=sample-app ENV=dev BRANCH=main

# View specific service logs
make view-logs PROJECT=sample-app ENV=dev BRANCH=main SERVICE=web

# View Celery worker logs
make view-logs PROJECT=sample-app ENV=dev BRANCH=main SERVICE=worker
```

### `make cleanup-deployments`
Clean up old deployments to free disk space.

**Syntax:**
```bash
make cleanup-deployments [DAYS_OLD=<number>]
```

**Examples:**
```bash
# Clean deployments older than default (30 days)
make cleanup-deployments

# Clean deployments older than 7 days
make cleanup-deployments DAYS_OLD=7
```

## Development and Maintenance Commands

### `make build`
Set up the PyDeployer development environment.

**Examples:**
```bash
# Initial setup
make build

# Verify setup
make venv-info
```

### `make validate`
Validate deployment configuration files.

**Syntax:**
```bash
make validate [CONFIG=<config-file>]
```

**Examples:**
```bash
# Validate default configuration
make validate

# Validate specific config
make validate CONFIG=projects/sample-app/deploy-prod.yml
```

### `make check-system`
Check system requirements for deployment.

**Examples:**
```bash
# Verify system prerequisites
make check-system
```

## Documentation Commands

### `make docs`
Build and serve documentation locally.

**Examples:**
```bash
# Start documentation server
make docs

# Documentation will be available at http://127.0.0.1:8000
```

### `make docs-build`
Build static documentation only.

**Examples:**
```bash
# Build documentation to site/ directory
make docs-build
```

## Complete Sample-App Workflow

Here's a complete workflow for deploying and managing the sample-app:

```bash
# 1. Initial deployment
make deploy REPO_URL=git@github.com:user/sample-app.git BRANCH=main ENV=dev

# 2. Verify database setup
make verify-database PROJECT=sample-app ENV=dev BRANCH=main

# 3. Run migrations
make run-migrations PROJECT_DIR=/srv/deployments/sample-app/dev/main/code

# 4. Collect static files
make collect-static PROJECT_DIR=/srv/deployments/sample-app/dev/main/code

# 5. Create superuser
make create-superuser \
  PROJECT_DIR=/srv/deployments/sample-app/dev/main/code \
  USERNAME=admin \
  EMAIL=admin@sampleapp.com \
  PASSWORD=admin123

# 6. Check deployment status
make deployment-status PROJECT=sample-app ENV=dev BRANCH=main

# 7. View logs
make view-logs PROJECT=sample-app ENV=dev BRANCH=main

# 8. Check database permissions
make list-db-permissions DB=sampleapp_dev

# 9. Validate Django environment
make validate-django PROJECT_DIR=/srv/deployments/sample-app/dev/main/code
```

## Environment Variables Reference

Common environment variables used across commands:

| Variable | Description | Example |
|----------|-------------|---------|
| `REPO_URL` | Git repository URL | `git@github.com:user/sample-app.git` |
| `BRANCH` | Git branch name | `main`, `develop`, `feature/new-ui` |
| `ENV` | Target environment | `dev`, `stage`, `prod`, `qa`, `branch` |
| `PROJECT` | Project name | `sample-app` |
| `PROJECT_DIR` | Full path to project code | `/srv/deployments/sample-app/dev/main/code` |
| `DB` | Database name | `sampleapp_dev` |
| `SERVICE` | Service name for logs | `web`, `worker`, `beat` |
| `USERNAME` | Django superuser name | `admin` |
| `EMAIL` | Django superuser email | `admin@example.com` |
| `PASSWORD` | Django superuser password | `secure_password` |

## Tips and Best Practices

### Path Construction
Project directories follow this pattern:
```
/srv/deployments/{project}/{environment}/{branch}/code/
```

Examples:
- `/srv/deployments/sample-app/dev/main/code/`
- `/srv/deployments/sample-app/prod/main/code/`
- `/srv/deployments/sample-app/branch/feature-new-ui/code/`

### Environment Naming
- `dev` - Development environment
- `stage` - Staging environment  
- `prod` - Production environment
- `qa` - Quality assurance environment
- `branch` - Feature branch deployments

### Service Names
Common service names for log viewing:
- `web` - Django web application
- `worker` - Celery worker processes
- `beat` - Celery beat scheduler
- `flower` - Celery monitoring (if configured)

For more detailed examples, see the [Sample App Guide](../examples/sample-app.md).
