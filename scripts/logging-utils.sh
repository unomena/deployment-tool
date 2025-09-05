#!/bin/bash
# logging-utils.sh - Common logging utilities for deployment scripts
#
# This file provides consistent logging functions that automatically handle
# color output based on whether output is going to a terminal or being redirected.

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions that detect terminal vs file output
log_info() {
    if [[ -t 1 ]]; then
        echo -e "${GREEN}[INFO]${NC} $1"
    else
        echo "[INFO] $1"
    fi
}

log_warn() {
    if [[ -t 1 ]]; then
        echo -e "${YELLOW}[WARN]${NC} $1"
    else
        echo "[WARN] $1"
    fi
}

log_error() {
    if [[ -t 1 ]]; then
        echo -e "${RED}[ERROR]${NC} $1"
    else
        echo "[ERROR] $1"
    fi
}

log_success() {
    if [[ -t 1 ]]; then
        echo -e "${GREEN}[✓]${NC} $1"
    else
        echo "[✓] $1"
    fi
}

log_failure() {
    if [[ -t 1 ]]; then
        echo -e "${RED}[✗]${NC} $1"
    else
        echo "[✗] $1"
    fi
}

log_debug() {
    if [[ -t 1 ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    else
        echo "[DEBUG] $1"
    fi
}

log_step() {
    if [[ -t 1 ]]; then
        echo -e "${BLUE}[STEP]${NC} $1"
    else
        echo "[STEP] $1"
    fi
}
