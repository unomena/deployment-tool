# Database Credential Separation

## Overview

PyDeployer implements a secure database credential separation system that distinguishes between:
1. **Root/Admin credentials** - Used only for database and user creation
2. **Application credentials** - Used by the application at runtime

This separation ensures that applications never have access to database root credentials, following the principle of least privilege.

## Configuration Structure

### 1. Database Server Configuration (`config.yml` or `/etc/deployment-tool/db-servers.yml`)

This file contains root credentials for database servers and is stored securely on the deployment server:

```yaml
databases:
  - name: localhost-postgresql
    type: postgresql
    root_user: postgres
    root_password: postgres_root_password
    host: localhost
    port: 5432
  
  - name: production-db
    type: postgresql
    root_user: root
    root_password: production_root_password
    host: prod.example.com
    port: 5432
```

**Location Priority:**
1. `/etc/deployment-tool/db-servers.yml` (system-wide)
2. `/srv/deployment-tool/config/db-servers.yml` (deployment tool specific)
3. `~/.deployment-tool/db-servers.yml` (user-specific)
4. `/opt/deployment-tool/config/db-servers.yml` (alternative system location)
5. `config.yml` in project root (for development/testing)

### 2. Deployment Configuration (`deploy-{env}.yml`)

The deployment configuration has two distinct sections for database configuration:

#### `database` Section
Used by deployment scripts for database creation and verification:

```yaml
database:
  type: postgresql
  name: ${DB_NAME}        # Can reference env_vars
  user: ${DB_USER}        # Can reference env_vars
  password: ${DB_PASSWORD} # Can reference env_vars
  host: ${DB_HOST}        # Can reference env_vars
  port: ${DB_PORT}        # Can reference env_vars
```

#### `env_vars` Section
Environment variables passed to the running application:

```yaml
env_vars:
  DB_NAME: "myapp_dev"
  DB_USER: "myapp_user"
  DB_PASSWORD: "app_password"
  DB_HOST: "localhost"
  DB_PORT: "5432"
```

## How It Works

### 1. Database Creation Process

When `verify-postgresql-database.sh` runs:

1. **Load Database Configuration**: The script receives database configuration from the `database` section via environment variables
2. **Load Root Credentials**: The script calls `manage-database-credentials.py` to load root credentials for the specified host
3. **Create Database**: Uses root credentials to create the database and user if they don't exist
4. **Grant Permissions**: Sets up proper permissions for the application user
5. **Test Connection**: Verifies the application can connect with its credentials

### 2. Application Runtime

The application receives only the `env_vars` section values and never has access to root credentials.

## Script Components

### `manage-database-credentials.py`

Manages database server credentials:
- Loads root credentials from configuration file
- Matches database host to find appropriate credentials
- Exports credentials as environment variables for use by other scripts

Usage:
```bash
# Export credentials as shell variables
eval $(DB_HOST=localhost ./manage-database-credentials.py)

# Get JSON output
DB_HOST=prod.example.com ./manage-database-credentials.py --json
```

### `verify-postgresql-database.sh`

Database verification and creation script:
- Uses values from `database` section of deployment config
- Loads root credentials via `manage-database-credentials.py`
- Creates database and user if needed
- Grants appropriate permissions
- Tests connection with application credentials

### `deploy.py`

The orchestrator:
- Loads deployment configuration
- Expands template variables in `database` section
- Passes database configuration to verification scripts
- Ensures proper credential separation

## Security Benefits

1. **Least Privilege**: Applications only have the permissions they need
2. **Credential Isolation**: Root passwords are never exposed to application code
3. **Centralized Management**: Database credentials managed in one secure location
4. **Audit Trail**: All database creation operations logged with root user identification

## Example Workflow

1. **Setup**: Admin creates `/etc/deployment-tool/db-servers.yml` with root credentials
2. **Deploy**: Developer creates `deploy-dev.yml` with application database config
3. **Execution**: 
   - Deploy script reads both configurations
   - Database verification uses root credentials to create database
   - Application uses its own credentials for runtime access
4. **Runtime**: Application connects with limited privileges

## Best Practices

1. **Secure Storage**: Store `db-servers.yml` with restricted permissions (600)
2. **Different Passwords**: Never use root passwords for application users
3. **Host Matching**: Use specific hostnames in server configurations
4. **Regular Rotation**: Rotate both root and application credentials regularly
5. **Environment Separation**: Use different database users for different environments

## Troubleshooting

### Credentials Not Found
- Check `DB_SERVERS_CONFIG` environment variable
- Verify configuration file exists in expected location
- Ensure host in deployment config matches server configuration

### Permission Denied
- Verify root user has CREATEROLE and CREATEDB permissions
- Check PostgreSQL authentication configuration (pg_hba.conf)
- Ensure network connectivity to database server

### Database Creation Fails
- Check root credentials are correct
- Verify database server is running
- Review PostgreSQL logs for detailed errors
