#!/bin/bash
# diagnose-test-failure.sh - Enhanced test failure diagnosis
# Inspired by Concourse's comprehensive error handling

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-functions.sh"

# Diagnosis configuration
DIAGNOSIS_DIR="${TEST_RESULTS_DIR:-/tmp}/diagnosis"
MAX_LOG_SIZE="10M"
COLLECT_SYSTEM_INFO="${COLLECT_SYSTEM_INFO:-true}"
COLLECT_DOCKER_INFO="${COLLECT_DOCKER_INFO:-true}"

function create_diagnosis_structure() {
    log_info "📁 Creating diagnosis directory structure..."
    
    local dirs=(
        "$DIAGNOSIS_DIR/system"
        "$DIAGNOSIS_DIR/logs/pxf"
        "$DIAGNOSIS_DIR/logs/hadoop"
        "$DIAGNOSIS_DIR/logs/cloudberry"
        "$DIAGNOSIS_DIR/configs"
        "$DIAGNOSIS_DIR/docker"
        "$DIAGNOSIS_DIR/network"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    log_success "Diagnosis directory structure created"
}

function collect_system_info() {
    if [[ "$COLLECT_SYSTEM_INFO" != "true" ]]; then
        log_info "⏭️ Skipping system info collection"
        return 0
    fi
    
    log_info "🖥️ Collecting system information..."
    
    local system_dir="$DIAGNOSIS_DIR/system"
    
    # Basic system information
    {
        echo "=== System Information ==="
        uname -a
        echo
        echo "=== OS Release ==="
        cat /etc/os-release 2>/dev/null || echo "OS release info not available"
        echo
        echo "=== Uptime ==="
        uptime
        echo
        echo "=== Date ==="
        date
    } > "$system_dir/basic_info.txt"
    
    # Resource usage
    {
        echo "=== Disk Usage ==="
        df -h
        echo
        echo "=== Memory Usage ==="
        free -h
        echo
        echo "=== CPU Information ==="
        lscpu 2>/dev/null || echo "CPU info not available"
    } > "$system_dir/resources.txt"
    
    # Process information
    {
        echo "=== Running Processes ==="
        ps aux --sort=-%cpu | head -20
        echo
        echo "=== Java Processes ==="
        ps aux | grep java | grep -v grep || echo "No Java processes found"
        echo
        echo "=== PXF Processes ==="
        ps aux | grep pxf | grep -v grep || echo "No PXF processes found"
    } > "$system_dir/processes.txt"
    
    # Environment variables
    {
        echo "=== Environment Variables ==="
        env | sort
    } > "$system_dir/environment.txt"
    
    log_success "System information collected"
}

function collect_network_info() {
    log_info "🌐 Collecting network information..."
    
    local network_dir="$DIAGNOSIS_DIR/network"
    
    # Network connections
    {
        echo "=== Network Connections ==="
        netstat -tlpn 2>/dev/null || ss -tlpn 2>/dev/null || echo "Network info not available"
        echo
        echo "=== Listening Ports ==="
        netstat -ln 2>/dev/null | grep LISTEN || ss -ln 2>/dev/null | grep LISTEN || echo "Port info not available"
    } > "$network_dir/connections.txt"
    
    # DNS and connectivity
    {
        echo "=== DNS Resolution ==="
        nslookup localhost 2>/dev/null || echo "DNS lookup not available"
        echo
        echo "=== Localhost Connectivity ==="
        ping -c 3 localhost 2>/dev/null || echo "Ping not available"
    } > "$network_dir/connectivity.txt"
    
    log_success "Network information collected"
}

function collect_docker_info() {
    if [[ "$COLLECT_DOCKER_INFO" != "true" ]]; then
        log_info "⏭️ Skipping Docker info collection"
        return 0
    fi
    
    if ! command -v docker >/dev/null 2>&1; then
        log_info "Docker not available, skipping Docker info collection"
        return 0
    fi
    
    log_info "🐳 Collecting Docker information..."
    
    local docker_dir="$DIAGNOSIS_DIR/docker"
    
    # Docker system info
    {
        echo "=== Docker Version ==="
        docker version 2>/dev/null || echo "Docker version not available"
        echo
        echo "=== Docker System Info ==="
        docker system info 2>/dev/null || echo "Docker system info not available"
    } > "$docker_dir/system.txt"
    
    # Container information
    {
        echo "=== Running Containers ==="
        docker ps -a 2>/dev/null || echo "Container list not available"
        echo
        echo "=== Container Stats ==="
        docker stats --no-stream 2>/dev/null || echo "Container stats not available"
    } > "$docker_dir/containers.txt"
    
    # Docker logs for PXF-related containers
    local pxf_containers
    if pxf_containers=$(docker ps -q --filter "name=pxf" 2>/dev/null); then
        for container in $pxf_containers; do
            local container_name
            container_name=$(docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's/^\//')
            log_info "Collecting logs for container: $container_name"
            
            docker logs --tail=1000 "$container" > "$docker_dir/${container_name}_logs.txt" 2>&1 || \
                echo "Failed to collect logs for $container_name" > "$docker_dir/${container_name}_logs.txt"
        done
    fi
    
    log_success "Docker information collected"
}

function collect_pxf_logs() {
    log_info "📋 Collecting PXF logs..."
    
    local pxf_log_dir="$DIAGNOSIS_DIR/logs/pxf"
    local pxf_home="${PXF_HOME:-/usr/local/pxf}"
    
    # PXF server logs
    if [[ -d "$pxf_home/logs" ]]; then
        find "$pxf_home/logs" -name "*.log" -type f | while read -r logfile; do
            local basename
            basename=$(basename "$logfile")
            log_info "Collecting PXF log: $basename"
            
            # Limit log size to avoid huge files
            tail -c "$MAX_LOG_SIZE" "$logfile" > "$pxf_log_dir/$basename" 2>/dev/null || \
                echo "Failed to collect $logfile" > "$pxf_log_dir/$basename"
        done
    else
        echo "PXF logs directory not found: $pxf_home/logs" > "$pxf_log_dir/missing_logs.txt"
    fi
    
    # PXF configuration
    if [[ -d "$pxf_home/conf" ]]; then
        cp -r "$pxf_home/conf" "$DIAGNOSIS_DIR/configs/pxf_conf" 2>/dev/null || \
            echo "Failed to copy PXF configuration" > "$DIAGNOSIS_DIR/configs/pxf_conf_error.txt"
    fi
    
    log_success "PXF logs collected"
}

function collect_hadoop_logs() {
    log_info "🐘 Collecting Hadoop logs..."
    
    local hadoop_log_dir="$DIAGNOSIS_DIR/logs/hadoop"
    local hadoop_home="${HADOOP_HOME:-/workspace/hadoop-3.3.4}"
    
    # Hadoop logs
    if [[ -d "$hadoop_home/logs" ]]; then
        find "$hadoop_home/logs" -name "*.log" -type f | head -10 | while read -r logfile; do
            local basename
            basename=$(basename "$logfile")
            log_info "Collecting Hadoop log: $basename"
            
            tail -c "$MAX_LOG_SIZE" "$logfile" > "$hadoop_log_dir/$basename" 2>/dev/null || \
                echo "Failed to collect $logfile" > "$hadoop_log_dir/$basename"
        done
    else
        echo "Hadoop logs directory not found: $hadoop_home/logs" > "$hadoop_log_dir/missing_logs.txt"
    fi
    
    # Hadoop configuration
    if [[ -d "$hadoop_home/etc/hadoop" ]]; then
        cp -r "$hadoop_home/etc/hadoop" "$DIAGNOSIS_DIR/configs/hadoop_conf" 2>/dev/null || \
            echo "Failed to copy Hadoop configuration" > "$DIAGNOSIS_DIR/configs/hadoop_conf_error.txt"
    fi
    
    log_success "Hadoop logs collected"
}

function collect_cloudberry_logs() {
    log_info "🍃 Collecting Cloudberry logs..."
    
    local cb_log_dir="$DIAGNOSIS_DIR/logs/cloudberry"
    local gphome="${GPHOME:-/usr/local/cloudberry-db}"
    
    # Cloudberry logs
    local log_locations=(
        "/tmp/gpdemo/coordinator.log"
        "/tmp/gpdemo/datadirs/coordinator/log"
        "$gphome/log"
    )
    
    for location in "${log_locations[@]}"; do
        if [[ -f "$location" ]]; then
            local basename
            basename=$(basename "$location")
            tail -c "$MAX_LOG_SIZE" "$location" > "$cb_log_dir/$basename" 2>/dev/null
        elif [[ -d "$location" ]]; then
            find "$location" -name "*.log" -type f | head -5 | while read -r logfile; do
                local basename
                basename=$(basename "$logfile")
                tail -c "$MAX_LOG_SIZE" "$logfile" > "$cb_log_dir/cb_$basename" 2>/dev/null
            done
        fi
    done
    
    log_success "Cloudberry logs collected"
}

function collect_test_artifacts() {
    log_info "🧪 Collecting test artifacts..."
    
    local test_dirs=(
        "/tmp/smoke-test-results"
        "/tmp/integration-test-results"
        "/tmp/hadoop-integration-results"
        "/tmp/automation-test-results"
        "${TEST_RESULTS_DIR:-}"
    )
    
    for test_dir in "${test_dirs[@]}"; do
        if [[ -n "$test_dir" ]] && [[ -d "$test_dir" ]]; then
            local dir_name
            dir_name=$(basename "$test_dir")
            log_info "Collecting test artifacts from: $test_dir"
            
            cp -r "$test_dir" "$DIAGNOSIS_DIR/test_$dir_name" 2>/dev/null || \
                echo "Failed to copy test artifacts from $test_dir" > "$DIAGNOSIS_DIR/test_${dir_name}_error.txt"
        fi
    done
    
    log_success "Test artifacts collected"
}

function analyze_common_issues() {
    log_info "🔍 Analyzing common issues..."
    
    local analysis_file="$DIAGNOSIS_DIR/issue_analysis.txt"
    
    {
        echo "=== Common Issue Analysis ==="
        echo "Generated: $(date)"
        echo
        
        # Check for port conflicts
        echo "=== Port Conflict Analysis ==="
        local pxf_ports=(5888 8080 9000)
        for port in "${pxf_ports[@]}"; do
            if netstat -ln 2>/dev/null | grep ":$port " >/dev/null; then
                echo "⚠️ Port $port is in use"
            else
                echo "✅ Port $port is available"
            fi
        done
        echo
        
        # Check for Java issues
        echo "=== Java Environment Analysis ==="
        if command -v java >/dev/null 2>&1; then
            echo "✅ Java is available: $(java -version 2>&1 | head -1)"
        else
            echo "❌ Java is not available"
        fi
        
        if [[ -n "${JAVA_HOME:-}" ]]; then
            echo "✅ JAVA_HOME is set: $JAVA_HOME"
        else
            echo "⚠️ JAVA_HOME is not set"
        fi
        echo
        
        # Check for disk space
        echo "=== Disk Space Analysis ==="
        local disk_usage
        disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
        if [[ $disk_usage -gt 90 ]]; then
            echo "❌ Disk usage is critical: ${disk_usage}%"
        elif [[ $disk_usage -gt 80 ]]; then
            echo "⚠️ Disk usage is high: ${disk_usage}%"
        else
            echo "✅ Disk usage is normal: ${disk_usage}%"
        fi
        echo
        
        # Check for memory issues
        echo "=== Memory Analysis ==="
        local mem_usage
        if mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}'); then
            if [[ $mem_usage -gt 90 ]]; then
                echo "❌ Memory usage is critical: ${mem_usage}%"
            elif [[ $mem_usage -gt 80 ]]; then
                echo "⚠️ Memory usage is high: ${mem_usage}%"
            else
                echo "✅ Memory usage is normal: ${mem_usage}%"
            fi
        else
            echo "⚠️ Could not determine memory usage"
        fi
        
    } > "$analysis_file"
    
    log_success "Issue analysis completed"
}

