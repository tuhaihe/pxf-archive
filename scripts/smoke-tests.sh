#!/bin/bash
# PXF Smoke Tests - Basic functionality verification
# This script performs comprehensive smoke testing of PXF components

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_RESULTS_DIR="${TEST_RESULTS_DIR:-/tmp/smoke-test-results}"
ALLOW_WARNINGS="${ALLOW_WARNINGS:-true}"

# Create test results directory
mkdir -p "$TEST_RESULTS_DIR"

echo "🧪 Starting PXF smoke tests..."

# Function to log test results
log_test_result() {
    local test_name="$1"
    local status="$2"
    local message="$3"
    
    echo "[$status] $test_name: $message"
    echo "$(date): [$status] $test_name: $message" >> "$TEST_RESULTS_DIR/smoke-test.log"
}

# Function to check if artifacts exist
check_artifacts() {
    echo "📦 Checking build artifacts..."
    
    if ls *.tar.gz >/dev/null 2>&1; then
        log_test_result "ARTIFACTS" "PASS" "Build artifacts found"
        
        # Extract artifacts for testing
        mkdir -p pxf-extracted
        tar -xzf *.tar.gz -C pxf-extracted --strip-components=1
        
        log_test_result "EXTRACTION" "PASS" "Artifacts extracted successfully"
        return 0
    else
        log_test_result "ARTIFACTS" "FAIL" "No build artifacts found"
        return 1
    fi
}

# Function to test PXF CLI functionality
test_cli_functionality() {
    echo "🔧 Testing PXF CLI functionality..."
    
    local cli_paths=(
        "pxf-extracted/bin/pxf"
        "pxf-extracted/pxf/bin/pxf"
        "pxf-extracted/cli/pxf"
    )
    
    local cli_path=""
    for path in "${cli_paths[@]}"; do
        if [ -f "$path" ]; then
            cli_path="$path"
            break
        fi
    done
    
    if [ -z "$cli_path" ]; then
        log_test_result "CLI_BINARY" "FAIL" "PXF CLI binary not found"
        return 1
    fi
    
    chmod +x "$cli_path"
    log_test_result "CLI_BINARY" "PASS" "PXF CLI binary found at $cli_path"
    
    # Test CLI version command
    if "$cli_path" --version 2>/dev/null | grep -q "6.10.1"; then
        log_test_result "CLI_VERSION" "PASS" "CLI version command works correctly"
    else
        log_test_result "CLI_VERSION" "WARN" "CLI version command failed or unexpected version"
        [ "$ALLOW_WARNINGS" = "false" ] && return 1
    fi
    
    # Test CLI help command
    if "$cli_path" --help >/dev/null 2>&1; then
        log_test_result "CLI_HELP" "PASS" "CLI help command works"
    else
        log_test_result "CLI_HELP" "FAIL" "CLI help command failed"
        return 1
    fi
    
    # Test CLI subcommands
    local subcommands=("cluster" "server")
    for cmd in "${subcommands[@]}"; do
        if "$cli_path" "$cmd" --help >/dev/null 2>&1; then
            log_test_result "CLI_SUBCMD_$cmd" "PASS" "CLI $cmd subcommand available"
        else
            log_test_result "CLI_SUBCMD_$cmd" "WARN" "CLI $cmd subcommand not responding"
            [ "$ALLOW_WARNINGS" = "false" ] && return 1
        fi
    done
    
    return 0
}

# Function to test PXF Server JAR
test_server_jar() {
    echo "☕ Testing PXF Server JAR..."
    
    local jar_paths=(
        "pxf-extracted/application"
        "pxf-extracted/pxf/application"
        "pxf-extracted/lib"
        "pxf-extracted/pxf/lib"
    )
    
    local main_jar=""
    for jar_path in "${jar_paths[@]}"; do
        if ls "$jar_path"/pxf-app-*.jar >/dev/null 2>&1; then
            main_jar=$(ls "$jar_path"/pxf-app-*.jar | head -1)
            break
        elif ls "$jar_path"/pxf-service-*.jar >/dev/null 2>&1; then
            main_jar=$(ls "$jar_path"/pxf-service-*.jar | head -1)
            break
        fi
    done
    
    if [ -z "$main_jar" ]; then
        log_test_result "SERVER_JAR" "FAIL" "PXF Server JAR not found"
        return 1
    fi
    
    log_test_result "SERVER_JAR" "PASS" "PXF Server JAR found at $main_jar"
    
    # Test JAR integrity
    if jar tf "$main_jar" | head -5 >/dev/null 2>&1; then
        log_test_result "JAR_INTEGRITY" "PASS" "JAR file is readable and well-formed"
    else
        log_test_result "JAR_INTEGRITY" "FAIL" "JAR file integrity check failed"
        return 1
    fi
    
    # Test for PXF main classes
    if jar tf "$main_jar" | grep -q "org.*pxf.*Application\|org.*pxf.*Main\|org.*pxf.*Service"; then
        log_test_result "JAR_CLASSES" "PASS" "JAR contains PXF application classes"
    else
        log_test_result "JAR_CLASSES" "WARN" "Main application classes not found in expected format"
        [ "$ALLOW_WARNINGS" = "false" ] && return 1
    fi
    
    return 0
}

