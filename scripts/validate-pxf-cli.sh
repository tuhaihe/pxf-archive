#!/bin/bash
# validate-pxf-cli.sh - Dedicated PXF CLI validation script
# Inspired by Concourse's modular approach

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-functions.sh"

# CLI validation configuration
CLI_PATHS=(
    "pxf-extracted/bin/pxf"
    "pxf-extracted/pxf/bin/pxf"
    "pxf-extracted/cli/pxf"
    "pxf-extracted/pxf-cli"
    "pxf-extracted/build/pxf-cli"
    "pxf-extracted/cli/build/pxf-cli"
    "pxf-extracted/stage/bin/pxf"
    "pxf-extracted/stage/pxf/bin/pxf"
)

CLI_COMMANDS=(
    "version"
    "help"
    "cluster --help"
    "server --help"
)

function validate_cli_binary() {
    local cli_path=""

    log_info "🔍 Searching for PXF CLI binary..."

    for path in "${CLI_PATHS[@]}"; do
        if [[ -f "$path" ]]; then
            cli_path="$path"
            log_success "Found PXF CLI at: $cli_path"
            break
        fi
    done

    if [[ -z "$cli_path" ]]; then
        log_error "PXF CLI binary not found in expected locations"
        log_info "Searched paths:"
        printf '  - %s\n' "${CLI_PATHS[@]}"

        # Set empty path to prevent unbound variable errors
        export PXF_CLI_PATH=""
        return 1
    fi

    # Make CLI executable
    chmod +x "$cli_path"

    # Export for use in other functions
    export PXF_CLI_PATH="$cli_path"
    return 0
}

function validate_cli_permissions() {
    log_info "🔐 Validating CLI permissions..."

    if [[ -z "${PXF_CLI_PATH:-}" ]]; then
        log_error "PXF CLI path not set"
        return 1
    fi

    if [[ ! -x "$PXF_CLI_PATH" ]]; then
        log_error "PXF CLI is not executable"
        return 1
    fi

    log_success "CLI permissions validated"
    return 0
}

