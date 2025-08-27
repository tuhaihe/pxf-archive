#!/bin/bash
# common-functions.sh - Shared utility functions for PXF CI/CD scripts
# This file provides common logging, error handling, and utility functions

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️ $*${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️ $*${NC}"
}

log_error() {
    echo -e "${RED}❌ $*${NC}" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}🔍 DEBUG: $*${NC}" >&2
    fi
}

# Error handling functions
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Error occurred in script at line $line_number (exit code: $exit_code)"
    
    # Collect debug information if available
    if [[ "${COLLECT_DEBUG_ON_ERROR:-true}" == "true" ]]; then
        collect_error_context "$line_number" "$exit_code"
    fi
    
    exit $exit_code
}

collect_error_context() {
    local line_number="$1"
    local exit_code="$2"
    local error_log="${TEST_RESULTS_DIR:-/tmp}/error-context.log"
    
    {
        echo "=== Error Context ==="
        echo "Timestamp: $(date)"
        echo "Script: ${BASH_SOURCE[1]:-unknown}"
        echo "Line: $line_number"
        echo "Exit Code: $exit_code"
        echo "Working Directory: $(pwd)"
        echo "User: $(whoami)"
        echo
        echo "=== Environment Variables ==="
        env | grep -E "(PXF|HADOOP|JAVA|GPHOME)" | sort
        echo
        echo "=== Recent Commands ==="
        history | tail -10 2>/dev/null || echo "History not available"
        echo
        echo "=== System Resources ==="
        df -h / 2>/dev/null || echo "Disk info not available"
        free -h 2>/dev/null || echo "Memory info not available"
    } >> "$error_log"
    
    log_info "Error context saved to: $error_log"
}

# Set up error handling
set_error_handling() {
    set -euo pipefail
    trap 'handle_error $LINENO' ERR
}

# Utility functions
check_command() {
    local cmd="$1"
    local package="${2:-$cmd}"
    
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command '$cmd' not found. Please install $package."
        return 1
    fi
    return 0
}

check_file() {
    local file="$1"
    local description="${2:-file}"
    
    if [[ ! -f "$file" ]]; then
        log_error "Required $description not found: $file"
        return 1
    fi
    return 0
}

check_directory() {
    local dir="$1"
    local description="${2:-directory}"
    
    if [[ ! -d "$dir" ]]; then
        log_error "Required $description not found: $dir"
        return 1
    fi
    return 0
}

# Retry mechanism
retry_command() {
    local max_attempts="${1:-3}"
    local delay="${2:-5}"
    shift 2
    local cmd=("$@")
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Attempt $attempt/$max_attempts: ${cmd[*]}"
        
        if "${cmd[@]}"; then
            log_success "Command succeeded on attempt $attempt"
            return 0
        else
            local exit_code=$?
            log_warning "Command failed on attempt $attempt (exit code: $exit_code)"
            
            if [[ $attempt -lt $max_attempts ]]; then
                log_info "Waiting $delay seconds before retry..."
                sleep "$delay"
            fi
        fi
        
        ((attempt++))
    done
    
    log_error "Command failed after $max_attempts attempts"
    return 1
}

# Environment validation
validate_environment() {
    log_info "🔍 Validating environment..."
    
    local required_vars=("${@:-}")
    local missing_vars=()
    
    # Check required environment variables
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        return 1
    fi
    
    # Check common tools
    local tools=("java" "tar" "gzip")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_warning "Missing optional tools: ${missing_tools[*]}"
    fi
    
    log_success "Environment validation completed"
    return 0
}

# File operations
safe_extract() {
    local archive="$1"
    local destination="${2:-.}"
    local strip_components="${3:-0}"
    
    log_info "Extracting $archive to $destination..."
    
    if [[ ! -f "$archive" ]]; then
        log_error "Archive not found: $archive"
        return 1
    fi
    
    mkdir -p "$destination"
    
    case "$archive" in
        *.tar.gz|*.tgz)
            tar -xzf "$archive" -C "$destination" --strip-components="$strip_components"
            ;;
        *.tar)
            tar -xf "$archive" -C "$destination" --strip-components="$strip_components"
            ;;
        *.zip)
            unzip -q "$archive" -d "$destination"
            ;;
        *)
            log_error "Unsupported archive format: $archive"
            return 1
            ;;
    esac
    
    log_success "Extraction completed"
    return 0
}