# Function to test PXF connectors
test_connectors() {
    echo "🔌 Testing PXF connectors..."
    
    local connectors=("hdfs" "hive" "hbase" "jdbc" "json" "s3")
    local connector_count=0
    
    # Check for individual connector JARs
    for connector in "${connectors[@]}"; do
        local found=false
        for lib_path in "pxf-extracted/lib" "pxf-extracted/pxf/lib" "pxf-extracted/pxf/share"; do
            if ls "$lib_path"/pxf-${connector}-*.jar >/dev/null 2>&1; then
                log_test_result "CONNECTOR_$connector" "PASS" "$connector connector found in $lib_path"
                connector_count=$((connector_count + 1))
                found=true
                break
            fi
        done
        
        if [ "$found" = false ]; then
            log_test_result "CONNECTOR_$connector" "INFO" "$connector connector not found as individual JAR (may be embedded)"
        fi
    done
    
    # Check for embedded connectors in main application JAR
    local main_jar=$(find pxf-extracted -name "pxf-app-*.jar" -type f | head -1)
    if [ -n "$main_jar" ]; then
        if jar tf "$main_jar" 2>/dev/null | grep -q "org.*pxf.*hdfs\|org.*pxf.*hive\|org.*pxf.*hbase"; then
            log_test_result "EMBEDDED_CONNECTORS" "PASS" "Connectors found embedded in main application JAR"
            connector_count=$((connector_count + 1))
        fi
    fi
    
    if [ "$connector_count" -gt 0 ]; then
        log_test_result "CONNECTORS_OVERALL" "PASS" "PXF connectors validated (found $connector_count evidence)"
        return 0
    else
        log_test_result "CONNECTORS_OVERALL" "WARN" "No clear connector evidence found"
        [ "$ALLOW_WARNINGS" = "false" ] && return 1
    fi
}

# Function to test configuration
test_configuration() {
    echo "⚙️ Testing PXF configuration..."
    
    local config_paths=(
        "pxf-extracted/conf"
        "pxf-extracted/pxf/conf"
        "pxf-extracted/pxf/templates"
        "pxf-extracted/templates"
    )
    
    local config_found=false
    for config_path in "${config_paths[@]}"; do
        if [ -d "$config_path" ]; then
            log_test_result "CONFIG_DIR" "PASS" "Configuration directory found at $config_path"
            config_found=true
            break
        fi
    done
    
    if [ "$config_found" = false ]; then
        log_test_result "CONFIG_DIR" "WARN" "Configuration directory not found in expected locations"
        [ "$ALLOW_WARNINGS" = "false" ] && return 1
    fi
    
    return 0
}

# Main execution
main() {
    local exit_code=0
    
    # Run all smoke tests
    check_artifacts || exit_code=1
    test_cli_functionality || exit_code=1
    test_server_jar || exit_code=1
    test_connectors || exit_code=1
    test_configuration || exit_code=1
    
    # Generate summary
    echo ""
    echo "📊 Smoke Test Summary:"
    echo "======================"
    
    local pass_count=$(grep -c "\[PASS\]" "$TEST_RESULTS_DIR/smoke-test.log" || echo "0")
    local fail_count=$(grep -c "\[FAIL\]" "$TEST_RESULTS_DIR/smoke-test.log" || echo "0")
    local warn_count=$(grep -c "\[WARN\]" "$TEST_RESULTS_DIR/smoke-test.log" || echo "0")
    
    echo "✅ Passed: $pass_count"
    echo "❌ Failed: $fail_count"
    echo "⚠️  Warnings: $warn_count"
    
    if [ "$exit_code" -eq 0 ]; then
        echo "🎉 All smoke tests completed successfully!"
    else
        echo "💥 Some smoke tests failed. Check logs for details."
    fi
    
    return $exit_code
}

# Execute main function
main "$@"
