# PXF GitHub Actions CI/CD for Apache/Cloudberry

This document describes the GitHub Actions-based CI/CD pipeline that replaces the previous Concourse-based system for PXF integration with Apache/Cloudberry Database.

## Overview

The GitHub Actions workflow provides automated testing, building, and deployment of PXF (Platform Extension Framework) adapted for Apache/Cloudberry Database, replacing the previous Greenplum-focused Concourse pipelines.

## Workflow Files

### Main CI Workflow (`.github/workflows/ci.yml`)

The primary workflow that runs on every push and pull request:

**Jobs:**
- `build-matrix`: Builds PXF components across multiple OS and Java versions
- `smoke-tests`: Runs basic functionality tests
- `integration-tests`: Tests with Hadoop components (HDFS, Hive)
- `security-scan`: Performs security vulnerability scanning
- `code-quality`: Runs linting and code quality checks
- `deploy`: Handles artifact deployment (main branch only)

**Key Features:**
- Multi-platform support (Ubuntu 20.04, 22.04)
- Multiple Java versions (8, 11)
- Caching for Maven, Gradle, and Go dependencies
- Artifact generation (TAR, DEB packages)
- Security scanning with SARIF uploads

### Performance Testing Workflow (`.github/workflows/performance.yml`)

Extended testing for performance and compatibility:

**Triggers:**
- Nightly schedule (2 AM UTC)
- Manual dispatch with configurable test types

**Jobs:**
- `performance-tests`: Runs performance benchmarks with different Hadoop configurations
- `stress-tests`: Executes stress testing scenarios
- `compatibility-matrix`: Tests multiple version combinations
- `generate-test-report`: Aggregates results into comprehensive reports

## Key Adaptations for Apache/Cloudberry

### Database Integration Changes

1. **Greenplum → Cloudberry Migration:**
   - Uses PostgreSQL 14 as base (Cloudberry is PostgreSQL-based)
   - Adapts extension build process for Cloudberry compatibility
   - Modifies environment variables and paths

2. **Extension Compatibility:**
   - External table extension builds with PostgreSQL infrastructure
   - FDW extension may need Cloudberry-specific adaptations
   - Graceful handling of build failures during migration

3. **Configuration Adaptations:**
   - Modified `GPHOME` to point to PostgreSQL installation
   - Adjusted `PXF_HOME` and `PG_CONFIG` paths
   - Updated user and database setup for Cloudberry

### Resource Optimization for Public CI

1. **Limited Resource Usage:**
   - Selective test execution based on labels
   - Parallel job matrix with fail-fast disabled
   - Appropriate timeouts for different job types

2. **Artifact Management:**
   - Short retention periods (7-30 days)
   - Selective artifact upload based on primary builds
   - Compressed packaging for efficiency

3. **Conditional Execution:**
   - Integration tests only on labeled PRs or main branch
   - Performance tests limited to authorized repositories
   - Stress tests only on manual dispatch

## Comparison with Original Concourse Pipeline

### Features Retained
- ✅ Multi-component builds (external-table, FDW, CLI, server)
- ✅ Unit and integration testing
- ✅ Package creation (TAR, DEB)
- ✅ Hadoop ecosystem testing (HDFS, Hive, HBase)
- ✅ Security scanning
- ✅ Performance testing (scheduled)

### Features Adapted
- 🔄 **Database Platform**: Greenplum → Apache/Cloudberry
- 🔄 **Cloud Storage**: S3/MinIO/GCS → Simplified local testing
- 🔄 **Container Strategy**: Custom Docker images → GitHub Actions runners
- 🔄 **Resource Management**: Enterprise CI → Public CI limitations

### Features Simplified/Removed
- ❌ Multi-node Hadoop clusters (resource intensive)
- ❌ Enterprise cloud integrations (requires credentials)
- ❌ Complex multi-datacenter deployments
- ❌ Proprietary Greenplum-specific features
- ❌ RPM packaging (focused on DEB for Ubuntu/Debian)

## Environment Variables and Configuration

