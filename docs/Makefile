# Documentation Makefile for PyDeployer
# Manages MkDocs documentation with isolated virtual environment

# Variables
PYTHON := python3
VENV_DIR := .venv-docs
VENV_BIN := $(VENV_DIR)/bin
PYTHON_VENV := $(VENV_BIN)/python
PIP_VENV := $(VENV_BIN)/pip
MKDOCS_VENV := $(VENV_BIN)/mkdocs

# Colors for output
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
NC := \033[0m # No Color

# Default target
.DEFAULT_GOAL := help

# Phony targets
.PHONY: help build serve clean install dev-setup

help: ## Display available documentation commands
	@echo "$(GREEN)PyDeployer Documentation$(NC)"
	@echo ""
	@echo "$(YELLOW)Available commands:$(NC)"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""
	@echo "$(YELLOW)Usage examples:$(NC)"
	@echo "  make install    # Set up documentation environment"
	@echo "  make serve      # Build and serve docs locally"
	@echo "  make build      # Build static documentation"
	@echo ""

$(VENV_DIR): ## Create virtual environment for documentation
	@echo "$(YELLOW)Creating documentation virtual environment...$(NC)"
	$(PYTHON) -m venv $(VENV_DIR)
	@echo "$(YELLOW)Upgrading pip...$(NC)"
	$(PIP_VENV) install --upgrade pip
	@echo "$(YELLOW)Installing MkDocs and dependencies...$(NC)"
	$(PIP_VENV) install mkdocs mkdocs-material mkdocs-mermaid2-plugin mkdocs-awesome-pages-plugin
	@touch $(VENV_DIR)

install: $(VENV_DIR) ## Install documentation dependencies
	@echo "$(GREEN)✓ Documentation environment ready$(NC)"

build: $(VENV_DIR) ## Build static documentation
	@echo "$(YELLOW)Building documentation...$(NC)"
	$(MKDOCS_VENV) build
	@echo "$(GREEN)✓ Documentation built in site/ directory$(NC)"

serve: $(VENV_DIR) ## Serve documentation locally with live reload
	@echo "$(YELLOW)Starting documentation server...$(NC)"
	@echo "$(GREEN)Documentation will be available at http://0.0.0.0:8500$(NC)"
	$(MKDOCS_VENV) serve --dev-addr=0.0.0.0:8500

dev-setup: install ## Complete setup for documentation development
	@echo "$(GREEN)✓ Documentation development setup complete$(NC)"

clean: ## Remove virtual environment and built files
	@echo "$(YELLOW)Cleaning documentation environment...$(NC)"
	rm -rf $(VENV_DIR)
	rm -rf site/
	@echo "$(GREEN)✓ Documentation cleanup complete$(NC)"

# Check if docs are up to date
check: $(VENV_DIR) ## Check if documentation builds without errors
	@echo "$(YELLOW)Checking documentation build...$(NC)"
	$(MKDOCS_VENV) build --strict
	@echo "$(GREEN)✓ Documentation check passed$(NC)"