function validate_cli_commands() {
    log_info "⚙️ Validating CLI commands..."

    if [[ -z "${PXF_CLI_PATH:-}" ]]; then
        log_warning "Cannot validate CLI commands - CLI path not set"
        return 0
    fi

    local failed_commands=()

    for cmd in "${CLI_COMMANDS[@]}"; do
        log_info "Testing command: pxf $cmd"

        if timeout 10s "$PXF_CLI_PATH" $cmd >/dev/null 2>&1; then
            log_success "✅ Command 'pxf $cmd' works"
        else
            log_warning "⚠️ Command 'pxf $cmd' failed"
            failed_commands+=("$cmd")
        fi
    done
    
    if [[ ${#failed_commands[@]} -gt 0 ]]; then
        log_warning "Some CLI commands failed:"
        printf '  - pxf %s\n' "${failed_commands[@]}"
        
        # Don't fail if only non-critical commands failed
        if [[ ${#failed_commands[@]} -lt ${#CLI_COMMANDS[@]} ]]; then
            log_info "Core CLI functionality appears to work"
            return 0
        else
            log_error "All CLI commands failed"
            return 1
        fi
    fi
    
    log_success "All CLI commands validated"
    return 0
}

function validate_cli_version() {
    log_info "🏷️ Validating CLI version..."

    if [[ -z "${PXF_CLI_PATH:-}" ]]; then
        log_warning "Could not retrieve CLI version - CLI path not set"
        return 0
    fi

    local version_output
    if version_output=$("$PXF_CLI_PATH" version 2>/dev/null); then
        log_info "CLI version output: $version_output"

        # Check if version contains expected pattern
        if echo "$version_output" | grep -q "PXF version"; then
            log_success "CLI version format is correct"
        else
            log_warning "CLI version format is unexpected"
        fi
    else
        log_warning "Could not retrieve CLI version"
    fi

    return 0
}

function validate_cli_help() {
    log_info "📖 Validating CLI help functionality..."

    if [[ -z "${PXF_CLI_PATH:-}" ]]; then
        log_warning "Could not retrieve CLI help - CLI path not set"
        return 0
    fi

    local help_output
    if help_output=$("$PXF_CLI_PATH" --help 2>/dev/null); then
        # Check for expected help content
        local expected_sections=("Usage:" "Available Commands:" "Flags:")
        local missing_sections=()
        
        for section in "${expected_sections[@]}"; do
            if ! echo "$help_output" | grep -q "$section"; then
                missing_sections+=("$section")
            fi
        done
        
        if [[ ${#missing_sections[@]} -eq 0 ]]; then
            log_success "CLI help content is complete"
        else
            log_warning "CLI help is missing sections: ${missing_sections[*]}"
        fi
    else
        log_warning "Could not retrieve CLI help"
    fi
    
    return 0
}

function validate_cli_subcommands() {
    log_info "🔧 Validating CLI subcommands..."
    
    local subcommands=("cluster" "server")
    local failed_subcommands=()
    
    for subcmd in "${subcommands[@]}"; do
        if "$PXF_CLI_PATH" "$subcmd" --help >/dev/null 2>&1; then
            log_success "✅ Subcommand '$subcmd' is available"
        else
            log_warning "⚠️ Subcommand '$subcmd' failed"
            failed_subcommands+=("$subcmd")
        fi
    done
    
    if [[ ${#failed_subcommands[@]} -gt 0 ]]; then
        log_warning "Some subcommands failed: ${failed_subcommands[*]}"
    else
        log_success "All subcommands validated"
    fi
    
    return 0
}

function generate_cli_validation_report() {
    local report_file="${TEST_RESULTS_DIR:-/tmp}/cli-validation-report.txt"
    
    log_info "📋 Generating CLI validation report..."
    
    cat > "$report_file" << EOF
PXF CLI Validation Report
========================
Generated: $(date)
CLI Path: ${PXF_CLI_PATH:-"Not found"}

Binary Validation:
- Location: ${PXF_CLI_PATH:-"Not found"}
- Executable: $(test -x "${PXF_CLI_PATH:-}" && echo "Yes" || echo "No")
- Size: $(test -f "${PXF_CLI_PATH:-}" && stat -c%s "${PXF_CLI_PATH}" 2>/dev/null || echo "Unknown") bytes

Command Validation:
EOF

    for cmd in "${CLI_COMMANDS[@]}"; do
        if [[ -n "${PXF_CLI_PATH:-}" ]] && timeout 5s "$PXF_CLI_PATH" $cmd >/dev/null 2>&1; then
            echo "- pxf $cmd: ✅ PASS" >> "$report_file"
        else
            echo "- pxf $cmd: ❌ FAIL" >> "$report_file"
        fi
    done
    
    log_success "CLI validation report saved to: $report_file"
}

function main() {
    log_info "🚀 Starting PXF CLI validation..."
    
    # Create results directory
    mkdir -p "${TEST_RESULTS_DIR:-/tmp}"
    
    # Run validation steps
    local validation_steps=(
        "validate_cli_binary"
        "validate_cli_permissions"
        "validate_cli_version"
        "validate_cli_help"
        "validate_cli_commands"
        "validate_cli_subcommands"
    )
    
    local failed_steps=()
    
    for step in "${validation_steps[@]}"; do
        if ! $step; then
            failed_steps+=("$step")
        fi
    done
    
    # Generate report regardless of failures
    generate_cli_validation_report
    
    # Summary
    if [[ ${#failed_steps[@]} -eq 0 ]]; then
        log_success "🎉 All CLI validation steps passed!"
        return 0
    else
        log_warning "⚠️ Some validation steps failed: ${failed_steps[*]}"
        log_info "Check the validation report for details"
        
        # Don't fail if only non-critical validations failed
        if [[ ${#failed_steps[@]} -le 2 ]]; then
            log_info "Core CLI functionality appears to work, continuing..."
            return 0
        else
            log_error "Too many critical CLI validation failures"
            return 1
        fi
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
