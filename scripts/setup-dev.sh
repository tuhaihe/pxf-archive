#!/bin/bash

# PXF Development Setup Script for Apache/Cloudberry
# This script helps set up a local development environment for PXF with Cloudberry

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PXF_VERSION=${PXF_VERSION:-"6.10.1-SNAPSHOT"}
CLOUDBERRY_VERSION=${CLOUDBERRY_VERSION:-"1.0.0"}
JAVA_VERSION=${JAVA_VERSION:-"11"}
GO_VERSION=${GO_VERSION:-"1.19"}
HADOOP_VERSION=${HADOOP_VERSION:-"3.3.4"}

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PXF_ROOT="$(cd "${SCRIPT_DIR}" && pwd)"
PXF_HOME="${PXF_HOME:-/usr/local/pxf}"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

check_requirements() {
    log "Checking system requirements..."
    
    # Check for required tools
    local missing_tools=()
    
    for tool in make gcc curl unzip java javac go pg_config; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        error "Missing required tools: ${missing_tools[*]}"
    fi
    
    # Check Java version
    local java_ver=$(java -version 2>&1 | grep -oP '(?<=version ").*?(?=")' | cut -d. -f1)
    if [ "$java_ver" -ne "$JAVA_VERSION" ] && [ "$java_ver" -ne 8 ]; then
        warn "Java version mismatch. Expected $JAVA_VERSION or 8, got $java_ver"
    fi
    
    log "System requirements check completed"
}

setup_environment() {
    log "Setting up environment variables..."
    
    # Detect PostgreSQL installation
    local pg_config_path=$(command -v pg_config)
    local pg_root=$(dirname "$(dirname "$pg_config_path")")
    
    cat > "${PXF_ROOT}/.pxf-env" << EOF
# PXF Environment Configuration for Apache/Cloudberry
export GPHOME="${pg_root}"
export PXF_HOME="${PXF_HOME}"
export PG_CONFIG="${pg_config_path}"
export JAVA_HOME="${JAVA_HOME:-$(dirname $(dirname $(readlink -f $(which java))))}"
export PATH="${PXF_HOME}/bin:\$PATH"
export PGPORT=5432
export PGUSER=gpadmin
export PGPASSWORD=gpadmin
EOF
    
    log "Environment configuration saved to ${PXF_ROOT}/.pxf-env"
    log "Source this file: source ${PXF_ROOT}/.pxf-env"
}

install_dependencies() {
    log "Installing system dependencies..."
    
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y \
            build-essential \
            curl \
            unzip \
            maven \
            postgresql-14 \
            postgresql-server-dev-14 \
            postgresql-client \
            libreadline-dev \
            zlib1g-dev \
            libssl-dev \
            libxml2-dev \
            libxslt-dev \
            libcurl4-openssl-dev \
            python3-dev \
            flex \
            bison
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y \
            gcc \
            gcc-c++ \
            make \
            curl \
            unzip \
            maven \
            postgresql14-server \
            postgresql14-devel \
            readline-devel \
            zlib-devel \
            openssl-devel \
            libxml2-devel \
            libxslt-devel \
            libcurl-devel \
            python3-devel \
            flex \
            bison
    else
        warn "Unknown package manager. Please install dependencies manually."
    fi
}

setup_database() {
    log "Setting up PostgreSQL database for testing..."
    
    # Create gpadmin user if it doesn't exist
    if ! id "gpadmin" >/dev/null 2>&1; then
        sudo useradd -m -s /bin/bash gpadmin
        echo "gpadmin:gpadmin" | sudo chpasswd
        sudo usermod -aG sudo gpadmin
    fi
    
    # Setup PostgreSQL
    sudo systemctl enable postgresql || true
    sudo systemctl start postgresql || true
    
    # Create databases
    sudo -u postgres createuser -s gpadmin || true
    sudo -u postgres createdb -O gpadmin gpadmin || true
    sudo -u postgres createdb -O gpadmin pxfautomation || true
    
    # Configure PostgreSQL
    local pg_version=$(sudo -u postgres psql -t -c "SELECT version();" | grep -oP 'PostgreSQL \K[0-9]+')
    local pg_config_dir="/etc/postgresql/${pg_version}/main"
    
    if [ -d "$pg_config_dir" ]; then
        sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "${pg_config_dir}/postgresql.conf"
        echo "host all all 0.0.0.0/0 trust" | sudo tee -a "${pg_config_dir}/pg_hba.conf"
        sudo systemctl restart postgresql
    fi
    
    log "Database setup completed"
}

