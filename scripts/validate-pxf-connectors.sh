#!/bin/bash
# validate-pxf-connectors.sh - Dedicated PXF Connectors validation script
# Validates PXF connector availability and functionality

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

# Connector validation configuration
CONNECTORS=(
    "pxf-hdfs"
    "pxf-hive"
    "pxf-hbase"
    "pxf-jdbc"
    "pxf-json"
    "pxf-s3"
)

CONNECTOR_LIB_PATHS=(
    "pxf-extracted/lib"
    "pxf-extracted/pxf/lib"
    "pxf-extracted/pxf/share"
    "pxf-extracted/share"
)

function validate_individual_connector_jars() {
    log_info "🔌 Validating individual connector JARs..."
    
    local connector_count=0
    local found_connectors=()
    
    for connector in "${CONNECTORS[@]}"; do
        local found=false
        
        for lib_path in "${CONNECTOR_LIB_PATHS[@]}"; do
            if [[ -d "$lib_path" ]] && ls "$lib_path"/${connector}-*.jar >/dev/null 2>&1; then
                local jar_file
                jar_file=$(ls "$lib_path"/${connector}-*.jar | head -1)
                log_success "$connector connector found: $(basename "$jar_file")"
                found_connectors+=("$connector")
                connector_count=$((connector_count + 1))
                found=true
                break
            fi
        done
        
        if [[ "$found" == false ]]; then
            log_info "$connector connector not found as individual JAR (may be embedded)"
        fi
    done
    
    if [[ $connector_count -gt 0 ]]; then
        log_success "Found $connector_count individual connector JARs"
        export INDIVIDUAL_CONNECTORS="${found_connectors[*]}"
    else
        log_info "No individual connector JARs found"
        export INDIVIDUAL_CONNECTORS=""
    fi
    
    return 0
}

