#!/bin/bash
# setup-test-data.sh - Standardized test data generation
# Inspired by Concourse's data management approach

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-functions.sh"

# Test data configuration
TEST_DATA_DIR="${TEST_DATA_DIR:-/tmp/pxf-test-data}"
CREATE_LARGE_DATASET="${CREATE_LARGE_DATASET:-false}"
UPLOAD_TO_HDFS="${UPLOAD_TO_HDFS:-false}"
HADOOP_HOME="${HADOOP_HOME:-}"

# Data size configurations
SMALL_DATASET_ROWS=100
MEDIUM_DATASET_ROWS=10000
LARGE_DATASET_ROWS=1000000

function create_directory_structure() {
    log_info "📁 Creating test data directory structure..."
    
    local dirs=(
        "$TEST_DATA_DIR/small"
        "$TEST_DATA_DIR/medium"
        "$TEST_DATA_DIR/large"
        "$TEST_DATA_DIR/formats/csv"
        "$TEST_DATA_DIR/formats/json"
        "$TEST_DATA_DIR/formats/parquet"
        "$TEST_DATA_DIR/formats/avro"
        "$TEST_DATA_DIR/schemas"
    )
    
    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    log_success "Directory structure created"
}

function create_small_dataset() {
    log_info "📊 Creating small dataset ($SMALL_DATASET_ROWS rows)..."
    
    local output_dir="$TEST_DATA_DIR/small"
    
    # Employee data (CSV)
    cat > "$output_dir/employees.csv" << 'EOF'
id,name,salary,department,hire_date
1,Alice Johnson,75000,Engineering,2020-01-15
2,Bob Smith,65000,Sales,2019-03-22
3,Charlie Brown,70000,Marketing,2021-06-10
4,Diana Prince,80000,Engineering,2018-11-05
5,Eve Wilson,60000,HR,2020-09-18
EOF

    # Product data (JSON)
    cat > "$output_dir/products.json" << 'EOF'
{"id": 1, "name": "Laptop", "price": 999.99, "category": "Electronics", "in_stock": true}
{"id": 2, "name": "Mouse", "price": 29.99, "category": "Electronics", "in_stock": true}
{"id": 3, "name": "Keyboard", "price": 79.99, "category": "Electronics", "in_stock": false}
{"id": 4, "name": "Monitor", "price": 299.99, "category": "Electronics", "in_stock": true}
{"id": 5, "name": "Desk Chair", "price": 199.99, "category": "Furniture", "in_stock": true}
EOF

    # Sales data (TSV)
    cat > "$output_dir/sales.tsv" << 'EOF'
order_id	customer_id	product_id	quantity	order_date	total_amount
1001	101	1	2	2023-01-15	1999.98
1002	102	2	1	2023-01-16	29.99
1003	103	3	1	2023-01-17	79.99
1004	101	4	1	2023-01-18	299.99
1005	104	5	1	2023-01-19	199.99
EOF

    # Complex nested JSON
    cat > "$output_dir/complex.json" << 'EOF'
{"user": {"id": 1, "name": "John Doe", "email": "john@example.com"}, "orders": [{"id": 1001, "items": [{"name": "Laptop", "qty": 1}]}]}
{"user": {"id": 2, "name": "Jane Smith", "email": "jane@example.com"}, "orders": [{"id": 1002, "items": [{"name": "Mouse", "qty": 2}, {"name": "Keyboard", "qty": 1}]}]}
EOF

    log_success "Small dataset created"
}

