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

# Default config file (can be overridden)
CONFIG ?= deploy-branch.yml
BRANCH ?= main

# Colors for output
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
NC := \033[0m # No Color

# Default target
.DEFAULT_GOAL := help

# Phony targets
.PHONY: help build install clean test lint format deploy deploy-branch venv-info check-config validate

help: ## Display available commands with descriptions
	@echo "$(GREEN)PyDeployer - Deployment Automation Tool$(NC)"
	@echo ""
	@echo "$(YELLOW)Available commands:$(NC)"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Usage examples:$(NC)"
	@echo "  make build                                    # Set up development environment"
	@echo "  make deploy REPO_URL=<repo> BRANCH=main ENV=prod    # Deploy main branch to production"
	@echo "  make deploy REPO_URL=<repo> BRANCH=dev ENV=dev      # Deploy dev branch to development"
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

check-config: ## Validate that CONFIG file exists and is readable
	@if [ ! -f "$(CONFIG)" ]; then \
		echo "$(RED)✗ Config file not found: $(CONFIG)$(NC)"; \
		echo "$(YELLOW)Usage: make deploy CONFIG=your-config.yml$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✓ Config file found: $(CONFIG)$(NC)"

validate: $(VENV_DIR) check-config ## Validate deployment configuration without deploying
	@echo "$(YELLOW)Validating deployment configuration...$(NC)"
	$(PYTHON_VENV) -c "import yaml; config = yaml.safe_load(open('$(CONFIG)')); print('✓ YAML syntax valid')"
	@echo "$(GREEN)✓ Configuration validation complete$(NC)"

deploy: ## Deploy application using simplified interface (requires REPO_URL, BRANCH, ENV variables)
	@echo "$(GREEN)Starting deployment with simplified interface...$(NC)"
	@echo "$(YELLOW)Usage: make deploy REPO_URL=<url> BRANCH=<branch> ENV=<environment>$(NC)"
	@if [ -z "$(REPO_URL)" ]; then echo "$(RED)Error: REPO_URL is required$(NC)"; exit 1; fi
	@if [ -z "$(BRANCH)" ]; then echo "$(RED)Error: BRANCH is required$(NC)"; exit 1; fi
	@if [ -z "$(ENV)" ]; then echo "$(RED)Error: ENV is required (prod|stage|qa|dev|branch)$(NC)"; exit 1; fi
	./deploy $(REPO_URL) $(BRANCH) $(ENV)

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

# Quick deployment shortcuts for common environments
deploy-dev: ## Quick deploy to dev environment (assumes deploy-dev.yml exists)
	@$(MAKE) deploy CONFIG=deploy-dev.yml

deploy-staging: ## Quick deploy to staging environment (assumes deploy-staging.yml exists)
	@$(MAKE) deploy CONFIG=deploy-staging.yml

deploy-prod: ## Quick deploy to production environment (assumes deploy-prod.yml exists)
	@$(MAKE) deploy CONFIG=deploy-prod.yml

# System requirements check
check-system: ## Check system requirements for deployment
	@echo "$(YELLOW)Checking system requirements...$(NC)"
	@which python3 > /dev/null || (echo "$(RED)✗ Python 3 not found$(NC)" && exit 1)
	@which git > /dev/null || (echo "$(RED)✗ Git not found$(NC)" && exit 1)
	@which sudo > /dev/null || (echo "$(RED)✗ Sudo not found$(NC)" && exit 1)
	@echo "$(GREEN)✓ System requirements satisfied$(NC)"

# Show current configuration
show-config: check-config ## Display current deployment configuration
	@echo "$(YELLOW)Current Deployment Configuration:$(NC)"
	@echo "  Config file: $(CONFIG)"
	@echo "  Branch: $(BRANCH)"
	@echo "  Script: $(DEPLOY_SCRIPT)"
	@echo ""
	@echo "$(YELLOW)Configuration contents:$(NC)"
	@cat $(CONFIG)

# Dependencies update
update-requirements: $(VENV_DIR) ## Update requirements.txt with new dependencies
	@echo "$(YELLOW)Current requirements:$(NC)"
	@cat $(REQUIREMENTS)
	@echo ""
	@echo "$(YELLOW)To add new dependencies:$(NC)"
	@echo "  1. $(PIP_VENV) install <package-name>"
	@echo "  2. make freeze"
	@echo "  3. Update $(REQUIREMENTS) manually if needed"
