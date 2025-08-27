#!/bin/bash
# Hadoop Environment Setup for PXF Integration Testing
# This script sets up a minimal Hadoop environment for testing PXF connectivity

set -euo pipefail

CONTAINER_NAME="${1:-pxf-hadoop}"
HADOOP_VERSION="${HADOOP_VERSION:-3.3.4}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔧 Setting up Hadoop environment for PXF testing..."

# Function to setup Hadoop in container
setup_hadoop_environment() {
    echo "📥 Setting up Hadoop $HADOOP_VERSION..."
    
    docker exec --user gpadmin "$CONTAINER_NAME" bash -c "
        cd /workspace
        
        # Download Hadoop if not already present
        if [ ! -d hadoop-$HADOOP_VERSION ]; then
            echo 'Downloading Hadoop $HADOOP_VERSION...'
            wget -q https://archive.apache.org/dist/hadoop/common/hadoop-$HADOOP_VERSION/hadoop-$HADOOP_VERSION.tar.gz
            tar -xzf hadoop-$HADOOP_VERSION.tar.gz
            rm hadoop-$HADOOP_VERSION.tar.gz
        fi
        
        export HADOOP_HOME=/workspace/hadoop-$HADOOP_VERSION
        export JAVA_HOME=\$(find /usr/lib/jvm -name 'java-11-openjdk*' | head -1)
        
        # Create Hadoop configuration directory
        mkdir -p \$HADOOP_HOME/etc/hadoop
        
        echo '✅ Hadoop binaries ready'
    "
}

# Function to configure Hadoop for pseudo-distributed mode
configure_hadoop() {
    echo "⚙️ Configuring Hadoop for pseudo-distributed mode..."
    
    docker exec --user gpadmin "$CONTAINER_NAME" bash -c "
        export HADOOP_HOME=/workspace/hadoop-$HADOOP_VERSION
        export JAVA_HOME=\$(find /usr/lib/jvm -name 'java-11-openjdk*' | head -1)
        
        # Configure core-site.xml
        cat > \$HADOOP_HOME/etc/hadoop/core-site.xml << 'EOF'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>hdfs://localhost:9000</value>
  </property>
  <property>
    <name>hadoop.tmp.dir</name>
    <value>/tmp/hadoop-pxf</value>
  </property>
  <property>
    <name>hadoop.proxyuser.gpadmin.hosts</name>
    <value>*</value>
  </property>
  <property>
    <name>hadoop.proxyuser.gpadmin.groups</name>
    <value>*</value>
  </property>
</configuration>
EOF
        
        # Configure hdfs-site.xml
        cat > \$HADOOP_HOME/etc/hadoop/hdfs-site.xml << 'EOF'
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<configuration>
  <property>
    <name>dfs.replication</name>
    <value>1</value>
  </property>
  <property>
    <name>dfs.namenode.name.dir</name>
    <value>/tmp/hadoop-pxf/dfs/name</value>
  </property>
  <property>
    <name>dfs.datanode.data.dir</name>
    <value>/tmp/hadoop-pxf/dfs/data</value>
  </property>
  <property>
    <name>dfs.permissions.enabled</name>
    <value>false</value>
  </property>
  <property>
    <name>dfs.namenode.safemode.threshold-pct</name>
    <value>0</value>
  </property>
</configuration>
EOF
        
        # Set JAVA_HOME in hadoop-env.sh
        echo \"export JAVA_HOME=\$JAVA_HOME\" >> \$HADOOP_HOME/etc/hadoop/hadoop-env.sh
        
        echo '✅ Hadoop configuration completed'
    "
}

# Function to setup SSH for Hadoop
setup_ssh() {
    echo "🔑 Setting up SSH for Hadoop..."
    
    docker exec --user gpadmin "$CONTAINER_NAME" bash -c "
        # Generate SSH key if not exists
        if [ ! -f ~/.ssh/id_rsa ]; then
            ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa
        fi
        
        # Add to authorized keys
        cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
        chmod 0600 ~/.ssh/authorized_keys
        
        # Create SSH config to avoid host key checking
        cat > ~/.ssh/config << 'EOF'
Host localhost
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF
        chmod 600 ~/.ssh/config
        
        echo '✅ SSH setup completed'
    "
}

