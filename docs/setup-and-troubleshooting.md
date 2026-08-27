# Setup and Troubleshooting Guide

This guide covers developer environment setup, health checks, and troubleshooting for Stellar-K8s.

## Table of Contents

- [Quick Start](#quick-start)
- [Environment Setup](#environment-setup)
- [Health Checks](#health-checks)
- [Troubleshooting](#troubleshooting)
- [Monitoring & Observability](#monitoring--observability)

---

## Quick Start

For a fresh clone, run these commands:

```bash
git clone https://github.com/OtowoOrg/Stellar-K8s.git
cd Stellar-K8s

# One-time setup with environment health checks
make dev-setup

# Verify everything works
make health

# Start developing
make quick          # Fast pre-commit check
make test           # Run all tests
```

---

## Environment Setup

### Prerequisites

The enhanced `make dev-setup` command now validates your environment during setup.

**Requirements:**
- **Rust** — Latest stable (installed automatically)
- **Docker** — Latest version with daemon running
- **Kubernetes Tools** — kind, kubectl, helm (3.0+)
- **Git Tools** — git, gh CLI
- **Additional Tools** — pre-commit, shellcheck, k6, jq

### One-Command Setup

```bash
make dev-setup
```

This installs and validates:
1. Rust toolchain + clippy + rustfmt
2. Cargo development tools (cargo-audit, cargo-watch)
3. Pre-commit hooks for git integration
4. Environment health checks

### Step-by-Step Setup

If you prefer manual setup:

```bash
# 1. Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
rustup component add clippy rustfmt

# 2. Install Docker
# See: https://docs.docker.com/get-docker/

# 3. Install Kubernetes tools
brew install kind kubectl helm          # macOS
apt-get install -y kind kubectl helm    # Ubuntu/Debian

# 4. Install GitHub CLI
brew install gh                         # macOS
apt-get install -y gh                   # Ubuntu/Debian

# 5. Install pre-commit hooks
pip install pre-commit
make dev-setup-hooks

# 6. Verify setup
make dev-setup-check
```

### Environment Health Checks

Check your environment without making changes:

```bash
make dev-setup-check
```

This performs:
- Rust toolchain validation
- Docker daemon connectivity
- Kubernetes tool versions
- Disk space and RAM availability
- System compatibility checks

For strict validation (fails on outdated components):

```bash
make dev-setup-strict
```

---

## Health Checks

### Quick Health Check

```bash
make health-fast
```

Runs: formatting check, lint, compilation

### Full Health Check

```bash
make health
```

Runs all checks:
- Code formatting
- Linting (clippy)
- Compilation
- Unit tests
- Documentation validation
- Link checking

### Preflight Check

```bash
make preflight
```

Verifies:
- All required tools are installed
- Tool versions meet minimum requirements
- Repository structure is valid

---

## Troubleshooting

### Common Issues

#### 1. Rust Not Found

```bash
error: 'rustc' is not found
```

**Solution:**
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env
```

#### 2. Docker Daemon Not Running

```bash
error: Cannot connect to Docker daemon
```

**Solution:**
- macOS: Open Docker Desktop application
- Linux: `sudo systemctl start docker`
- Verify: `docker ps` should list running containers

#### 3. Kind Cluster Creation Failed

```bash
error: failed to load image into cluster
```

**Solution:**
```bash
# Clean up previous cluster
kind delete cluster --name stellar-dev

# Try again
make quickstart-setup
```

#### 4. Cargo Build Fails

```bash
error: linker 'cc' not found
```

**Solution (Ubuntu/Debian):**
```bash
apt-get install -y build-essential
```

**Solution (macOS):**
```bash
xcode-select --install
```

#### 5. Pre-commit Hook Failures

```bash
error: Pre-commit hook failed
```

**Solution:**
```bash
# Run hooks manually to see details
make pre-commit

# Install missing tools
make dev-setup

# Stage changes and try commit again
git add .
git commit -m "message"
```

#### 6. Test Failures

```bash
test result: FAILED
```

**Solution:**
```bash
# Run tests with verbose output
cargo test --verbose

# Run specific test
cargo test test_name -- --nocapture

# Check dependencies
cargo update

# Clean and rebuild
cargo clean
cargo test
```

#### 7. Out of Disk Space

```bash
error: no space left on device
```

**Solution:**
```bash
# Clean build artifacts
make clean

# Remove Docker dangling images
docker image prune -a

# Check available space
df -h
```

#### 8. High Memory Usage

```bash
error: cannot allocate memory
```

**Solution:**
```bash
# Reduce parallel build jobs
cargo build -j 1

# Increase system swap (if needed)
# Or increase Docker Desktop memory allocation
```

---

## Monitoring & Observability

### Metrics

The operator exposes Prometheus metrics on port 8080:

```bash
curl http://localhost:8080/metrics
```

Key metrics:
- `stellar_operator_uptime_seconds_total` — Operator uptime
- `stellar_operator_reconciliation_duration_seconds` — Reconciliation time
- `stellar_core_ledger_tps` — Transactions per second
- `stellar_core_ledger_lag_seconds` — Ledger lag
- `stellar_core_node_up` — Node health

### Grafana Dashboards

After deploying with monitoring:

1. **Cluster Overview** — Network-wide metrics
   - TPS, ledger lag, node health
   - Byzantine fault tolerance
   - Quorum connectivity

2. **Per-Node Stats** — Individual node metrics
   - Pod resource usage
   - Storage usage
   - Transaction processing latency

3. **Alerting Dashboard** — Active alerts and incidents
   - Critical issues
   - Warning conditions
   - Historical trends

### Logging

View operator logs:

```bash
# Local development
RUST_LOG=debug cargo run

# In Kubernetes
kubectl logs -f deployment/stellar-operator -n stellar-system
```

Set log levels:
- `RUST_LOG=error` — Only errors
- `RUST_LOG=warn` — Errors and warnings
- `RUST_LOG=info` — General information
- `RUST_LOG=debug` — Detailed debugging
- `RUST_LOG=trace` — Very detailed tracing

### Benchmarks

Run performance benchmarks:

```bash
# All benchmarks
make benchmark-all

# Specific benchmark
make benchmark              # k6 operator load test
make benchmark-webhook      # Webhook performance
make benchmark-upgrade      # Upgrade load test
```

View baseline comparisons:

```bash
bash benchmarks/benchmark-suite.sh all --save-baseline
```

---

## Advanced Configuration

### Environment Variables

Development environment variables:

```bash
# Logging
export RUST_LOG=debug
export RUST_BACKTRACE=1

# Kubernetes API
export KUBECONFIG=$HOME/.kube/config

# Docker
export DOCKER_HOST=unix:///var/run/docker.sock
```

### Makefile Targets

Full list of available commands:

```bash
make help
```

Common workflows:

```bash
# Development iteration
make quick              # Fast check (format + compile)
make test               # Full test suite
make health             # Complete health check

# CI pipeline locally
make ci-local           # Run all CI checks locally

# Building and deployment
make build              # Release build
make docker-build       # Local Docker image
make quickstart         # Full local deployment

# Documentation
make docs-lint          # Check documentation
make link-check         # Validate markdown links

# Cleanup
make cleanup            # Remove scratch files
make clean              # Remove build artifacts
```

### Performance Tuning

For faster builds on slower machines:

```bash
# Use system linker (faster)
export RUSTFLAGS="-C link-arg=-fuse-ld=lld"

# Limit parallel jobs
cargo build -j 2

# Use incremental compilation
export CARGO_INCREMENTAL=1
```

---

## Getting Help

### Documentation

- **Developer Guide** — `DEVELOPMENT.md`
- **Architecture** — `docs/architecture/`
- **Troubleshooting** — `.github/CI_TROUBLESHOOTING.md`
- **API Reference** — `docs/api-reference.md`

### Community

- **Issues** — GitHub Issues with detailed setup info
- **Discussions** — GitHub Discussions for questions
- **Contributing** — `CONTRIBUTING.md` for workflow

### Debug Information

Collect debug information for issue reports:

```bash
# Environment summary
rustc --version
cargo --version
docker --version
kubectl version
helm version
git --version

# Health check output
make dev-setup-check > ~/stellar-debug.txt

# Attach to issue
```

---

## Issue Reporting

When reporting issues, include:

1. **Environment:**
   - OS and version
   - Rust version (`rustc --version`)
   - Docker version
   - Kubernetes tools versions

2. **Steps to reproduce:**
   - Exact commands run
   - Output with errors
   - Any relevant configuration

3. **Debug output:**
   ```bash
   make dev-setup-check
   make health
   cargo test -- --nocapture 2>&1
   ```

4. **System resources:**
   ```bash
   uname -a
   df -h
   free -h      # Linux
   vm_stat      # macOS
   ```

---

## Next Steps

After successful setup:

1. **Quick check:** `make quick`
2. **Run tests:** `make test`
3. **Full health:** `make health`
4. **Deploy locally:** `make quickstart`
5. **Read docs:** See `DEVELOPMENT.md` for detailed workflow

For issues, see the [Troubleshooting](#troubleshooting) section or open a GitHub issue with debug output.
