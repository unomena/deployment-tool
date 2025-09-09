# Installation

This guide will walk you through installing and setting up PyDeployer on your Ubuntu LTS server.

## Prerequisites

### System Requirements

- **Operating System**: Ubuntu 20.04 LTS or newer
- **Python**: Python 3.8 or newer
- **Git**: For repository cloning
- **PostgreSQL**: For database management
- **Supervisor**: For service management
- **Nginx**: For web server (optional, for production)

### Required Packages

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install essential packages
sudo apt install -y python3 python3-venv python3-pip git postgresql postgresql-contrib supervisor nginx

# Install Python PostgreSQL adapter
sudo apt install -y python3-psycopg2
```

## Installation Steps

### 1. Clone PyDeployer Repository

```bash
# Clone the repository
git clone <repository-url> /opt/pydeployer
cd /opt/pydeployer

# Make scripts executable
chmod +x deploy undeploy status viewlogs
```

### 2. Set Up Development Environment

```bash
# Create and activate virtual environment
make build

# Verify installation
make venv-info
```

### 3. Configure Database Access

Create the main configuration file:

```bash
# Copy example configuration
cp config.yml.example config.yml

# Edit configuration with your database credentials
nano config.yml
```

Example `config.yml`:

```yaml
databases:
  - name: localhost-postgresql
    type: postgresql
    root_user: postgres
    root_password: your_secure_password
    host: localhost
    port: 5432
    description: "Local PostgreSQL server"

redis:
  - name: localhost-redis
    host: localhost
    port: 6379
    password: ""
    description: "Local Redis server"
```

### 4. Verify Installation

```bash
# Check system requirements
make check-system

# Test database connection
make list-db-permissions

# Verify all components
make validate CONFIG=deploy-dev.yml
```

## Post-Installation Setup

### Configure PostgreSQL

1. **Set PostgreSQL password**:
   ```bash
   sudo -u postgres psql
   \password postgres
   \q
   ```

2. **Update pg_hba.conf** for local connections:
   ```bash
   sudo nano /etc/postgresql/*/main/pg_hba.conf
   ```
   
   Change the line:
   ```
   local   all             postgres                                peer
   ```
   to:
   ```
   local   all             postgres                                md5
   ```

3. **Restart PostgreSQL**:
   ```bash
   sudo systemctl restart postgresql
   ```

### Configure Supervisor

Ensure Supervisor is running:

```bash
sudo systemctl enable supervisor
sudo systemctl start supervisor
sudo systemctl status supervisor
```

### Set Up Deployment Directory

```bash
# Create deployment directory
sudo mkdir -p /srv/deployments
sudo chown $USER:$USER /srv/deployments
```

## Verification

Test your installation with a sample deployment:

```bash
# Test with a simple project
make deploy REPO_URL=https://github.com/django/django-project-template.git BRANCH=main
```

## Next Steps

- **[Quick Start Guide](quick-start.md)** - Deploy your first application
- **[Configuration Guide](configuration.md)** - Detailed configuration options
- **[Sample App Example](../examples/sample-app.md)** - Complete deployment walkthrough

## Troubleshooting

### Common Issues

**Permission Denied Errors**:
```bash
# Fix ownership of deployment directory
sudo chown -R $USER:$USER /srv/deployments

# Make scripts executable
chmod +x deploy undeploy status viewlogs
```

**PostgreSQL Connection Issues**:
```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# Test connection
psql -U postgres -h localhost -c "SELECT version();"
```

**Python Virtual Environment Issues**:
```bash
# Clean and rebuild environment
make clean
make build
```

For more troubleshooting help, see the [Troubleshooting Guide](../reference/troubleshooting.md).