# Function to start Hadoop services
start_hadoop_services() {
    echo "🚀 Starting Hadoop services..."
    
    docker exec --user gpadmin "$CONTAINER_NAME" bash -c "
        export HADOOP_HOME=/workspace/hadoop-$HADOOP_VERSION
        export JAVA_HOME=\$(find /usr/lib/jvm -name 'java-11-openjdk*' | head -1)
        export PATH=\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin:\$PATH
        
        # Format namenode if not already formatted
        if [ ! -d /tmp/hadoop-pxf/dfs/name/current ]; then
            echo 'Formatting HDFS namenode...'
            \$HADOOP_HOME/bin/hdfs namenode -format -force -nonInteractive
        fi
        
        # Start HDFS services
        echo 'Starting HDFS services...'
        \$HADOOP_HOME/sbin/start-dfs.sh
        
        # Wait for services to start
        sleep 30
        
        # Verify HDFS is running
        \$HADOOP_HOME/bin/hdfs dfsadmin -report
        
        echo '✅ Hadoop services started'
    "
}

# Function to create test directories and data
setup_test_data() {
    echo "📁 Setting up test data in HDFS..."
    
    docker exec --user gpadmin "$CONTAINER_NAME" bash -c "
        export HADOOP_HOME=/workspace/hadoop-$HADOOP_VERSION
        export JAVA_HOME=\$(find /usr/lib/jvm -name 'java-11-openjdk*' | head -1)
        export PATH=\$HADOOP_HOME/bin:\$PATH
        
        # Create user directory
        \$HADOOP_HOME/bin/hdfs dfs -mkdir -p /user/gpadmin
        
        # Create test data
        echo -e 'id,name,salary\\n1,Alice,50000\\n2,Bob,60000\\n3,Charlie,55000' > /tmp/employee_test.csv
        
        # Upload test data to HDFS
        \$HADOOP_HOME/bin/hdfs dfs -put /tmp/employee_test.csv /user/gpadmin/employee_test.csv
        
        # Create Hive-style directory structure
        \$HADOOP_HOME/bin/hdfs dfs -mkdir -p /user/gpadmin/hive/warehouse/test_table
        
        # Upload Hive-style data
        echo -e '1\\tAlice\\t50000\\n2\\tBob\\t60000\\n3\\tCharlie\\t55000' > /tmp/hive_test_data.txt
        \$HADOOP_HOME/bin/hdfs dfs -put /tmp/hive_test_data.txt /user/gpadmin/hive/warehouse/test_table/data.txt
        
        # Verify data upload
        echo 'Verifying test data...'
        \$HADOOP_HOME/bin/hdfs dfs -ls /user/gpadmin/
        \$HADOOP_HOME/bin/hdfs dfs -cat /user/gpadmin/employee_test.csv | head -3
        
        echo '✅ Test data setup completed'
    "
}

# Function to verify Hadoop setup
verify_hadoop_setup() {
    echo "🔍 Verifying Hadoop setup..."
    
    docker exec --user gpadmin "$CONTAINER_NAME" bash -c "
        export HADOOP_HOME=/workspace/hadoop-$HADOOP_VERSION
        export JAVA_HOME=\$(find /usr/lib/jvm -name 'java-11-openjdk*' | head -1)
        export PATH=\$HADOOP_HOME/bin:\$PATH
        
        # Test HDFS connectivity
        if \$HADOOP_HOME/bin/hdfs dfs -ls / >/dev/null 2>&1; then
            echo '✅ HDFS connectivity verified'
        else
            echo '❌ HDFS connectivity failed'
            exit 1
        fi
        
        # Test data access
        if \$HADOOP_HOME/bin/hdfs dfs -test -f /user/gpadmin/employee_test.csv; then
            echo '✅ Test data accessible'
        else
            echo '❌ Test data not accessible'
            exit 1
        fi
        
        # Show cluster status
        echo 'HDFS Cluster Status:'
        \$HADOOP_HOME/bin/hdfs dfsadmin -report | head -10
        
        echo '✅ Hadoop verification completed'
    "
}

# Main execution function
main() {
    echo "🐳 Setting up Hadoop environment in container: $CONTAINER_NAME"
    
    # Execute setup steps
    setup_hadoop_environment
    configure_hadoop
    setup_ssh
    start_hadoop_services
    setup_test_data
    verify_hadoop_setup
    
    echo "🎉 Hadoop environment setup completed successfully!"
    echo "📊 Environment details:"
    echo "  - Hadoop Version: $HADOOP_VERSION"
    echo "  - HDFS URL: hdfs://localhost:9000"
    echo "  - Test data: /user/gpadmin/employee_test.csv"
    echo "  - Hive data: /user/gpadmin/hive/warehouse/test_table/"
}

# Execute main function
main "$@"