### Required Environment Variables
```bash
# PXF Configuration
PXF_VERSION=6.10.1-SNAPSHOT
PXF_API_VERSION=1.0.0

# Java Configuration
JAVA_VERSION=11

# Database Configuration  
PGPORT=5432
PGUSER=gpadmin
PGPASSWORD=gpadmin

# Cloudberry Configuration
CBDB_VERSION=1.0.0
```

### Build Dependencies
- **System**: build-essential, curl, unzip, maven, rpm, alien
- **Database**: postgresql-14, postgresql-server-dev-14
- **Languages**: OpenJDK 8/11, Go 1.19
- **Hadoop**: Apache Hadoop 3.3.4, Hive 3.1.3, HBase 2.4.17

## Usage Instructions

### Running Tests Locally

1. **Prerequisites:**
   ```bash
   sudo apt-get update
   sudo apt-get install -y build-essential maven postgresql-14 postgresql-server-dev-14
   ```

2. **Environment Setup:**
   ```bash
   export GPHOME=/usr/lib/postgresql/14
   export PXF_HOME=/usr/local/pxf
   export PG_CONFIG=/usr/lib/postgresql/14/bin/pg_config
   ```

3. **Build PXF:**
   ```bash
   make clean
   make all
   ```

### Triggering Workflows

1. **Automatic Triggers:**
   - Push to main/master/develop branches
   - Pull request creation/updates
   - Nightly performance tests (2 AM UTC)

2. **Manual Triggers:**
   - Use "Actions" tab in GitHub repository
   - Select workflow and click "Run workflow"
   - Configure parameters for performance tests

### Artifact Access

Built artifacts are available in the Actions tab:
- **Build artifacts**: TAR and DEB packages
- **Test reports**: JUnit XML, performance metrics
- **Security scans**: SARIF files uploaded to GitHub Security tab

## Migration from Concourse

### For Developers

1. **Local Development**: Same Makefile-based workflow
2. **Testing**: Enhanced with additional matrix combinations
3. **Packaging**: Simplified to focus on TAR and DEB formats
4. **Documentation**: Updated for Cloudberry integration

### For CI/CD Administrators

1. **Secret Management**: Use GitHub Secrets instead of Concourse credentials
2. **Resource Monitoring**: GitHub Actions usage limits apply
3. **Artifact Storage**: GitHub-managed with configurable retention
4. **Notifications**: GitHub native notifications and integrations

## Monitoring and Maintenance

### Regular Maintenance Tasks

1. **Dependency Updates:**
   - Dependabot automatically creates PRs for updates
   - Review and merge dependency updates weekly

2. **Performance Monitoring:**
   - Review nightly performance test results
   - Monitor for performance regressions

3. **Security Updates:**
   - Address security scan findings promptly
   - Keep base images and dependencies updated

### Troubleshooting Common Issues

1. **Build Failures:**
   - Check Java/Go version compatibility
   - Verify PostgreSQL installation and configuration
   - Review dependency cache invalidation

2. **Test Failures:**
   - Check Cloudberry-specific compatibility issues
   - Verify Hadoop configuration
   - Review resource limits and timeouts

3. **Integration Issues:**
   - Validate FDW extension builds with Cloudberry
   - Check external table extension compatibility
   - Test PXF server startup and configuration

## Future Enhancements

### Planned Improvements

1. **Enhanced Cloudberry Integration:**
   - Native Cloudberry installation instead of PostgreSQL fallback
   - Cloudberry-specific feature testing
   - Version compatibility matrix expansion

2. **Advanced Testing:**
   - Multi-node testing with containerized clusters
   - Extended cloud storage provider support
   - Automated performance regression detection

3. **Developer Experience:**
   - Pre-commit hooks for code quality
   - Development container configurations
   - Enhanced debugging capabilities

### Contributing

To contribute improvements to the CI/CD pipeline:

1. Fork the repository
2. Create feature branch for workflow changes
3. Test changes in your fork's Actions
4. Submit pull request with detailed description
5. Ensure all checks pass before merge

For questions or issues with the CI/CD pipeline, please create an issue using the provided templates.