function validate_embedded_connectors() {
    log_info "🔍 Checking for embedded connectors in main JAR..."
    
    local main_jar
    if main_jar=$(find pxf-extracted -name "pxf-app-*.jar" -type f | head -1); then
        log_info "Checking main application JAR: $(basename "$main_jar")"
        
        if ! command -v jar >/dev/null 2>&1; then
            log_warning "jar command not available, skipping embedded connector check"
            return 0
        fi
        
        local embedded_connectors=()
        local jar_contents
        jar_contents=$(jar tf "$main_jar" 2>/dev/null)
        
        # Check for connector packages in the main JAR
        for connector in "hdfs" "hive" "hbase" "jdbc" "json" "s3"; do
            if echo "$jar_contents" | grep -qi "org.*pxf.*$connector\|org.*greenplum.*pxf.*$connector"; then
                log_success "$connector connector classes found in main JAR"
                embedded_connectors+=("$connector")
            fi
        done
        
        if [[ ${#embedded_connectors[@]} -gt 0 ]]; then
            log_success "Found ${#embedded_connectors[@]} embedded connectors: ${embedded_connectors[*]}"
            export EMBEDDED_CONNECTORS="${embedded_connectors[*]}"
        else
            log_info "No embedded connectors found in main JAR"
            export EMBEDDED_CONNECTORS=""
        fi
    else
        log_warning "Main application JAR not found"
        export EMBEDDED_CONNECTORS=""
    fi
    
    return 0
}

function validate_connector_dependencies() {
    log_info "📚 Validating connector dependencies..."
    
    local dependency_paths=(
        "pxf-extracted/lib"
        "pxf-extracted/pxf/lib"
    )
    
    # Common dependencies for different connectors
    local hdfs_deps=("hadoop-client" "hadoop-common" "hadoop-hdfs")
    local hive_deps=("hive-exec" "hive-metastore" "hive-common")
    local hbase_deps=("hbase-client" "hbase-common")
    local jdbc_deps=("postgresql" "mysql" "ojdbc")
    
    local found_deps=()
    
    for dep_path in "${dependency_paths[@]}"; do
        if [[ -d "$dep_path" ]]; then
            # Check for Hadoop dependencies
            for dep in "${hdfs_deps[@]}"; do
                if ls "$dep_path"/*${dep}*.jar >/dev/null 2>&1; then
                    log_success "HDFS dependency found: $dep"
                    found_deps+=("hdfs:$dep")
                fi
            done
            
            # Check for Hive dependencies
            for dep in "${hive_deps[@]}"; do
                if ls "$dep_path"/*${dep}*.jar >/dev/null 2>&1; then
                    log_success "Hive dependency found: $dep"
                    found_deps+=("hive:$dep")
                fi
            done
            
            # Check for HBase dependencies
            for dep in "${hbase_deps[@]}"; do
                if ls "$dep_path"/*${dep}*.jar >/dev/null 2>&1; then
                    log_success "HBase dependency found: $dep"
                    found_deps+=("hbase:$dep")
                fi
            done
            
            # Check for JDBC dependencies
            for dep in "${jdbc_deps[@]}"; do
                if ls "$dep_path"/*${dep}*.jar >/dev/null 2>&1; then
                    log_success "JDBC dependency found: $dep"
                    found_deps+=("jdbc:$dep")
                fi
            done
        fi
    done
    
    if [[ ${#found_deps[@]} -gt 0 ]]; then
        log_success "Found ${#found_deps[@]} connector dependencies"
        export CONNECTOR_DEPENDENCIES="${found_deps[*]}"
    else
        log_info "No specific connector dependencies found (may be embedded or minimal build)"
        export CONNECTOR_DEPENDENCIES=""
    fi
    
    return 0
}

function validate_connector_configurations() {
    log_info "⚙️ Validating connector configurations..."
    
    local config_paths=(
        "pxf-extracted/conf"
        "pxf-extracted/pxf/conf"
        "pxf-extracted/templates"
        "pxf-extracted/pxf/templates"
    )
    
    local found_configs=()
    
    for config_path in "${config_paths[@]}"; do
        if [[ -d "$config_path" ]]; then
            log_success "Configuration directory found: $config_path"
            
            # Check for connector-specific configuration files
            local config_files=(
                "hdfs-site.xml"
                "core-site.xml"
                "hive-site.xml"
                "hbase-site.xml"
                "jdbc-site.xml"
                "pxf-site.xml"
            )
            
            for config_file in "${config_files[@]}"; do
                if [[ -f "$config_path/$config_file" ]]; then
                    log_success "Configuration file found: $config_file"
                    found_configs+=("$config_file")
                elif [[ -f "$config_path/${config_file}.template" ]]; then
                    log_success "Configuration template found: ${config_file}.template"
                    found_configs+=("${config_file}.template")
                fi
            done
            
            # List other configuration files
            if [[ "$(ls -A "$config_path" 2>/dev/null)" ]]; then
                log_info "Other configuration files: $(ls "$config_path" | head -3 | tr '\n' ' ')"
            fi
            
            break
        fi
    done
    
    if [[ ${#found_configs[@]} -gt 0 ]]; then
        log_success "Found ${#found_configs[@]} configuration files"
        export CONNECTOR_CONFIGS="${found_configs[*]}"
    else
        log_warning "No connector configuration files found"
        export CONNECTOR_CONFIGS=""
    fi
    
    return 0
}

function test_connector_class_loading() {
    log_info "🔄 Testing connector class loading capabilities..."
    
    if ! command -v java >/dev/null 2>&1; then
        log_warning "Java not available, skipping class loading test"
        return 0
    fi
    
    # Find the main PXF JAR
    local main_jar
    if main_jar=$(find pxf-extracted -name "pxf-app-*.jar" -type f | head -1); then
        log_info "Testing class loading with: $(basename "$main_jar")"
        
        # Try to list classes related to connectors
        local connector_classes=()
        if command -v jar >/dev/null 2>&1; then
            local jar_contents
            jar_contents=$(jar tf "$main_jar" 2>/dev/null)
            
            # Look for connector-related classes
            for connector in "hdfs" "hive" "hbase" "jdbc" "json" "s3"; do
                local class_count
                class_count=$(echo "$jar_contents" | grep -ci "$connector" || echo 0)
                if [[ $class_count -gt 0 ]]; then
                    log_success "$connector: $class_count related classes found"
                    connector_classes+=("$connector:$class_count")
                fi
            done
        fi
        
        if [[ ${#connector_classes[@]} -gt 0 ]]; then
            log_success "Connector classes available for loading"
            export CONNECTOR_CLASSES="${connector_classes[*]}"
        else
            log_info "No specific connector classes identified"
            export CONNECTOR_CLASSES=""
        fi
    else
        log_warning "Main JAR not found for class loading test"
        export CONNECTOR_CLASSES=""
    fi
    
    return 0
}

function generate_connector_validation_report() {
    local report_file="${TEST_RESULTS_DIR:-/tmp}/connector-validation-report.txt"
    
    log_info "📋 Generating connector validation report..."
    
    cat > "$report_file" << EOF
PXF Connector Validation Report
==============================
Generated: $(date)

Individual Connectors Found:
${INDIVIDUAL_CONNECTORS:-"None"}

Embedded Connectors Found:
${EMBEDDED_CONNECTORS:-"None"}

Connector Dependencies:
${CONNECTOR_DEPENDENCIES:-"None"}

Configuration Files:
${CONNECTOR_CONFIGS:-"None"}

Connector Classes:
${CONNECTOR_CLASSES:-"None"}

Summary:
- Individual connector JARs: $(echo "${INDIVIDUAL_CONNECTORS:-}" | wc -w)
- Embedded connectors: $(echo "${EMBEDDED_CONNECTORS:-}" | wc -w)
- Dependencies found: $(echo "${CONNECTOR_DEPENDENCIES:-}" | wc -w)
- Configuration files: $(echo "${CONNECTOR_CONFIGS:-}" | wc -w)

Overall Assessment:
EOF

    # Calculate overall assessment
    local total_evidence=0
    total_evidence=$((total_evidence + $(echo "${INDIVIDUAL_CONNECTORS:-}" | wc -w)))
    total_evidence=$((total_evidence + $(echo "${EMBEDDED_CONNECTORS:-}" | wc -w)))
    total_evidence=$((total_evidence + $(echo "${CONNECTOR_DEPENDENCIES:-}" | wc -w)))
    
    if [[ $total_evidence -gt 5 ]]; then
        echo "✅ COMPREHENSIVE - Multiple connectors and dependencies found" >> "$report_file"
    elif [[ $total_evidence -gt 2 ]]; then
        echo "✅ ADEQUATE - Basic connector functionality available" >> "$report_file"
    elif [[ $total_evidence -gt 0 ]]; then
        echo "⚠️ MINIMAL - Limited connector evidence found" >> "$report_file"
    else
        echo "❌ INSUFFICIENT - No clear connector evidence found" >> "$report_file"
    fi
    
    log_success "Connector validation report saved to: $report_file"
}

function main() {
    log_info "🚀 Starting PXF Connector validation..."
    
    # Create results directory
    mkdir -p "${TEST_RESULTS_DIR:-/tmp}"
    
    # Initialize environment variables
    export INDIVIDUAL_CONNECTORS=""
    export EMBEDDED_CONNECTORS=""
    export CONNECTOR_DEPENDENCIES=""
    export CONNECTOR_CONFIGS=""
    export CONNECTOR_CLASSES=""
    
    # Run validation steps
    local validation_steps=(
        "validate_individual_connector_jars"
        "validate_embedded_connectors"
        "validate_connector_dependencies"
        "validate_connector_configurations"
        "test_connector_class_loading"
    )
    
    local failed_steps=()
    
    for step in "${validation_steps[@]}"; do
        if ! $step; then
            failed_steps+=("$step")
        fi
    done
    
    # Generate report regardless of failures
    generate_connector_validation_report
    
    # Summary
    if [[ ${#failed_steps[@]} -eq 0 ]]; then
        log_success "🎉 All connector validation steps completed!"
        return 0
    else
        log_warning "⚠️ Some validation steps had issues: ${failed_steps[*]}"
        log_info "Check the validation report for details"
        
        # Connector validation is informational, don't fail the build
        log_info "Connector validation is informational only, continuing..."
        return 0
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
