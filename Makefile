# PyDeployer - Deployment Automation Tool
# Makefile for managing virtual environment and deployment operations

# Variables
PYTHON := python3
VENV_DIR := .venv
VENV_BIN := $(VENV_DIR)/bin
PYTHON_VENV := $(VENV_BIN)/python
PIP_VENV := $(VENV_BIN)/pip
DEPLOY_SCRIPT := scripts/deploy.py
REQUIREMENTS := requirements.txt

# Default branch for deployment
BRANCH ?= main

# Colors for output
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
NC := \033[0m # No Color

# Default target
.DEFAULT_GOAL := help

# Phony targets
.PHONY: help build install clean test lint format deploy deploy-branch venv-info check-config validate \
        list-db-permissions create-superuser run-migrations collect-static validate-django \
        verify-database cleanup-deployments view-logs deployment-status undeploy docs docs-build docs-serve

help: ## Display available commands with descriptions
	@echo "$(GREEN)PyDeployer - Deployment Automation Tool$(NC)"
	@echo ""
	@echo "$(YELLOW)Available commands:$(NC)"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Usage examples:$(NC)"
	@echo "  make build                                          # Set up development environment"
	@echo "  make deploy REPO_URL=<repo> BRANCH=main             # Deploy main branch"
	@echo "  make deploy REPO_URL=<repo> BRANCH=feature/auth     # Deploy feature branch"
	@echo "  make deploy REPO_URL=<repo> BRANCH=dev               # Deploy dev branch"
	@echo ""
	@echo "$(YELLOW)Configuration:$(NC)"
	@echo "  • Uses fallback config: deploy-{branch}.yml → deploy.yml"
	@echo "  • Domain pattern: {project}-{branch} or custom domain in config"
	@echo "  • Service-level overrides: domain and env_vars per service"
	@echo ""

build: $(VENV_DIR) ## Set up virtual environment and install dependencies
	@echo "$(GREEN)✓ Development environment ready$(NC)"

$(VENV_DIR): $(REQUIREMENTS)
	@echo "$(YELLOW)Creating virtual environment...$(NC)"
	$(PYTHON) -m venv $(VENV_DIR)
	@echo "$(YELLOW)Upgrading pip...$(NC)"
	$(PIP_VENV) install --upgrade pip
	@echo "$(YELLOW)Installing dependencies...$(NC)"
	$(PIP_VENV) install -r $(REQUIREMENTS)
	@touch $(VENV_DIR)

install: build ## Alias for build target
	@echo "$(GREEN)✓ Installation complete$(NC)"

venv-info: $(VENV_DIR) ## Display virtual environment information
	@echo "$(YELLOW)Virtual Environment Information:$(NC)"
	@echo "  Location: $(VENV_DIR)"
	@echo "  Python: $$($(PYTHON_VENV) --version)"
	@echo "  Pip: $$($(PIP_VENV) --version)"
	@echo "  Installed packages:"
	@$(PIP_VENV) list --format=columns

validate-config: ## Validate deployment configuration for a project (requires PROJECT, BRANCH)
	@echo "$(YELLOW)Validating deployment configuration...$(NC)"
	@if [ -z "$(PROJECT)" ]; then echo "$(RED)Error: PROJECT is required$(NC)"; exit 1; fi
	@if [ -z "$(BRANCH)" ]; then echo "$(RED)Error: BRANCH is required$(NC)"; exit 1; fi
	@NORMALIZED_BRANCH=$$(echo "$(BRANCH)" | sed 's/\//-/g'); \
	CONFIG_FILE="projects/$(PROJECT)/deploy-$$NORMALIZED_BRANCH.yml"; \
	FALLBACK_CONFIG="projects/$(PROJECT)/deploy.yml"; \
	if [ -f "$$CONFIG_FILE" ]; then \
		echo "$(GREEN)✓ Found branch-specific config: $$CONFIG_FILE$(NC)"; \
		python3 -c "import yaml; yaml.safe_load(open('$$CONFIG_FILE')); print('✓ YAML syntax valid')"; \
	elif [ -f "$$FALLBACK_CONFIG" ]; then \
		echo "$(GREEN)✓ Found fallback config: $$FALLBACK_CONFIG$(NC)"; \
		python3 -c "import yaml; yaml.safe_load(open('$$FALLBACK_CONFIG')); print('✓ YAML syntax valid')"; \
	else \
		echo "$(RED)✗ No configuration found for $(PROJECT)/$(BRANCH)$(NC)"; \
		echo "$(YELLOW)Looked for: $$CONFIG_FILE and $$FALLBACK_CONFIG$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ Configuration validation complete$(NC)"

deploy: ## Deploy application using simplified interface (requires REPO_URL, BRANCH variables)
	@echo "$(GREEN)Starting deployment with simplified interface...$(NC)"
	@echo "$(YELLOW)Usage: make deploy REPO_URL=<url> BRANCH=<branch>$(NC)"
	@if [ -z "$(REPO_URL)" ]; then echo "$(RED)Error: REPO_URL is required$(NC)"; exit 1; fi
	@if [ -z "$(BRANCH)" ]; then echo "$(RED)Error: BRANCH is required$(NC)"; exit 1; fi
	./deploy $(REPO_URL) $(BRANCH)

test: $(VENV_DIR) ## Run tests for the deployment script
	@echo "$(YELLOW)Running deployment script tests...$(NC)"
	$(PYTHON_VENV) -m py_compile $(DEPLOY_SCRIPT)
	@echo "$(GREEN)✓ Python syntax validation passed$(NC)"
	@if [ -f "test_deploy.py" ]; then \
		$(PYTHON_VENV) -m pytest test_deploy.py -v; \
	else \
		echo "$(YELLOW)No test file found (test_deploy.py)$(NC)"; \
	fi

lint: $(VENV_DIR) ## Run linting checks on Python code
	@echo "$(YELLOW)Running linting checks...$(NC)"
	@if ! $(PIP_VENV) show flake8 > /dev/null 2>&1; then \
		echo "$(YELLOW)Installing flake8...$(NC)"; \
		$(PIP_VENV) install flake8; \
	fi
	$(VENV_BIN)/flake8 $(DEPLOY_SCRIPT) --max-line-length=88 --extend-ignore=E203,W503
	@echo "$(GREEN)✓ Linting checks passed$(NC)"

format: $(VENV_DIR) ## Format Python code using black
	@echo "$(YELLOW)Formatting Python code...$(NC)"
	@if ! $(PIP_VENV) show black > /dev/null 2>&1; then \
		echo "$(YELLOW)Installing black...$(NC)"; \
		$(PIP_VENV) install black; \
	fi
	$(VENV_BIN)/black $(DEPLOY_SCRIPT) --line-length=88
	@echo "$(GREEN)✓ Code formatting complete$(NC)"

clean: ## Remove virtual environment and temporary files
	@echo "$(YELLOW)Cleaning up...$(NC)"
	rm -rf $(VENV_DIR)
	rm -rf __pycache__
	rm -rf *.pyc
	rm -rf .pytest_cache
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

upgrade: $(VENV_DIR) ## Upgrade all dependencies to latest versions
	@echo "$(YELLOW)Upgrading dependencies...$(NC)"
	$(PIP_VENV) install --upgrade pip
	$(PIP_VENV) install --upgrade -r $(REQUIREMENTS)
	@echo "$(GREEN)✓ Dependencies upgraded$(NC)"

freeze: $(VENV_DIR) ## Generate requirements file with current package versions
	@echo "$(YELLOW)Generating requirements with pinned versions...$(NC)"
	$(PIP_VENV) freeze > requirements-frozen.txt
	@echo "$(GREEN)✓ Frozen requirements saved to requirements-frozen.txt$(NC)"

# Development helpers
dev-setup: build lint format ## Complete development setup with linting and formatting tools
	@echo "$(GREEN)✓ Development setup complete$(NC)"

# Quick deployment shortcuts for common branches
deploy-main: ## Quick deploy main branch (requires REPO_URL)
	@$(MAKE) deploy BRANCH=main

deploy-dev: ## Quick deploy dev branch (requires REPO_URL)
	@$(MAKE) deploy BRANCH=dev

deploy-qa: ## Quick deploy qa branch (requires REPO_URL)
	@$(MAKE) deploy BRANCH=qa

# System requirements check
check-system: ## Check system requirements for deployment
	@echo "$(YELLOW)Checking system requirements...$(NC)"
	@which python3 > /dev/null || (echo "$(RED)✗ Python 3 not found$(NC)" && exit 1)
	@which git > /dev/null || (echo "$(RED)✗ Git not found$(NC)" && exit 1)
	@which sudo > /dev/null || (echo "$(RED)✗ Sudo not found$(NC)" && exit 1)
	@echo "$(GREEN)✓ System requirements satisfied$(NC)"

# Show current configuration
show-config: ## Display deployment configuration for a project (requires PROJECT, BRANCH)
	@echo "$(YELLOW)Deployment Configuration:$(NC)"
	@if [ -z "$(PROJECT)" ]; then echo "$(RED)Error: PROJECT is required$(NC)"; exit 1; fi
	@if [ -z "$(BRANCH)" ]; then echo "$(RED)Error: BRANCH is required$(NC)"; exit 1; fi
	@echo "  Project: $(PROJECT)"
	@echo "  Branch: $(BRANCH)"
	@echo "  Script: $(DEPLOY_SCRIPT)"
	@echo ""
	@NORMALIZED_BRANCH=$$(echo "$(BRANCH)" | sed 's/\//-/g'); \
	CONFIG_FILE="projects/$(PROJECT)/deploy-$$NORMALIZED_BRANCH.yml"; \
	FALLBACK_CONFIG="projects/$(PROJECT)/deploy.yml"; \
	if [ -f "$$CONFIG_FILE" ]; then \
		echo "$(YELLOW)Using branch-specific config: $$CONFIG_FILE$(NC)"; \
		cat "$$CONFIG_FILE"; \
	elif [ -f "$$FALLBACK_CONFIG" ]; then \
		echo "$(YELLOW)Using fallback config: $$FALLBACK_CONFIG$(NC)"; \
		cat "$$FALLBACK_CONFIG"; \
	else \
		echo "$(RED)No configuration found for $(PROJECT)/$(BRANCH)$(NC)"; \
		echo "$(YELLOW)Looked for: $$CONFIG_FILE and $$FALLBACK_CONFIG$(NC)"; \
	fi

# Dependencies update
update-requirements: $(VENV_DIR) ## Update requirements.txt with new dependencies
	@echo "$(YELLOW)Current requirements:$(NC)"
	@cat $(REQUIREMENTS)
	@echo ""
	@echo "$(YELLOW)To add new dependencies:$(NC)"
	@echo "  1. $(PIP_VENV) install <package-name>"
	@echo "  2. make freeze"
	@echo "  3. Update $(REQUIREMENTS) manually if needed"

# Database and Django Management Commands
list-db-permissions: ## List PostgreSQL databases and their user permissions
	@echo "$(YELLOW)Listing database permissions...$(NC)"
	@if [ -n "$(DB)" ]; then \
		$(PYTHON) scripts/list-database-permissions.py $(DB); \
	else \
		$(PYTHON) scripts/list-database-permissions.py; \
	fi

create-superuser: ## Create Django superuser (requires PROJECT_DIR, optionally USERNAME, EMAIL, PASSWORD)
	@echo "$(YELLOW)Creating Django superuser...$(NC)"
	@if [ -z "$(PROJECT_DIR)" ]; then echo "$(RED)Error: PROJECT_DIR is required$(NC)"; exit 1; fi
	@if [ -n "$(USERNAME)" ] && [ -n "$(EMAIL)" ] && [ -n "$(PASSWORD)" ]; then \
		DJANGO_SUPERUSER_USERNAME=$(USERNAME) DJANGO_SUPERUSER_EMAIL=$(EMAIL) DJANGO_SUPERUSER_PASSWORD=$(PASSWORD) \
		bash scripts/create-django-superuser.sh $(PROJECT_DIR); \
	else \
		bash scripts/create-django-superuser.sh $(PROJECT_DIR); \
	fi

run-migrations: ## Run Django database migrations (requires PROJECT_DIR)
	@echo "$(YELLOW)Running Django migrations...$(NC)"
	@if [ -z "$(PROJECT_DIR)" ]; then echo "$(RED)Error: PROJECT_DIR is required$(NC)"; exit 1; fi
	bash scripts/run-django-migrations.sh $(PROJECT_DIR)

collect-static: ## Collect Django static files (requires PROJECT_DIR)
	@echo "$(YELLOW)Collecting Django static files...$(NC)"
	@if [ -z "$(PROJECT_DIR)" ]; then echo "$(RED)Error: PROJECT_DIR is required$(NC)"; exit 1; fi
	bash scripts/collect-django-static.sh $(PROJECT_DIR)

validate-django: ## Validate Django environment (requires PROJECT_DIR)
	@echo "$(YELLOW)Validating Django environment...$(NC)"
	@if [ -z "$(PROJECT_DIR)" ]; then echo "$(RED)Error: PROJECT_DIR is required$(NC)"; exit 1; fi
	bash scripts/validate-django-environment.sh $(PROJECT_DIR)

verify-database: ## Verify PostgreSQL database connection and setup (requires PROJECT, BRANCH)
	@echo "$(YELLOW)Verifying database setup...$(NC)"
	@if [ -z "$(PROJECT)" ]; then echo "$(RED)Error: PROJECT is required$(NC)"; exit 1; fi
	@if [ -z "$(BRANCH)" ]; then echo "$(RED)Error: BRANCH is required$(NC)"; exit 1; fi
	bash scripts/verify-postgresql-database.sh $(PROJECT) $(BRANCH)

# Deployment Management Commands
cleanup-deployments: ## Clean up old deployments (optionally specify DAYS_OLD)
	@echo "$(YELLOW)Cleaning up old deployments...$(NC)"
	@if [ -n "$(DAYS_OLD)" ]; then \
		bash scripts/cleanup-deployments.sh $(DAYS_OLD); \
	else \
		bash scripts/cleanup-deployments.sh; \
	fi

view-logs: ## View deployment logs (requires PROJECT, BRANCH, optionally SERVICE)
	@echo "$(YELLOW)Viewing deployment logs...$(NC)"
	@if [ -z "$(PROJECT)" ]; then echo "$(RED)Error: PROJECT is required$(NC)"; exit 1; fi
	@if [ -z "$(BRANCH)" ]; then echo "$(RED)Error: BRANCH is required$(NC)"; exit 1; fi
	@if [ -n "$(SERVICE)" ]; then \
		bash scripts/view-logs.sh $(PROJECT) $(BRANCH) $(SERVICE); \
	else \
		bash scripts/view-logs.sh $(PROJECT) $(BRANCH); \
	fi

deployment-status: ## Check deployment status (requires PROJECT, BRANCH)
	@echo "$(YELLOW)Checking deployment status...$(NC)"
	@if [ -z "$(PROJECT)" ]; then echo "$(RED)Error: PROJECT is required$(NC)"; exit 1; fi
	@if [ -z "$(BRANCH)" ]; then echo "$(RED)Error: BRANCH is required$(NC)"; exit 1; fi
	bash scripts/deployment-status.sh $(PROJECT) $(BRANCH)

undeploy: ## Remove a deployment (requires PROJECT, BRANCH)
	@echo "$(YELLOW)Removing deployment...$(NC)"
	@if [ -z "$(PROJECT)" ]; then echo "$(RED)Error: PROJECT is required$(NC)"; exit 1; fi
	@if [ -z "$(BRANCH)" ]; then echo "$(RED)Error: BRANCH is required$(NC)"; exit 1; fi
	./undeploy $(PROJECT) $(BRANCH)

# Documentation Commands
docs: ## Build and serve documentation locally
	@$(MAKE) -C docs serve

docs-build: ## Build documentation only
	@$(MAKE) -C docs build

docs-serve: ## Serve documentation (requires docs to be built first)
	@$(MAKE) -C docs serve
