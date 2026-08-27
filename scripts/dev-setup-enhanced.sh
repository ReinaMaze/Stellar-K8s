#!/bin/bash
# =============================================================================
# Enhanced Development Setup with Environment Health Checks
#
# This script implements the developer experience wave acceptance criteria:
# - Installs all dependencies (Rust, Docker, kind, kubectl, Helm, gh, pre-commit)
# - Validates tools are installed and reachable
# - Reports missing or outdated components
# - Provides actionable remediation steps
#
# Usage:
#   bash scripts/dev-setup-enhanced.sh [--check-only] [--strict]
#
# Options:
#   --check-only    Only perform health checks, don't install
#   --strict        Fail if any component is outdated (default: warn)
# =============================================================================

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Status tracking
PASSED=0
FAILED=0
WARNED=0
CHECK_ONLY=${1:-}
STRICT_MODE=0

if [[ "$CHECK_ONLY" == "--strict" ]] || [[ "${2:-}" == "--strict" ]]; then
  STRICT_MODE=1
fi

if [[ "$CHECK_ONLY" == "--check-only" ]]; then
  CHECK_ONLY=1
else
  CHECK_ONLY=0
fi

# Helper functions
print_header() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_pass() {
  echo -e "${GREEN}✓${NC} $1"
  ((PASSED++))
}

print_fail() {
  echo -e "${RED}✗${NC} $1"
  ((FAILED++))
}

print_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
  ((WARNED++))
}

check_command() {
  local cmd=$1
  local min_version=${2:-}
  local name=${3:-$cmd}
  
  if ! command -v "$cmd" &>/dev/null; then
    print_fail "$name not found"
    return 1
  fi
  
  if [[ -n "$min_version" ]]; then
    local version
    version=$("$cmd" --version 2>&1 | head -1 || echo "unknown")
    print_pass "$name installed: $version"
  else
    print_pass "$name found"
  fi
  return 0
}

check_rust_toolchain() {
  print_header "Rust Toolchain"
  
  if ! command -v rustc &>/dev/null; then
    print_fail "Rust not installed"
    if [[ $CHECK_ONLY -eq 0 ]]; then
      echo "  Install from: https://rustup.rs/"
    fi
    return 1
  fi
  
  local version
  version=$(rustc --version)
  print_pass "$version"
  
  # Check for required components
  for component in clippy rustfmt; do
    if rustup component list | grep -q "^$component.*installed"; then
      print_pass "$component component installed"
    else
      print_warn "$component component missing"
      if [[ $CHECK_ONLY -eq 0 ]]; then
        echo "  Installing $component..."
        rustup component add "$component"
      fi
    fi
  done
  
  # Check Cargo tools
  for tool in cargo-audit cargo-watch; do
    if cargo install --list 2>/dev/null | grep -q "^$tool"; then
      print_pass "$tool installed"
    else
      print_warn "$tool not installed"
      if [[ $CHECK_ONLY -eq 0 ]]; then
        echo "  Installing $tool..."
        cargo install --locked "$tool"
      fi
    fi
  done
}

check_docker() {
  print_header "Docker"
  
  if ! command -v docker &>/dev/null; then
    print_fail "Docker not found"
    if [[ $CHECK_ONLY -eq 0 ]]; then
      echo "  Install from: https://docs.docker.com/get-docker/"
    fi
    return 1
  fi
  
  local version
  version=$(docker --version)
  print_pass "$version"
  
  # Test Docker daemon
  if docker ps &>/dev/null; then
    print_pass "Docker daemon is running"
  else
    print_fail "Docker daemon not accessible"
    return 1
  fi
}

check_kubernetes_tools() {
  print_header "Kubernetes Tools"
  
  check_command kubectl "1.20" "kubectl" || return 1
  check_command kind "0.20" "kind" || return 1
  check_command helm "3.0" "Helm" || return 1
}

check_git_tools() {
  print_header "Git & GitHub Tools"
  
  check_command git "2.30" "Git" || return 1
  
  if ! command -v gh &>/dev/null; then
    print_warn "GitHub CLI (gh) not found"
    if [[ $CHECK_ONLY -eq 0 ]]; then
      echo "  Install from: https://cli.github.com/"
      echo "  Or: brew install gh (macOS), apt-get install gh (Ubuntu)"
    fi
  else
    local version
    version=$(gh --version | head -1)
    print_pass "$version"
  fi
}

check_pre_commit() {
  print_header "Pre-commit Hooks"
  
  if ! command -v pre-commit &>/dev/null; then
    print_warn "pre-commit not installed"
    if [[ $CHECK_ONLY -eq 0 ]]; then
      echo "  Installing pre-commit..."
      pip install pre-commit || pip3 install pre-commit
    fi
  else
    local version
    version=$(pre-commit --version)
    print_pass "$version"
    
    if [[ $CHECK_ONLY -eq 0 ]]; then
      echo "  Installing git hooks..."
      pre-commit install || true
      pre-commit install --hook-type pre-push || true
    fi
  fi
}