build_pxf() {
    log "Building PXF components..."
    
    # Source environment
    source "${PXF_ROOT}/.pxf-env"
    
    # Create PXF_HOME directory
    sudo mkdir -p "$PXF_HOME"
    sudo chown -R "$USER:$USER" "$PXF_HOME"
    
    cd "$PXF_ROOT"
    
    # Clean previous builds
    make clean || true
    
    # Build components
    log "Building external-table extension..."
    make -C external-table || error "Failed to build external-table"
    
    log "Building FDW extension..."
    if make -C fdw; then
        log "FDW extension built successfully"
    else
        warn "FDW build failed - may need Cloudberry-specific modifications"
    fi
    
    log "Building CLI..."
    make -C cli || error "Failed to build CLI"
    
    log "Building server..."
    make -C server || error "Failed to build server"
    
    log "PXF build completed successfully"
}

run_tests() {
    log "Running PXF tests..."
    
    source "${PXF_ROOT}/.pxf-env"
    cd "$PXF_ROOT"
    
    # Run unit tests
    log "Running CLI tests..."
    make -C cli test || warn "CLI tests failed"
    
    log "Running server tests..."
    make -C server test || warn "Server tests failed"
    
    # Basic smoke test
    log "Running basic smoke tests..."
    if [ -x "$PXF_HOME/bin/pxf-cli" ]; then
        "$PXF_HOME/bin/pxf-cli" version || warn "PXF CLI smoke test failed"
    fi
}

install_pxf() {
    log "Installing PXF..."
    
    source "${PXF_ROOT}/.pxf-env"
    cd "$PXF_ROOT"
    
    make install-server || error "Failed to install PXF server"
    
    # Set permissions
    sudo chown -R gpadmin:gpadmin "$PXF_HOME" || true
    
    log "PXF installation completed"
}

create_packages() {
    log "Creating distribution packages..."
    
    source "${PXF_ROOT}/.pxf-env"
    cd "$PXF_ROOT"
    
    # Create tarball
    make tar || warn "Failed to create tarball"
    
    # Create DEB package
    make deb || warn "Failed to create DEB package"
    
    log "Package creation completed. Check build/dist/ for artifacts."
}

setup_hadoop_testing() {
    log "Setting up Hadoop for testing (optional)..."
    
    local hadoop_dir="/tmp/hadoop-${HADOOP_VERSION}"
    
    if [ ! -d "$hadoop_dir" ]; then
        cd /tmp
        curl -LO "https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz"
        tar -xzf "hadoop-${HADOOP_VERSION}.tar.gz"
    fi
    
    export HADOOP_HOME="$hadoop_dir"
    export HADOOP_CONF_DIR="$hadoop_dir/etc/hadoop"
    export PATH="$hadoop_dir/bin:$PATH"
    
    # Basic Hadoop configuration
    cat > "$HADOOP_CONF_DIR/core-site.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>fs.defaultFS</name>
    <value>file:///</value>
  </property>
</configuration>
EOF
    
    log "Hadoop setup completed at $hadoop_dir"
}

print_usage() {
    cat << EOF
PXF Development Setup Script for Apache/Cloudberry

Usage: $0 [COMMAND]

Commands:
  check       Check system requirements
  setup       Set up development environment
  deps        Install system dependencies
  database    Set up PostgreSQL database
  build       Build PXF components
  test        Run PXF tests
  install     Install PXF
  package     Create distribution packages
  hadoop      Set up Hadoop for testing
  all         Run all setup steps (deps, database, setup, build, install)
  
Environment Variables:
  PXF_VERSION       PXF version (default: $PXF_VERSION)
  CLOUDBERRY_VERSION Cloudberry version (default: $CLOUDBERRY_VERSION)
  JAVA_VERSION      Java version (default: $JAVA_VERSION)
  GO_VERSION        Go version (default: $GO_VERSION)
  HADOOP_VERSION    Hadoop version (default: $HADOOP_VERSION)
  PXF_HOME          PXF installation directory (default: $PXF_HOME)

Examples:
  $0 all                    # Full setup and build
  $0 setup && $0 build     # Environment setup and build only
  $0 test                  # Run tests after build
  $0 package               # Create packages after build

EOF
}

main() {
    case "${1:-}" in
        check)
            check_requirements
            ;;
        setup)
            setup_environment
            ;;
        deps)
            install_dependencies
            ;;
        database)
            setup_database
            ;;
        build)
            build_pxf
            ;;
        test)
            run_tests
            ;;
        install)
            install_pxf
            ;;
        package)
            create_packages
            ;;
        hadoop)
            setup_hadoop_testing
            ;;
        all)
            check_requirements
            install_dependencies
            setup_database
            setup_environment
            build_pxf
            install_pxf
            log "PXF development environment setup completed!"
            log "Source the environment: source ${PXF_ROOT}/.pxf-env"
            ;;
        *)
            print_usage
            ;;
    esac
}

main "$@"