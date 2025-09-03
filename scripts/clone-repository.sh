#!/bin/bash
# clone-repository.sh - Git Repository Cloning Script
# 
# This script clones a Git repository to a specified directory.
# Uses environment variables for configuration.
#
# Required Environment Variables:
#   REPO_URL    - Git repository URL to clone
#   TARGET_DIR  - Directory where repository should be cloned
#   BRANCH      - Git branch to checkout
#
# Optional Environment Variables:
#   CLONE_DEPTH     - Clone depth for shallow clone (default: full clone)
#   REMOVE_EXISTING - Remove existing directory before clone (default: true)
#   GIT_SSH_KEY     - Path to SSH key for private repositories

set -e  # Exit on any error

# Default values
REMOVE_EXISTING="${REMOVE_EXISTING:-true}"
CLONE_DEPTH="${CLONE_DEPTH:-}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check required environment variables
check_required_vars() {
    local missing_vars=()
    
    if [[ -z "${REPO_URL}" ]]; then
        missing_vars+=("REPO_URL")
    fi
    
    if [[ -z "${TARGET_DIR}" ]]; then
        missing_vars+=("TARGET_DIR")
    fi
    
    if [[ -z "${BRANCH}" ]]; then
        missing_vars+=("BRANCH")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_error "Required variables: REPO_URL, TARGET_DIR, BRANCH"
        log_error "Optional variables: CLONE_DEPTH, REMOVE_EXISTING (default: true), GIT_SSH_KEY"
        exit 1
    fi
}

# Check if git is available
check_git() {
    if ! command -v git >/dev/null 2>&1; then
        log_error "Git is not installed or not available in PATH"
        exit 1
    fi
    
    local git_version
    git_version=$(git --version)
    log_info "Using: ${git_version}"
}

# Setup SSH key if provided
setup_ssh_key() {
    if [[ -n "${GIT_SSH_KEY}" ]]; then
        if [[ -f "${GIT_SSH_KEY}" ]]; then
            log_info "Using SSH key: ${GIT_SSH_KEY}"
            export GIT_SSH_COMMAND="ssh -i ${GIT_SSH_KEY} -o StrictHostKeyChecking=no"
        else
            log_error "SSH key file not found: ${GIT_SSH_KEY}"
            exit 1
        fi
    fi
}

