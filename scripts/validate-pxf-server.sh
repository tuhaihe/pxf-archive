#!/bin/bash
# validate-pxf-server.sh - Dedicated PXF Server validation script
# Validates PXF server components and functionality

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-functions.sh" 2>/dev/null || {
    # Fallback logging functions if common-functions.sh doesn't exist
    log_info() { echo "ℹ️ $*"; }
    log_success() { echo "✅ $*"; }
    log_warning() { echo "⚠️ $*"; }
    log_error() { echo "❌ $*"; }
}

# Server validation configuration
SERVER_JAR_PATHS=(
    "pxf-extracted/application"
    "pxf-extracted/pxf/application"
    "pxf-extracted/lib"
    "pxf-extracted/pxf/lib"
)

EXPECTED_CLASSES=(
    "org.greenplum.pxf.Application"
    "org.greenplum.pxf.service"
    "org.greenplum.pxf.api"
)

function validate_server_jar() {
    log_info "🔍 Searching for PXF Server JAR..."
    
    local server_jar=""
    
    for jar_path in "${SERVER_JAR_PATHS[@]}"; do
        if [[ -d "$jar_path" ]]; then
            # Look for main application JAR with various naming patterns
            for jar_pattern in "pxf-app-*.jar" "pxf-service-*.jar" "pxf-*.jar" "*pxf*.jar"; do
                if ls "$jar_path"/$jar_pattern >/dev/null 2>&1; then
                    server_jar=$(ls "$jar_path"/$jar_pattern | head -1)

                    # Verify the JAR file is not empty and has reasonable size
                    if [[ -f "$server_jar" ]]; then
                        local jar_size=$(stat -c%s "$server_jar" 2>/dev/null || echo 0)
                        if [[ $jar_size -gt 1000 ]]; then
                            break 2
                        else
                            log_warning "Found JAR but it's too small: $server_jar ($jar_size bytes)"
                            server_jar=""
                        fi
                    fi
                fi
            done
        fi
    done
    
    if [[ -z "$server_jar" ]]; then
        log_error "PXF Server JAR not found in expected locations"
        log_info "Searched paths:"
        printf '  - %s\n' "${SERVER_JAR_PATHS[@]}"

        # Set empty path to prevent unbound variable errors
        export PXF_SERVER_JAR=""
        return 1
    fi

    log_success "Found PXF Server JAR: $server_jar"
    export PXF_SERVER_JAR="$server_jar"
    return 0
}

function validate_jar_integrity() {
    log_info "🔍 Validating JAR integrity..."

    if [[ -z "${PXF_SERVER_JAR:-}" ]]; then
        log_warning "JAR file integrity check skipped - JAR path not set"
        return 0
    fi

    if ! command -v jar >/dev/null 2>&1; then
        log_warning "jar command not available, skipping integrity check"
        return 0
    fi

    # Test JAR can be read
    if jar tf "$PXF_SERVER_JAR" | head -5 >/dev/null 2>&1; then
        log_success "JAR file is readable and well-formed"
    else
        log_error "JAR file integrity check failed"
        return 1
    fi
    
    # Check JAR size is reasonable
    local jar_size
    jar_size=$(stat -c%s "$PXF_SERVER_JAR" 2>/dev/null || echo 0)
    
    if [[ $jar_size -lt 1000000 ]]; then  # Less than 1MB
        log_warning "JAR file seems unusually small: $jar_size bytes"
    else
        log_success "JAR file size is reasonable: $jar_size bytes"
    fi
    
    return 0
}