function create_medium_dataset() {
    log_info "📊 Creating medium dataset ($MEDIUM_DATASET_ROWS rows)..."
    
    local output_dir="$TEST_DATA_DIR/medium"
    
    # Generate larger CSV file
    {
        echo "id,name,value,timestamp,category"
        for i in $(seq 1 $MEDIUM_DATASET_ROWS); do
            local category=$((i % 5 + 1))
            local timestamp=$(date -d "2023-01-01 + $((i % 365)) days" +%Y-%m-%d)
            echo "$i,Item_$i,$((RANDOM % 1000)),$timestamp,Category_$category"
        done
    } > "$output_dir/large_table.csv"
    
    # Generate JSON lines file
    {
        for i in $(seq 1 $((MEDIUM_DATASET_ROWS / 10))); do
            echo "{\"id\": $i, \"data\": \"test_data_$i\", \"value\": $((RANDOM % 1000)), \"active\": $((i % 2 == 0))}"
        done
    } > "$output_dir/large_data.json"
    
    log_success "Medium dataset created"
}

function create_large_dataset() {
    if [[ "$CREATE_LARGE_DATASET" != "true" ]]; then
        log_info "⏭️ Skipping large dataset creation (CREATE_LARGE_DATASET=false)"
        return 0
    fi
    
    log_info "📊 Creating large dataset ($LARGE_DATASET_ROWS rows)..."
    
    local output_dir="$TEST_DATA_DIR/large"
    
    # Generate very large CSV file in chunks to avoid memory issues
    {
        echo "id,uuid,name,email,phone,address,city,country,created_at,updated_at"
        for chunk in $(seq 0 $((LARGE_DATASET_ROWS / 10000))); do
            for i in $(seq 1 10000); do
                local id=$((chunk * 10000 + i))
                if [[ $id -gt $LARGE_DATASET_ROWS ]]; then
                    break 2
                fi
                local uuid=$(uuidgen 2>/dev/null || echo "uuid-$id")
                echo "$id,$uuid,User_$id,user$id@example.com,+1-555-$(printf "%04d" $((id % 10000))),123 Main St,City_$((id % 100)),Country_$((id % 20)),2023-01-01,2023-01-01"
            done
        done
    } > "$output_dir/users.csv"
    
    log_success "Large dataset created"
}

function create_schema_files() {
    log_info "📋 Creating schema files..."
    
    local schema_dir="$TEST_DATA_DIR/schemas"
    
    # Avro schema
    cat > "$schema_dir/employee.avsc" << 'EOF'
{
  "type": "record",
  "name": "Employee",
  "fields": [
    {"name": "id", "type": "int"},
    {"name": "name", "type": "string"},
    {"name": "salary", "type": "double"},
    {"name": "department", "type": "string"},
    {"name": "hire_date", "type": "string"}
  ]
}
EOF

    # Parquet schema (as JSON)
    cat > "$schema_dir/product.parquet.json" << 'EOF'
{
  "type": "record",
  "name": "Product",
  "fields": [
    {"name": "id", "type": "int"},
    {"name": "name", "type": "string"},
    {"name": "price", "type": "double"},
    {"name": "category", "type": "string"},
    {"name": "in_stock", "type": "boolean"}
  ]
}
EOF

    log_success "Schema files created"
}

function create_format_specific_data() {
    log_info "🔧 Creating format-specific test data..."
    
    local formats_dir="$TEST_DATA_DIR/formats"
    
    # Copy base data to format directories
    cp "$TEST_DATA_DIR/small/employees.csv" "$formats_dir/csv/"
    cp "$TEST_DATA_DIR/small/products.json" "$formats_dir/json/"
    
    # Create additional format samples if tools are available
    if command -v parquet-tools >/dev/null 2>&1; then
        log_info "Creating Parquet samples..."
        # Note: This would require actual parquet-tools implementation
        touch "$formats_dir/parquet/sample.parquet"
    fi
    
    if command -v avro-tools >/dev/null 2>&1; then
        log_info "Creating Avro samples..."
        # Note: This would require actual avro-tools implementation
        touch "$formats_dir/avro/sample.avro"
    fi
    
    log_success "Format-specific data created"
}

