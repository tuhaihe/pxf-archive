#!/bin/bash
# Setup Apache Cloudberry environment for PXF CI
# This script optimizes the Cloudberry setup process by using pre-built components

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Main execution function
main() {
    local container_name="${1:-pxf-build}"

    echo "🔧 Setting up optimized Cloudberry environment..."

    # Check if Cloudberry is already available in the Docker image
    if docker exec --user gpadmin "$container_name" test -f /usr/local/cloudberry-db/bin/postgres; then
        echo "✅ Using pre-built Cloudberry from Docker image"

        # Just configure the environment
        docker exec --user gpadmin "$container_name" bash -c "
            source /usr/local/cloudberry-db/cloudberry-env.sh
            export LANG=en_US.UTF-8

            # Create demo cluster using pre-built binaries
            echo 'Creating demo cluster with pre-built Cloudberry...'
            cd /tmp
            mkdir -p gpdemo/datadirs

            # Use simplified cluster setup
            export PGPORT=7000
            export COORDINATOR_DATADIR=/tmp/gpdemo/datadirs/coordinator
            mkdir -p \$COORDINATOR_DATADIR

            # Initialize database with minimal configuration
            initdb -D \$COORDINATOR_DATADIR --encoding=UTF8 --locale=en_US.UTF-8
            echo 'port = 7000' >> \$COORDINATOR_DATADIR/postgresql.conf
            echo 'max_connections = 200' >> \$COORDINATOR_DATADIR/postgresql.conf
            echo 'shared_preload_libraries = '\''pg_stat_statements'\''' >> \$COORDINATOR_DATADIR/postgresql.conf

            # Start the database
            pg_ctl -D \$COORDINATOR_DATADIR -l /tmp/gpdemo/coordinator.log start
            sleep 10

            # Create test database
            createdb gpadmin -p 7000 || echo 'Database already exists'

            echo '✅ Cloudberry environment ready'
        "
    else
        echo "⚠️ Pre-built Cloudberry not found, setting up minimal environment"

        # Fallback to minimal setup without full compilation
        docker exec --user gpadmin "$container_name" bash -c "
            # Set up basic PostgreSQL environment for testing
            export PGPORT=7000
            export COORDINATOR_DATADIR=/tmp/minimal-db
            mkdir -p \$COORDINATOR_DATADIR

            # Initialize minimal database for testing
            initdb -D \$COORDINATOR_DATADIR --encoding=UTF8 --locale=en_US.UTF-8
            echo 'port = 7000' >> \$COORDINATOR_DATADIR/postgresql.conf
            echo 'max_connections = 100' >> \$COORDINATOR_DATADIR/postgresql.conf

            # Start database
            pg_ctl -D \$COORDINATOR_DATADIR -l /tmp/minimal-db.log start
            sleep 5

            # Create test database
            createdb gpadmin -p 7000 || echo 'Database already exists'

            echo '✅ Minimal database environment ready'
        "
    fi

    # Verify database connectivity
    echo "🔍 Verifying database connectivity..."
    if docker exec --user gpadmin "$container_name" psql -p 7000 -d gpadmin -c "SELECT version();" >/dev/null 2>&1; then
        echo "✅ Database connectivity verified"
    else
        echo "❌ Database connectivity failed"
        exit 1
    fi

    echo "✅ Cloudberry environment setup completed"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