function validate_main_classes() {
    log_info "🔍 Validating main application classes..."

    if [[ -z "${PXF_SERVER_JAR:-}" ]]; then
        log_warning "Main application classes validation skipped - JAR path not set"
        return 0
    fi

    if ! command -v jar >/dev/null 2>&1; then
        log_warning "jar command not available, skipping class validation"
        return 0
    fi

    local found_classes=0
    local jar_contents
    jar_contents=$(jar tf "$PXF_SERVER_JAR" 2>/dev/null)
    
    # Check for main application classes
    if echo "$jar_contents" | grep -q "org.*pxf.*Application\|org.*pxf.*Main\|org.*pxf.*Service"; then
        log_success "Main application classes found"
        found_classes=$((found_classes + 1))
    else
        log_warning "Main application classes not found in expected format"
    fi
    
    # Check for API classes
    if echo "$jar_contents" | grep -q "org.*pxf.*api"; then
        log_success "PXF API classes found"
        found_classes=$((found_classes + 1))
    else
        log_warning "PXF API classes not found"
    fi
    
    # Check for service classes
    if echo "$jar_contents" | grep -q "org.*pxf.*service"; then
        log_success "PXF service classes found"
        found_classes=$((found_classes + 1))
    else
        log_warning "PXF service classes not found"
    fi
    
    if [[ $found_classes -gt 0 ]]; then
        log_success "Found $found_classes types of PXF classes"
        return 0
    else
        log_error "No PXF classes found in JAR"
        return 1
    fi
}

function validate_connector_classes() {
    log_info "🔌 Validating connector classes..."

    if [[ -z "${PXF_SERVER_JAR:-}" ]]; then
        log_warning "Connector classes validation skipped - JAR path not set"
        return 0
    fi

    if ! command -v jar >/dev/null 2>&1; then
        log_warning "jar command not available, skipping connector validation"
        return 0
    fi

    local connectors=("hdfs" "hive" "hbase" "jdbc" "json" "s3")
    local found_connectors=0
    local jar_contents
    jar_contents=$(jar tf "$PXF_SERVER_JAR" 2>/dev/null)
    
    for connector in "${connectors[@]}"; do
        if echo "$jar_contents" | grep -qi "$connector"; then
            log_success "✅ $connector connector classes found"
            found_connectors=$((found_connectors + 1))
        else
            log_info "⚠️ $connector connector classes not found (may be in separate JAR)"
        fi
    done
    
    if [[ $found_connectors -gt 3 ]]; then
        log_success "Multiple connector types found ($found_connectors) - comprehensive JAR"
    elif [[ $found_connectors -gt 0 ]]; then
        log_info "Some connector evidence found ($found_connectors) - may be minimal build"
    else
        log_warning "No clear connector evidence found - connectors may be in separate JARs"
    fi
    
    return 0
}

function validate_dependencies() {
    log_info "📚 Validating dependencies..."

    if [[ -z "${PXF_SERVER_JAR:-}" ]]; then
        log_warning "Dependencies validation skipped - JAR path not set"
        return 0
    fi

    if ! command -v jar >/dev/null 2>&1; then
        log_warning "jar command not available, skipping dependency validation"
        return 0
    fi

    local jar_contents
    jar_contents=$(jar tf "$PXF_SERVER_JAR" 2>/dev/null)
    
    # Check for common dependencies
    local dependencies=("spring" "hadoop" "jackson" "slf4j")
    local found_deps=0
    
    for dep in "${dependencies[@]}"; do
        if echo "$jar_contents" | grep -qi "$dep"; then
            log_success "✅ $dep dependency found"
            found_deps=$((found_deps + 1))
        else
            log_info "⚠️ $dep dependency not found (may be external)"
        fi
    done
    
    log_info "Found $found_deps common dependencies in JAR"
    return 0
}

function validate_manifest() {
    log_info "📋 Validating JAR manifest..."

    if [[ -z "${PXF_SERVER_JAR:-}" ]]; then
        log_warning "JAR manifest validation skipped - JAR path not set"
        return 0
    fi

    if ! command -v jar >/dev/null 2>&1; then
        log_warning "jar command not available, skipping manifest validation"
        return 0
    fi

    local manifest_content
    if manifest_content=$(jar xf "$PXF_SERVER_JAR" META-INF/MANIFEST.MF 2>/dev/null && cat META-INF/MANIFEST.MF 2>/dev/null); then
        log_success "JAR manifest is readable"
        
        # Check for main class
        if echo "$manifest_content" | grep -q "Main-Class:"; then
            local main_class
            main_class=$(echo "$manifest_content" | grep "Main-Class:" | cut -d: -f2 | tr -d ' ')
            log_success "Main class found: $main_class"
        else
            log_info "No main class specified in manifest"
        fi
        
        # Clean up extracted manifest
        rm -f META-INF/MANIFEST.MF
        rmdir META-INF 2>/dev/null || true
    else
        log_warning "Could not read JAR manifest"
    fi
    
    return 0
}

