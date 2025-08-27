#!/bin/bash
# Setup Apache Cloudberry environment for PXF CI
# This script clones, builds, and initializes Apache Cloudberry

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to setup Cloudberry source
setup_cloudberry_source() {
    local container_name="$1"

    echo "📥 Setting up Apache Cloudberry source..."

    docker exec --user gpadmin "$container_name" bash -c "
        cd /home/gpadmin

        # Clone Cloudberry source if not exists
        if [ ! -d cloudberry ]; then
            echo 'Cloning Apache Cloudberry repository...'
            git clone --depth 1 --branch main https://github.com/apache/cloudberry.git
        else
            echo 'Cloudberry source already exists'
        fi

        cd cloudberry
        echo '✅ Apache Cloudberry source ready'
    "
}

# Function to build Cloudberry
build_cloudberry() {
    local container_name="$1"

    echo "🏗️ Building Apache Cloudberry with PXF support..."

    docker exec --user gpadmin "$container_name" bash -c "
        cd /home/gpadmin/cloudberry
        source ~/.bashrc

        echo 'Configuring Apache Cloudberry...'

        # Prepare build environment
        sudo mkdir -p /usr/local/cloudberry-db/lib
        if [ -d /usr/local/xerces-c/lib ]; then
            sudo cp -v /usr/local/xerces-c/lib/libxerces-c.so /usr/local/cloudberry-db/lib/ 2>/dev/null || true
            sudo cp -v /usr/local/xerces-c/lib/libxerces-c-3.*.so /usr/local/cloudberry-db/lib/ 2>/dev/null || true
        fi
        sudo chown -R gpadmin:gpadmin /usr/local/cloudberry-db

        export LD_LIBRARY_PATH=/usr/local/cloudberry-db/lib:\$LD_LIBRARY_PATH

        # Configure with PXF support
        ./configure --prefix=/usr/local/cloudberry-db \\
          --disable-external-fts \\
          --enable-debug \\
          --enable-cassert \\
          --enable-gpcloud \\
          --enable-ic-proxy \\
          --enable-mapreduce \\
          --enable-orca \\
          --enable-pxf \\
          --with-gssapi \\
          --with-libxml \\
          --with-perl \\
          --with-pgport=5432 \\
          --with-python \\
          --with-pythonsrc-ext \\
          --with-uuid=e2fs \\
          --with-includes=/usr/local/xerces-c/include \\
          --with-libraries=/usr/local/cloudberry-db/lib

        # Build with optimal parallelism
        echo 'Building Apache Cloudberry...'
        NPROC=\$(nproc)
        PARALLEL_JOBS=\$((NPROC > 4 ? 4 : NPROC))

        make -j\$PARALLEL_JOBS

        # Install
        echo 'Installing Apache Cloudberry...'
        make -j\$PARALLEL_JOBS install

        echo '✅ Apache Cloudberry build completed'
    "
}

# Function to initialize demo cluster
initialize_demo_cluster() {
    local container_name="$1"

    echo "🎯 Initializing Apache Cloudberry demo cluster..."

    docker exec --user gpadmin "$container_name" bash -c "
        cd /home/gpadmin/cloudberry
        source /usr/local/cloudberry-db/cloudberry-env.sh
        export LANG=en_US.UTF-8

        # Create demo cluster
        echo 'Creating demo cluster...'
        make create-demo-cluster

        # Source cluster environment
        source gpAux/gpdemo/gpdemo-env.sh

        # Verify cluster status
        echo 'Verifying cluster status...'
        gpstate -s

        # Test connectivity
        psql -p 7000 template1 -c 'SELECT version();'

        echo '✅ Demo cluster initialized and verified'
    "
}

# Main execution function
main() {
    local container_name="${1:-pxf-build}"

    echo "🔧 Setting up Apache Cloudberry environment..."

    # Check if Cloudberry is already built and running
    if docker exec --user gpadmin "$container_name" test -f /usr/local/cloudberry-db/cloudberry-env.sh && \
       docker exec --user gpadmin "$container_name" test -f /home/gpadmin/cloudberry/gpAux/gpdemo/gpdemo-env.sh; then
        echo "✅ Cloudberry already built and configured"

        # Just verify it's running
        if docker exec --user gpadmin "$container_name" bash -c "
            source /usr/local/cloudberry-db/cloudberry-env.sh
            source /home/gpadmin/cloudberry/gpAux/gpdemo/gpdemo-env.sh
            psql -p 7000 template1 -c 'SELECT 1;' >/dev/null 2>&1
        "; then
            echo "✅ Cloudberry cluster is running"
        else
            echo "⚠️ Cloudberry cluster not running, restarting..."
            docker exec --user gpadmin "$container_name" bash -c "
                source /usr/local/cloudberry-db/cloudberry-env.sh
                source /home/gpadmin/cloudberry/gpAux/gpdemo/gpdemo-env.sh
                gpstart -a
            "
        fi
    else
        echo "� Building Cloudberry from source..."

        # Setup source, build, and initialize
        setup_cloudberry_source "$container_name"
        build_cloudberry "$container_name"
        initialize_demo_cluster "$container_name"
    fi

    # Final verification
    echo "🔍 Final verification..."

    if docker exec --user gpadmin "$container_name" bash -c "
        source /usr/local/cloudberry-db/cloudberry-env.sh
        source /home/gpadmin/cloudberry/gpAux/gpdemo/gpdemo-env.sh

        # Test database connection
        psql -p 7000 template1 -c 'SELECT version();'

        # Create gpadmin database if it doesn't exist
        createdb gpadmin -p 7000 2>/dev/null || echo 'Database gpadmin already exists'
    "; then
        echo "✅ Cloudberry environment setup completed successfully"
    else
        echo "❌ Final verification failed"

        # Show debug information
        echo "🔍 Debug information:"
        docker exec --user gpadmin "$container_name" bash -c "
            echo 'Cloudberry processes:'
            ps aux | grep postgres || echo 'No postgres processes found'

            echo 'Cluster status:'
            source /usr/local/cloudberry-db/cloudberry-env.sh 2>/dev/null || echo 'Cannot source cloudberry-env.sh'
            gpstate -s 2>/dev/null || echo 'gpstate failed'
        "

        exit 1
    fi
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