# Validate repository URL format
validate_repo_url() {
    log_info "Validating repository URL: ${REPO_URL}"
    
    # Basic validation for common Git URL formats
    if [[ "${REPO_URL}" =~ ^https://.*\.git$ ]] || \
       [[ "${REPO_URL}" =~ ^git@.*:.*\.git$ ]] || \
       [[ "${REPO_URL}" =~ ^ssh://git@.*/.* ]] || \
       [[ "${REPO_URL}" =~ ^https://github\.com/.* ]] || \
       [[ "${REPO_URL}" =~ ^https://gitlab\.com/.* ]] || \
       [[ "${REPO_URL}" =~ ^https://bitbucket\.org/.* ]]; then
        log_info "Repository URL format appears valid"
    else
        log_warn "Repository URL format may not be standard Git format"
        log_warn "Proceeding anyway, but clone may fail if URL is invalid"
    fi
}

# Test repository connectivity
test_repo_connectivity() {
    log_info "Testing repository connectivity..."
    
    # Use git ls-remote to test if we can connect to the repository
    if git ls-remote --heads "${REPO_URL}" >/dev/null 2>&1; then
        log_info "Repository is accessible"
    else
        log_error "Cannot access repository: ${REPO_URL}"
        log_error "Check URL, credentials, or network connectivity"
        exit 1
    fi
}

# Check if branch exists
check_branch_exists() {
    log_info "Checking if branch '${BRANCH}' exists..."
    
    if git ls-remote --heads "${REPO_URL}" | grep -q "refs/heads/${BRANCH}$"; then
        log_info "Branch '${BRANCH}' found in remote repository"
    else
        log_error "Branch '${BRANCH}' does not exist in repository"
        log_info "Available branches:"
        git ls-remote --heads "${REPO_URL}" | sed 's|.*refs/heads/||' | head -10
        exit 1
    fi
}

# Remove existing directory if it exists
remove_existing_directory() {
    if [[ "${REMOVE_EXISTING}" == "true" ]] && [[ -d "${TARGET_DIR}" ]]; then
        log_warn "Removing existing directory: ${TARGET_DIR}"
        rm -rf "${TARGET_DIR}"
    elif [[ -d "${TARGET_DIR}" ]]; then
        log_error "Target directory already exists: ${TARGET_DIR}"
        log_error "Set REMOVE_EXISTING=true to remove it automatically"
        exit 1
    fi
}

# Create parent directories
create_parent_directories() {
    local parent_dir
    parent_dir=$(dirname "${TARGET_DIR}")
    
    if [[ ! -d "${parent_dir}" ]]; then
        log_info "Creating parent directories: ${parent_dir}"
        mkdir -p "${parent_dir}"
    fi
}

# Clone repository
clone_repository() {
    log_info "Cloning repository to: ${TARGET_DIR}"
    log_info "Repository: ${REPO_URL}"
    log_info "Branch: ${BRANCH}"
    
    # Build git clone command
    local clone_cmd="git clone"
    
    # Add depth if specified (shallow clone)
    if [[ -n "${CLONE_DEPTH}" ]]; then
        clone_cmd="${clone_cmd} --depth ${CLONE_DEPTH}"
        log_info "Using shallow clone with depth: ${CLONE_DEPTH}"
    fi
    
    # Add branch
    clone_cmd="${clone_cmd} -b ${BRANCH}"
    
    # Add URL and target directory
    clone_cmd="${clone_cmd} ${REPO_URL} ${TARGET_DIR}"
    
    log_info "Running: ${clone_cmd}"
    
    if eval "${clone_cmd}"; then
        log_info "Repository cloned successfully"
    else
        log_error "Failed to clone repository"
        exit 1
    fi
}

# Verify clone
verify_clone() {
    log_info "Verifying repository clone..."
    
    # Check if target directory exists and is not empty
    if [[ ! -d "${TARGET_DIR}" ]]; then
        log_error "Target directory does not exist after clone"
        return 1
    fi
    
    if [[ ! -d "${TARGET_DIR}/.git" ]]; then
        log_error "Target directory is not a Git repository"
        return 1
    fi
    
    # Change to target directory for Git operations
    cd "${TARGET_DIR}"
    
    # Check current branch
    local current_branch
    current_branch=$(git branch --show-current)
    if [[ "${current_branch}" == "${BRANCH}" ]]; then
        log_info "✓ Correct branch checked out: ${current_branch}"
    else
        log_error "✗ Wrong branch checked out. Expected: ${BRANCH}, Got: ${current_branch}"
        return 1
    fi
    
    # Check remote origin
    local remote_url
    remote_url=$(git remote get-url origin)
    if [[ "${remote_url}" == "${REPO_URL}" ]]; then
        log_info "✓ Correct remote origin: ${remote_url}"
    else
        log_error "✗ Wrong remote origin. Expected: ${REPO_URL}, Got: ${remote_url}"
        return 1
    fi
    
    # Get latest commit info
    local latest_commit
    latest_commit=$(git log -1 --oneline)
    log_info "✓ Latest commit: ${latest_commit}"
    
    # Count files in repository
    local file_count
    file_count=$(find . -type f -not -path './.git/*' | wc -l)
    log_info "✓ Repository contains ${file_count} files"
    
    log_info "Repository clone verification completed successfully"
    return 0
}

# Show repository information
show_repo_info() {
    cd "${TARGET_DIR}"
    
    log_info "Repository Information:"
    echo "  Path: ${TARGET_DIR}"
    echo "  Remote URL: $(git remote get-url origin)"
    echo "  Current Branch: $(git branch --show-current)"
    echo "  Latest Commit: $(git log -1 --oneline)"
    echo "  Repository Size: $(du -sh . | cut -f1)"
    
    # Show recent commits
    log_info "Recent commits:"
    git log --oneline -5 | sed 's/^/  /'
}

# Main execution function
main() {
    log_info "Starting Git repository cloning"
    log_info "Repository: ${REPO_URL}"
    log_info "Target directory: ${TARGET_DIR}"
    log_info "Branch: ${BRANCH}"
    
    # Check required variables
    check_required_vars
    
    # Check Git availability
    check_git
    
    # Setup SSH key if provided
    setup_ssh_key
    
    # Validate repository URL
    validate_repo_url
    
    # Test repository connectivity
    test_repo_connectivity
    
    # Check if branch exists
    check_branch_exists
    
    # Remove existing directory if needed
    remove_existing_directory
    
    # Create parent directories
    create_parent_directories
    
    # Clone repository
    clone_repository
    
    # Verify clone
    if verify_clone; then
        show_repo_info
        log_info "🎉 Repository cloning completed successfully"
        return 0
    else
        log_error "Repository clone verification failed"
        return 1
    fi
}

# Help function
show_help() {
    cat << EOF
clone-repository.sh - Git Repository Cloning Script

DESCRIPTION:
    This script clones a Git repository to a specified directory with comprehensive
    validation and verification.

REQUIRED ENVIRONMENT VARIABLES:
    REPO_URL     Git repository URL (HTTPS or SSH)
    TARGET_DIR   Directory where repository should be cloned
    BRANCH       Git branch to checkout

OPTIONAL ENVIRONMENT VARIABLES:
    CLONE_DEPTH      Clone depth for shallow clone (omit for full clone)
    REMOVE_EXISTING  Remove existing directory before clone (default: true)
    GIT_SSH_KEY     Path to SSH key for private repositories

USAGE:
    # Basic HTTPS clone
    export REPO_URL="https://github.com/user/repo.git"
    export TARGET_DIR="/srv/app/code"
    export BRANCH="main"
    ./clone-repository.sh
    
    # SSH clone with key
    export REPO_URL="git@github.com:user/repo.git"
    export TARGET_DIR="/opt/app"
    export BRANCH="develop"
    export GIT_SSH_KEY="/home/user/.ssh/id_rsa"
    ./clone-repository.sh
    
    # Shallow clone
    export REPO_URL="https://github.com/user/repo.git"
    export TARGET_DIR="/tmp/repo"
    export BRANCH="main"
    export CLONE_DEPTH="1"
    ./clone-repository.sh

OPERATIONS PERFORMED:
    ✓ Environment variables validation
    ✓ Git availability check
    ✓ SSH key setup (if provided)
    ✓ Repository URL validation
    ✓ Repository connectivity test
    ✓ Branch existence verification
    ✓ Existing directory removal (optional)
    ✓ Repository cloning
    ✓ Clone verification

EXIT CODES:
    0  Success - Repository cloned and verified
    1  Error - Cloning or verification failed

EXAMPLES:
    # Clone main branch
    REPO_URL="https://github.com/user/repo.git" TARGET_DIR="/srv/app" BRANCH="main" ./clone-repository.sh
    
    # Clone with SSH key
    REPO_URL="git@github.com:user/repo.git" TARGET_DIR="/opt/app" BRANCH="develop" GIT_SSH_KEY="~/.ssh/id_rsa" ./clone-repository.sh
    
    # Shallow clone without removing existing directory
    REPO_URL="https://github.com/user/repo.git" TARGET_DIR="/tmp/repo" BRANCH="main" CLONE_DEPTH="1" REMOVE_EXISTING="false" ./clone-repository.sh
EOF
}

# Handle command line arguments
case "${1:-}" in
    -h|--help|help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