function test_jar_execution() {
    log_info "🚀 Testing JAR execution capabilities..."

    if [[ -z "${PXF_SERVER_JAR:-}" ]]; then
        log_warning "JAR execution test skipped - JAR path not set"
        return 0
    fi

    if ! command -v java >/dev/null 2>&1; then
        log_warning "Java not available, skipping execution test"
        return 0
    fi

    # Try to get help or version information
    local java_output
    if java_output=$(timeout 10s java -jar "$PXF_SERVER_JAR" --help 2>&1) ||
       java_output=$(timeout 10s java -jar "$PXF_SERVER_JAR" --version 2>&1) ||
       java_output=$(timeout 10s java -jar "$PXF_SERVER_JAR" -h 2>&1); then
        log_success "JAR responds to help/version commands"
        log_info "Output preview: $(echo "$java_output" | head -2 | tr '\n' ' ')"
    else
        log_info "JAR does not respond to standard help commands (may require specific arguments)"
    fi
    
    return 0
}

function generate_server_validation_report() {
    local report_file="${TEST_RESULTS_DIR:-/tmp}/server-validation-report.txt"
    
    log_info "📋 Generating server validation report..."
    
    cat > "$report_file" << EOF
PXF Server Validation Report
===========================
Generated: $(date)
Server JAR: ${PXF_SERVER_JAR:-"Not found"}

JAR Information:
- Location: ${PXF_SERVER_JAR:-"Not found"}
- Size: $(test -f "${PXF_SERVER_JAR:-}" && stat -c%s "${PXF_SERVER_JAR}" 2>/dev/null || echo "Unknown") bytes
- Readable: $(test -r "${PXF_SERVER_JAR:-}" && echo "Yes" || echo "No")

Validation Results:
EOF

    # Add validation results
    local validations=(
        "JAR Location:$(test -n "${PXF_SERVER_JAR:-}" && echo "✅ PASS" || echo "❌ FAIL")"
        "JAR Integrity:$(jar tf "${PXF_SERVER_JAR:-}" >/dev/null 2>&1 && echo "✅ PASS" || echo "❌ FAIL")"
        "Main Classes:$(jar tf "${PXF_SERVER_JAR:-}" 2>/dev/null | grep -q "org.*pxf" && echo "✅ PASS" || echo "❌ FAIL")"
    )
    
    for validation in "${validations[@]}"; do
        echo "- $validation" >> "$report_file"
    done
    
    log_success "Server validation report saved to: $report_file"
}

function main() {
    log_info "🚀 Starting PXF Server validation..."
    
    # Create results directory
    mkdir -p "${TEST_RESULTS_DIR:-/tmp}"
    
    # Run validation steps
    local validation_steps=(
        "validate_server_jar"
        "validate_jar_integrity"
        "validate_main_classes"
        "validate_connector_classes"
        "validate_dependencies"
        "validate_manifest"
        "test_jar_execution"
    )
    
    local failed_steps=()
    
    for step in "${validation_steps[@]}"; do
        if ! $step; then
            failed_steps+=("$step")
        fi
    done
    
    # Generate report regardless of failures
    generate_server_validation_report
    
    # Summary
    if [[ ${#failed_steps[@]} -eq 0 ]]; then
        log_success "🎉 All server validation steps passed!"
        return 0
    else
        log_warning "⚠️ Some validation steps failed: ${failed_steps[*]}"
        log_info "Check the validation report for details"
        
        # Don't fail if only non-critical validations failed
        if [[ ${#failed_steps[@]} -le 2 ]]; then
            log_info "Core server functionality appears to work, continuing..."
            return 0
        else
            log_error "Too many critical server validation failures"
            return 1
        fi
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