function generate_diagnosis_report() {
    log_info "📋 Generating comprehensive diagnosis report..."
    
    local report_file="$DIAGNOSIS_DIR/diagnosis_report.txt"
    
    {
        echo "PXF Test Failure Diagnosis Report"
        echo "================================="
        echo "Generated: $(date)"
        echo "Diagnosis Location: $DIAGNOSIS_DIR"
        echo
        
        echo "=== Collected Information ==="
        find "$DIAGNOSIS_DIR" -type f -name "*.txt" | sort | while read -r file; do
            local relative_path
            relative_path=${file#$DIAGNOSIS_DIR/}
            local file_size
            file_size=$(stat -f%z "$file" 2>/dev/null || echo "unknown")
            echo "- $relative_path ($file_size bytes)"
        done
        echo
        
        echo "=== Directory Summary ==="
        du -sh "$DIAGNOSIS_DIR"/* 2>/dev/null | sort -hr
        echo
        
        echo "=== Next Steps ==="
        echo "1. Review the issue_analysis.txt for common problems"
        echo "2. Check system resources and logs"
        echo "3. Examine PXF and Hadoop configurations"
        echo "4. Review test artifacts for specific failures"
        echo "5. Check Docker container logs if applicable"
        
    } > "$report_file"
    
    log_success "Diagnosis report generated: $report_file"
}

function main() {
    local test_type="${1:-general}"
    
    log_info "🚀 Starting test failure diagnosis for: $test_type"
    
    # Create diagnosis structure
    create_diagnosis_structure
    
    # Collect information
    collect_system_info
    collect_network_info
    collect_docker_info
    collect_pxf_logs
    collect_hadoop_logs
    collect_cloudberry_logs
    collect_test_artifacts
    
    # Analyze and report
    analyze_common_issues
    generate_diagnosis_report
    
    log_success "🎉 Diagnosis completed!"
    log_info "Diagnosis results available at: $DIAGNOSIS_DIR"
    log_info "Review the diagnosis_report.txt for a summary"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