# Test result management
init_test_results() {
    local results_dir="${TEST_RESULTS_DIR:-/tmp/test-results}"
    
    mkdir -p "$results_dir"
    
    # Create test summary file
    cat > "$results_dir/test-summary.txt" << EOF
PXF Test Results Summary
=======================
Started: $(date)
Script: ${BASH_SOURCE[1]:-unknown}
Working Directory: $(pwd)
User: $(whoami)

EOF
    
    export TEST_RESULTS_DIR="$results_dir"
    log_info "Test results will be saved to: $results_dir"
}

record_test_result() {
    local test_name="$1"
    local status="$2"
    local message="${3:-}"
    local results_file="${TEST_RESULTS_DIR:-/tmp}/test-summary.txt"
    
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$status] $test_name: $message" >> "$results_file"
    
    case "$status" in
        "PASS"|"SUCCESS")
            log_success "$test_name: $message"
            ;;
        "FAIL"|"ERROR")
            log_error "$test_name: $message"
            ;;
        "WARN"|"WARNING")
            log_warning "$test_name: $message"
            ;;
        *)
            log_info "$test_name: $message"
            ;;
    esac
}

# Cleanup functions
cleanup_on_exit() {
    local exit_code=$?
    
    log_info "🧹 Performing cleanup..."
    
    # Clean up temporary files
    if [[ -n "${TEMP_DIR:-}" ]] && [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_info "Cleaned up temporary directory: $TEMP_DIR"
    fi
    
    # Additional cleanup can be added here
    
    if [[ $exit_code -eq 0 ]]; then
        log_success "Script completed successfully"
    else
        log_error "Script completed with errors (exit code: $exit_code)"
    fi
    
    exit $exit_code
}

# Set up cleanup trap
setup_cleanup() {
    trap cleanup_on_exit EXIT
}

# Progress tracking
show_progress() {
    local current="$1"
    local total="$2"
    local description="${3:-Progress}"
    
    local percentage=$((current * 100 / total))
    local bar_length=20
    local filled_length=$((percentage * bar_length / 100))
    
    local bar=""
    for ((i=0; i<filled_length; i++)); do
        bar+="█"
    done
    for ((i=filled_length; i<bar_length; i++)); do
        bar+="░"
    done
    
    printf "\r%s: [%s] %d%% (%d/%d)" "$description" "$bar" "$percentage" "$current" "$total"
    
    if [[ $current -eq $total ]]; then
        echo  # New line when complete
    fi
}

# Version comparison
version_compare() {
    local version1="$1"
    local version2="$2"
    
    # Remove any non-numeric prefixes
    version1=$(echo "$version1" | sed 's/^[^0-9]*//')
    version2=$(echo "$version2" | sed 's/^[^0-9]*//')
    
    if [[ "$version1" == "$version2" ]]; then
        echo 0
    elif printf '%s\n%s\n' "$version1" "$version2" | sort -V | head -1 | grep -q "^$version1$"; then
        echo -1  # version1 < version2
    else
        echo 1   # version1 > version2
    fi
}

# Help and usage functions
show_help() {
    local script_name
    script_name=$(basename "${BASH_SOURCE[1]:-script}")
    
    cat << EOF
Usage: $script_name [OPTIONS]

Common Options:
  -h, --help              Show this help message
  -v, --verbose           Enable verbose output
  -d, --debug             Enable debug output
  --test-results-dir DIR  Set test results directory (default: /tmp/test-results)

Environment Variables:
  TEST_RESULTS_DIR        Directory for test results
  DEBUG                   Enable debug mode (true/false)
  COLLECT_DEBUG_ON_ERROR  Collect debug info on errors (true/false)

Examples:
  $script_name --verbose
  $script_name --test-results-dir /tmp/my-tests

EOF
}

# Initialize common functions
init_common_functions() {
    # Set up error handling
    set_error_handling
    
    # Set up cleanup
    setup_cleanup
    
    # Initialize test results
    init_test_results
    
    log_debug "Common functions initialized"
}

# Auto-initialize if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Script is being sourced, auto-initialize
    init_common_functions
fi