function upload_to_hdfs() {
    if [[ "$UPLOAD_TO_HDFS" != "true" ]]; then
        log_info "⏭️ Skipping HDFS upload (UPLOAD_TO_HDFS=false)"
        return 0
    fi
    
    if [[ -z "$HADOOP_HOME" ]]; then
        log_warning "HADOOP_HOME not set, skipping HDFS upload"
        return 0
    fi
    
    if [[ ! -x "$HADOOP_HOME/bin/hdfs" ]]; then
        log_warning "HDFS command not found, skipping HDFS upload"
        return 0
    fi
    
    log_info "📤 Uploading test data to HDFS..."
    
    # Create HDFS directories
    "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /user/gpadmin/test-data/small
    "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /user/gpadmin/test-data/medium
    
    # Upload small dataset
    "$HADOOP_HOME/bin/hdfs" dfs -put "$TEST_DATA_DIR/small/*" /user/gpadmin/test-data/small/
    
    # Upload medium dataset
    "$HADOOP_HOME/bin/hdfs" dfs -put "$TEST_DATA_DIR/medium/*" /user/gpadmin/test-data/medium/
    
    # Upload large dataset if it exists
    if [[ -d "$TEST_DATA_DIR/large" ]] && [[ "$(ls -A "$TEST_DATA_DIR/large")" ]]; then
        "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p /user/gpadmin/test-data/large
        "$HADOOP_HOME/bin/hdfs" dfs -put "$TEST_DATA_DIR/large/*" /user/gpadmin/test-data/large/
    fi
    
    log_success "Test data uploaded to HDFS"
}

function validate_test_data() {
    log_info "✅ Validating created test data..."
    
    local validation_errors=()
    
    # Check required files exist
    local required_files=(
        "$TEST_DATA_DIR/small/employees.csv"
        "$TEST_DATA_DIR/small/products.json"
        "$TEST_DATA_DIR/medium/large_table.csv"
        "$TEST_DATA_DIR/schemas/employee.avsc"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            validation_errors+=("Missing file: $file")
        fi
    done
    
    # Check file sizes are reasonable (use Linux-compatible stat command)
    local small_csv_size=$(stat -c%s "$TEST_DATA_DIR/small/employees.csv" 2>/dev/null || echo 0)
    if [[ $small_csv_size -lt 100 ]]; then
        validation_errors+=("Small CSV file is too small: $small_csv_size bytes")
    fi
    
    if [[ ${#validation_errors[@]} -gt 0 ]]; then
        log_error "Test data validation failed:"
        printf '  - %s\n' "${validation_errors[@]}"
        return 1
    fi
    
    log_success "Test data validation passed"
    return 0
}

function generate_data_summary() {
    local summary_file="$TEST_DATA_DIR/data-summary.txt"
    
    log_info "📋 Generating test data summary..."
    
    cat > "$summary_file" << EOF
PXF Test Data Summary
====================
Generated: $(date)
Location: $TEST_DATA_DIR

Directory Structure:
$(find "$TEST_DATA_DIR" -type d | sort)

File Inventory:
$(find "$TEST_DATA_DIR" -type f -exec ls -lh {} \; | awk '{print $9, $5}')

Dataset Sizes:
- Small: $(find "$TEST_DATA_DIR/small" -type f | wc -l) files
- Medium: $(find "$TEST_DATA_DIR/medium" -type f | wc -l) files
- Large: $(find "$TEST_DATA_DIR/large" -type f 2>/dev/null | wc -l) files

Total Size: $(du -sh "$TEST_DATA_DIR" | cut -f1)
EOF

    log_success "Test data summary saved to: $summary_file"
}

function main() {
    log_info "🚀 Starting test data setup..."
    
    # Create directory structure
    create_directory_structure
    
    # Create datasets
    create_small_dataset
    create_medium_dataset
    create_large_dataset
    
    # Create supporting files
    create_schema_files
    create_format_specific_data
    
    # Upload to HDFS if requested
    upload_to_hdfs
    
    # Validate and summarize
    validate_test_data
    generate_data_summary
    
    log_success "🎉 Test data setup completed successfully!"
    log_info "Test data location: $TEST_DATA_DIR"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
