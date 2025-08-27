#!/bin/bash
# Test Data Setup for PXF Integration Testing
# This script creates standardized test datasets for various PXF connectors

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DATA_DIR="${TEST_DATA_DIR:-/tmp/pxf-test-data}"
HADOOP_HOME="${HADOOP_HOME:-/workspace/hadoop-3.3.4}"

echo "📁 Setting up standardized test data for PXF testing..."

# Create test data directory
mkdir -p "$TEST_DATA_DIR"

# Function to create CSV test data
create_csv_data() {
    local filename="$1"
    local rows="$2"
    
    echo "📄 Creating CSV test data: $filename ($rows rows)"
    
    cat > "$filename" << 'EOF'
id,name,age,city,salary,department,hire_date
EOF
    
    # Generate test data
    for i in $(seq 1 "$rows"); do
        local names=("Alice" "Bob" "Charlie" "Diana" "Eve" "Frank" "Grace" "Henry" "Ivy" "Jack")
        local cities=("NYC" "LA" "Chicago" "Houston" "Phoenix" "Philadelphia" "San Antonio" "San Diego" "Dallas" "San Jose")
        local departments=("IT" "HR" "Finance" "Marketing" "Operations" "Sales" "Engineering" "Support" "Legal" "Admin")
        
        local name=${names[$((i % ${#names[@]}))]}
        local city=${cities[$((i % ${#cities[@]}))]}
        local department=${departments[$((i % ${#departments[@]}))]}
        local age=$((22 + (i % 43)))
        local salary=$((30000 + (i * 1000) % 120000))
        local hire_date="2020-$(printf "%02d" $((1 + (i % 12))))-$(printf "%02d" $((1 + (i % 28))))"
        
        echo "$i,$name,$age,$city,$salary,$department,$hire_date" >> "$filename"
    done
    
    echo "✅ Created $filename with $rows rows"
}

# Function to create JSON test data
create_json_data() {
    local filename="$1"
    local rows="$2"
    
    echo "📄 Creating JSON test data: $filename ($rows rows)"
    
    cat > "$filename" << 'EOF'
[
EOF
    
    for i in $(seq 1 "$rows"); do
        local names=("Alice" "Bob" "Charlie" "Diana" "Eve" "Frank" "Grace" "Henry" "Ivy" "Jack")
        local cities=("NYC" "LA" "Chicago" "Houston" "Phoenix" "Philadelphia" "San Antonio" "San Diego" "Dallas" "San Jose")
        local departments=("IT" "HR" "Finance" "Marketing" "Operations" "Sales" "Engineering" "Support" "Legal" "Admin")
        
        local name=${names[$((i % ${#names[@]}))]}
        local city=${cities[$((i % ${#cities[@]}))]}
        local department=${departments[$((i % ${#departments[@]}))]}
        local age=$((22 + (i % 43)))
        local salary=$((30000 + (i * 1000) % 120000))
        local hire_date="2020-$(printf "%02d" $((1 + (i % 12))))-$(printf "%02d" $((1 + (i % 28))))"
        
        if [ "$i" -eq "$rows" ]; then
            # Last record without comma
            cat >> "$filename" << EOF
  {
    "id": $i,
    "name": "$name",
    "age": $age,
    "city": "$city",
    "salary": $salary,
    "department": "$department",
    "hire_date": "$hire_date"
  }
EOF
        else
            cat >> "$filename" << EOF
  {
    "id": $i,
    "name": "$name",
    "age": $age,
    "city": "$city",
    "salary": $salary,
    "department": "$department",
    "hire_date": "$hire_date"
  },
EOF
        fi
    done
    
    echo "]" >> "$filename"
    echo "✅ Created $filename with $rows rows"
}

# Function to create Hive-style delimited data
create_hive_data() {
    local filename="$1"
    local rows="$2"
    
    echo "📄 Creating Hive-style delimited data: $filename ($rows rows)"
    
    for i in $(seq 1 "$rows"); do
        local names=("Alice" "Bob" "Charlie" "Diana" "Eve" "Frank" "Grace" "Henry" "Ivy" "Jack")
        local cities=("NYC" "LA" "Chicago" "Houston" "Phoenix" "Philadelphia" "San Antonio" "San Diego" "Dallas" "San Jose")
        local departments=("IT" "HR" "Finance" "Marketing" "Operations" "Sales" "Engineering" "Support" "Legal" "Admin")
        
        local name=${names[$((i % ${#names[@]}))]}
        local city=${cities[$((i % ${#cities[@]}))]}
        local department=${departments[$((i % ${#departments[@]}))]}
        local age=$((22 + (i % 43)))
        local salary=$((30000 + (i * 1000) % 120000))
        local hire_date="2020-$(printf "%02d" $((1 + (i % 12))))-$(printf "%02d" $((1 + (i % 28))))"
        
        echo -e "$i\t$name\t$age\t$city\t$salary\t$department\t$hire_date" >> "$filename"
    done
    
    echo "✅ Created $filename with $rows rows"
}

# Function to upload data to HDFS
upload_to_hdfs() {
    local local_file="$1"
    local hdfs_path="$2"
    
    if [ -n "${HADOOP_HOME:-}" ] && [ -f "$HADOOP_HOME/bin/hdfs" ]; then
        echo "📤 Uploading $local_file to HDFS: $hdfs_path"
        
        # Create parent directory
        local parent_dir=$(dirname "$hdfs_path")
        "$HADOOP_HOME/bin/hdfs" dfs -mkdir -p "$parent_dir"
        
        # Upload file
        if "$HADOOP_HOME/bin/hdfs" dfs -put "$local_file" "$hdfs_path"; then
            echo "✅ Successfully uploaded to HDFS: $hdfs_path"
        else
            echo "⚠️ Failed to upload to HDFS: $hdfs_path"
            return 1
        fi
    else
        echo "⚠️ HDFS not available, skipping upload"
    fi
}

# Function to create test datasets
create_test_datasets() {
    echo "🏗️ Creating standardized test datasets..."
    
    # Small dataset (1K rows)
    create_csv_data "$TEST_DATA_DIR/employees_small.csv" 1000
    create_json_data "$TEST_DATA_DIR/employees_small.json" 1000
    create_hive_data "$TEST_DATA_DIR/employees_small.txt" 1000
    
    # Medium dataset (10K rows)
    create_csv_data "$TEST_DATA_DIR/employees_medium.csv" 10000
    create_json_data "$TEST_DATA_DIR/employees_medium.json" 10000
    create_hive_data "$TEST_DATA_DIR/employees_medium.txt" 10000
    
    # Large dataset (100K rows) - only if requested
    if [ "${CREATE_LARGE_DATASET:-false}" = "true" ]; then
        create_csv_data "$TEST_DATA_DIR/employees_large.csv" 100000
        create_json_data "$TEST_DATA_DIR/employees_large.json" 100000
        create_hive_data "$TEST_DATA_DIR/employees_large.txt" 100000
    fi
    
    echo "✅ Test datasets created successfully"
}

# Function to upload datasets to HDFS
upload_datasets_to_hdfs() {
    echo "📤 Uploading test datasets to HDFS..."
    
    # Upload CSV files
    upload_to_hdfs "$TEST_DATA_DIR/employees_small.csv" "/user/gpadmin/test-data/csv/employees_small.csv"
    upload_to_hdfs "$TEST_DATA_DIR/employees_medium.csv" "/user/gpadmin/test-data/csv/employees_medium.csv"
    
    # Upload JSON files
    upload_to_hdfs "$TEST_DATA_DIR/employees_small.json" "/user/gpadmin/test-data/json/employees_small.json"
    upload_to_hdfs "$TEST_DATA_DIR/employees_medium.json" "/user/gpadmin/test-data/json/employees_medium.json"
    
    # Upload Hive-style files
    upload_to_hdfs "$TEST_DATA_DIR/employees_small.txt" "/user/gpadmin/hive/warehouse/employees_small/data.txt"
    upload_to_hdfs "$TEST_DATA_DIR/employees_medium.txt" "/user/gpadmin/hive/warehouse/employees_medium/data.txt"
    
    # Upload large datasets if they exist
    if [ -f "$TEST_DATA_DIR/employees_large.csv" ]; then
        upload_to_hdfs "$TEST_DATA_DIR/employees_large.csv" "/user/gpadmin/test-data/csv/employees_large.csv"
        upload_to_hdfs "$TEST_DATA_DIR/employees_large.json" "/user/gpadmin/test-data/json/employees_large.json"
        upload_to_hdfs "$TEST_DATA_DIR/employees_large.txt" "/user/gpadmin/hive/warehouse/employees_large/data.txt"
    fi
    
    echo "✅ Datasets uploaded to HDFS successfully"
}

# Function to verify test data
verify_test_data() {
    echo "🔍 Verifying test data..."
    
    # Check local files
    for file in "$TEST_DATA_DIR"/*.csv "$TEST_DATA_DIR"/*.json "$TEST_DATA_DIR"/*.txt; do
        if [ -f "$file" ]; then
            local size=$(wc -l < "$file")
            echo "✅ Local file: $(basename "$file") - $size lines"
        fi
    done
    
    # Check HDFS files if available
    if [ -n "${HADOOP_HOME:-}" ] && [ -f "$HADOOP_HOME/bin/hdfs" ]; then
        echo "📋 HDFS test data structure:"
        "$HADOOP_HOME/bin/hdfs" dfs -ls -R /user/gpadmin/test-data/ || echo "⚠️ No test-data directory in HDFS"
        "$HADOOP_HOME/bin/hdfs" dfs -ls -R /user/gpadmin/hive/warehouse/ || echo "⚠️ No hive warehouse in HDFS"
    fi
    
    echo "✅ Test data verification completed"
}

# Main execution function
main() {
    echo "🚀 Starting test data setup..."
    
    # Create test datasets
    create_test_datasets
    
    # Upload to HDFS if available
    if [ "${UPLOAD_TO_HDFS:-true}" = "true" ]; then
        upload_datasets_to_hdfs
    fi
    
    # Verify test data
    verify_test_data
    
    echo "🎉 Test data setup completed successfully!"
    echo "📊 Test data summary:"
    echo "  - Location: $TEST_DATA_DIR"
    echo "  - Small datasets: 1K rows each"
    echo "  - Medium datasets: 10K rows each"
    if [ "${CREATE_LARGE_DATASET:-false}" = "true" ]; then
        echo "  - Large datasets: 100K rows each"
    fi
    echo "  - Formats: CSV, JSON, Hive-delimited"
}

# Execute main function
main "$@"