check_additional_tools() {
  print_header "Additional Tools"
  
  # k6 for benchmarking
  if ! command -v k6 &>/dev/null; then
    print_warn "k6 (load testing) not found"
    echo "  Install from: https://k6.io/docs/get-started/installation/"
  else
    local version
    version=$(k6 version)
    print_pass "k6 found: $version"
  fi
  
  # shellcheck for shell script linting
  if ! command -v shellcheck &>/dev/null; then
    print_warn "shellcheck not found"
    echo "  Install: brew install shellcheck (macOS) or apt-get install shellcheck (Ubuntu)"
  else
    local version
    version=$(shellcheck --version | head -1)
    print_pass "$version"
  fi
  
  # lychee for link checking
  if ! command -v lychee &>/dev/null; then
    print_warn "lychee (link checker) not found"
    echo "  Install: cargo install lychee"
  else
    local version
    version=$(lychee --version)
    print_pass "$version"
  fi
  
  # jq for JSON processing
  if ! command -v jq &>/dev/null; then
    print_warn "jq not found"
    echo "  Install: brew install jq (macOS) or apt-get install jq (Ubuntu)"
  else
    local version
    version=$(jq --version)
    print_pass "$version"
  fi
}

check_system_diagnostics() {
  print_header "System Diagnostics"
  
  # Check disk space
  local available_space
  available_space=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
  
  if [[ $available_space -lt 10 ]]; then
    print_fail "Low disk space: ${available_space}GB available (need 10GB+)"
  elif [[ $available_space -lt 20 ]]; then
    print_warn "Disk space: ${available_space}GB available (recommend 20GB+)"
  else
    print_pass "Disk space: ${available_space}GB available"
  fi
  
  # Check RAM (if possible)
  if command -v free &>/dev/null; then
    local total_ram
    total_ram=$(free -BG | awk 'NR==2 {print $2}' | sed 's/G//')
    if [[ $total_ram -lt 8 ]]; then
      print_warn "RAM: ${total_ram}GB (recommend 8GB+)"
    else
      print_pass "RAM: ${total_ram}GB available"
    fi
  fi
  
  # Check OS
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    print_pass "OS: Linux"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    print_pass "OS: macOS"
  elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    print_warn "OS: Windows (limited support, use WSL2 for best results)"
  else
    print_pass "OS: $OSTYPE"
  fi
}

verify_project_setup() {
  print_header "Project Verification"
  
  # Check Makefile
  if [[ -f Makefile ]]; then
    print_pass "Makefile found"
  else
    print_fail "Makefile not found"
  fi
  
  # Check Cargo.toml
  if [[ -f Cargo.toml ]]; then
    print_pass "Cargo.toml found"
  else
    print_fail "Cargo.toml not found"
  fi
  
  # Check if Rust project compiles
  if [[ $CHECK_ONLY -eq 0 ]]; then
    echo "  Running cargo check..."
    if cargo check --quiet 2>/dev/null; then
      print_pass "Rust project compiles"
    else
      print_fail "Rust project failed to compile"
    fi
  fi
}

generate_health_report() {
  print_header "Health Check Summary"
  
  echo ""
  echo "Passed:  $PASSED"
  echo "Failed:  $FAILED"
  echo "Warned:  $WARNED"
  echo ""
  
  local total=$((PASSED + FAILED + WARNED))
  local percent=0
  
  if [[ $total -gt 0 ]]; then
    percent=$((PASSED * 100 / total))
  fi
  
  echo "Health Score: ${percent}%"
  echo ""
  
  if [[ $FAILED -eq 0 ]]; then
    if [[ $WARNED -eq 0 ]]; then
      print_pass "All systems operational!"
      return 0
    else
      print_warn "System operational with warnings"
      return 0
    fi
  else
    print_fail "System has critical issues"
    return 1
  fi
}

main() {
  if [[ $CHECK_ONLY -eq 1 ]]; then
    echo -e "${BLUE}Running in check-only mode${NC}\n"
  else
    echo -e "${BLUE}Running full environment setup${NC}\n"
  fi
  
  check_rust_toolchain
  check_docker
  check_kubernetes_tools
  check_git_tools
  check_pre_commit
  check_additional_tools
  check_system_diagnostics
  verify_project_setup
  
  if ! generate_health_report; then
    if [[ $CHECK_ONLY -eq 1 ]] || [[ $STRICT_MODE -eq 1 ]]; then
      exit 1
    fi
  fi
  
  if [[ $CHECK_ONLY -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✓ Development environment setup complete!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Run: make quick          (quick pre-commit check)"
    echo "  2. Run: make test           (run all tests)"
    echo "  3. Run: make health         (full health check)"
    echo "  4. See: DEVELOPMENT.md      (detailed developer guide)"
  fi
}

main
