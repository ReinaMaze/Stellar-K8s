#!/bin/bash
# =============================================================================
# Comprehensive Benchmark Suite for Stellar-K8s
#
# This script runs benchmarks for:
# - CRD validation performance
# - Helm chart rendering time
# - Operator API throughput
# - Webhook latency and throughput
#
# Establishes baseline numbers and integrates with CI for regression tracking.
#
# Usage:
#   bash benchmarks/benchmark-suite.sh [all|crd|helm|api|webhook] [--save-baseline]
#
# Issue: #wave-dx (Developer Experience Wave)
# =============================================================================

set -euo pipefail

# Configuration
BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${BENCHMARK_DIR}/results"
BASELINE_DIR="${BENCHMARK_DIR}/baselines"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
REGRESSION_THRESHOLD=10  # Percentage

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

mkdir -p "$RESULTS_DIR" "$BASELINE_DIR"

# Helper functions
print_header() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_pass() {
  echo -e "${GREEN}✓${NC} $1"
}

print_fail() {
  echo -e "${RED}✗${NC} $1"
}

print_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

# ─────────────────────────────────────────────────────────────────────────────
# CRD Validation Benchmark
# ─────────────────────────────────────────────────────────────────────────────

benchmark_crd_validation() {
  print_header "CRD Validation Performance Benchmark"
  
  local test_file="/tmp/stellar-crd-test.yaml"
  local result_file="$RESULTS_DIR/crd-validation-${TIMESTAMP}.json"
  
  # Generate test CRDs
  cat > "$test_file" << 'EOF'
apiVersion: stellar.org/v1alpha1
kind: StellarNode
metadata:
  name: test-node
  namespace: stellar-system
spec:
  image:
    repository: stellar/core
    tag: "21.5.0"
  resources:
    requests:
      cpu: "2"
      memory: "4Gi"
    limits:
      cpu: "4"
      memory: "8Gi"
  ledgerBackend: sqlite
  persistentVolume:
    enabled: true
    size: 500Gi
  networking:
    port: 11625
    httpPort: 11626
  archive:
    enabled: true
    url: "https://archive.stellar.org"
  quorum:
    threshold: 3
    validators:
      - name: "validator-1"
      - name: "validator-2"
      - name: "validator-3"
EOF
  
  print_info "Running CRD validation against $((100)) resources..."
  
  local times=()
  local errors=0
  
  for i in {1..100}; do
    local start
    local end
    local duration
    
    start=$(date +%s%N)
    
    if kubectl validate --filename="$test_file" --output=no &>/dev/null; then
      end=$(date +%s%N)
      duration=$(( (end - start) / 1000000 ))  # Convert to milliseconds
      times+=("$duration")
    else
      ((errors++))
    fi
  done
  
  # Calculate statistics
  local total=0
  local max=0
  local min="${times[0]}"
  
  for t in "${times[@]}"; do
    total=$((total + t))
    if (( t > max )); then max=$t; fi
    if (( t < min )); then min=$t; fi
  done
  
  local avg=$((total / ${#times[@]}))
  local p95=$((${#times[@]} * 95 / 100))
  
  # Generate JSON report
  cat > "$result_file" << EOF
{
  "benchmark": "crd-validation",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "samples": ${#times[@]},
  "errors": $errors,
  "latency_ms": {
    "min": $min,
    "max": $max,
    "avg": $avg,
    "p95": ${times[$p95]}
  }
}
EOF
  
  print_pass "CRD Validation: avg=${avg}ms, min=${min}ms, max=${max}ms"
  print_info "Results saved to: $result_file"
  
  rm -f "$test_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# Helm Chart Rendering Benchmark
# ─────────────────────────────────────────────────────────────────────────────

benchmark_helm_rendering() {
  print_header "Helm Chart Rendering Performance Benchmark"
  
  local result_file="$RESULTS_DIR/helm-rendering-${TIMESTAMP}.json"
  local times=()
  
  print_info "Running Helm template rendering 50 times..."
  
  for i in {1..50}; do
    local start
    local end
    local duration
    
    start=$(date +%s%N)
    
    if helm template stellar-operator charts/stellar-operator \
         --set image.tag=test \
         --set replicas=3 \
         > /dev/null 2>&1; then
      end=$(date +%s%N)
      duration=$(( (end - start) / 1000000 ))
      times+=("$duration")
    fi
  done
  
  # Calculate statistics
  local total=0
  local max=0
  local min="${times[0]}"
  
  for t in "${times[@]}"; do
    total=$((total + t))
    if (( t > max )); then max=$t; fi
    if (( t < min )); then min=$t; fi
  done
  
  local avg=$((total / ${#times[@]}))
  
  # Generate JSON report
  cat > "$result_file" << EOF
{
  "benchmark": "helm-rendering",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "samples": ${#times[@]},
  "latency_ms": {
    "min": $min,
    "max": $max,
    "avg": $avg
  }
}
EOF
  
  print_pass "Helm Rendering: avg=${avg}ms, min=${min}ms, max=${max}ms"
  print_info "Results saved to: $result_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# Operator API Throughput Benchmark
# ─────────────────────────────────────────────────────────────────────────────

benchmark_api_throughput() {
  print_header "Operator API Throughput Benchmark"
  
  local result_file="$RESULTS_DIR/api-throughput-${TIMESTAMP}.json"
  
  print_info "Building operator in release mode..."
  cargo build --release --quiet 2>/dev/null || true
  
  if [[ ! -f target/release/stellar-operator ]]; then
    print_fail "Operator binary not found"
    return 1
  fi
  
  print_info "Starting operator API server..."
  timeout 30 ./target/release/stellar-operator api --bind 127.0.0.1:8080 &
  local operator_pid=$!
  
  sleep 2  # Wait for server to start
  
  print_info "Running API throughput test (10 concurrent requests, 30 seconds)..."
  
  local total_requests=0
  local total_errors=0
  local start_time=$(date +%s)
  local end_time=$((start_time + 30))
  
  # Run concurrent requests
  for req in {1..300}; do
    {
      if curl -s -o /dev/null -w "%{http_code}" \
           "http://127.0.0.1:8080/api/v1/health" >/dev/null 2>&1; then
        ((total_requests++)) || true
      else
        ((total_errors++)) || true
      fi
    } &
    
    # Limit concurrency to 10
    if (( req % 10 == 0 )); then
      wait
    fi
  done
  
  wait
  
  local duration=$(($(date +%s) - start_time))
  local rps=$((total_requests / duration))
  
  kill $operator_pid 2>/dev/null || true
  wait $operator_pid 2>/dev/null || true
  
  # Generate JSON report
  cat > "$result_file" << EOF
{
  "benchmark": "api-throughput",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "duration_seconds": $duration,
  "total_requests": $total_requests,
  "total_errors": $total_errors,
  "requests_per_second": $rps,
  "error_rate": $(echo "scale=2; ($total_errors * 100) / ($total_requests + $total_errors)" | bc)
}
EOF
  
  print_pass "API Throughput: ${rps} req/s, errors: $total_errors"
  print_info "Results saved to: $result_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# Webhook Performance Benchmark
# ─────────────────────────────────────────────────────────────────────────────

benchmark_webhook() {
  print_header "Webhook Performance Benchmark"
  
  print_info "Running k6 webhook benchmark..."
  
  if ! command -v k6 &>/dev/null; then
    print_fail "k6 not found. Install from: https://k6.io/docs/get-started/installation/"
    return 1
  fi
  
  local result_file="$RESULTS_DIR/webhook-${TIMESTAMP}.json"
  
  k6 run \
    --vus 50 \
    --duration 30s \
    --out json="$result_file" \
    "${BENCHMARK_DIR}/k6/webhook-load-test.js" 2>/dev/null || true
  
  if [[ -f "$result_file" ]]; then
    print_pass "Webhook benchmark completed"
    print_info "Results saved to: $result_file"
  else
    print_fail "Webhook benchmark failed"
    return 1
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Baseline Comparison
# ─────────────────────────────────────────────────────────────────────────────

compare_with_baseline() {
  print_header "Baseline Comparison & Regression Detection"
  
  local baseline_file="${BASELINE_DIR}/benchmark-baseline.json"
  
  if [[ ! -f "$baseline_file" ]]; then
    print_info "No baseline found. Skipping regression check."
    return 0
  fi
  
  print_info "Comparing results with baseline..."
  
  # Extract latest results
  local latest_crd="$RESULTS_DIR/crd-validation-${TIMESTAMP}.json"
  local baseline_crd="$(jq -r '.crd_validation.file' "$baseline_file" 2>/dev/null || echo "none")"
  
  if [[ "$baseline_crd" != "none" && -f "$baseline_crd" ]]; then
    local baseline_avg=$(jq '.latency_ms.avg' "$baseline_crd")
    local current_avg=$(jq '.latency_ms.avg' "$latest_crd")
    local regression_pct=$(echo "scale=2; (($current_avg - $baseline_avg) * 100) / $baseline_avg" | bc)
    
    if (( $(echo "$regression_pct > $REGRESSION_THRESHOLD" | bc -l) )); then
      print_fail "CRD Validation regression detected: +${regression_pct}% (threshold: ${REGRESSION_THRESHOLD}%)"
      return 1
    else
      print_pass "CRD Validation within threshold: ${regression_pct}%"
    fi
  fi
  
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Save Baseline
# ─────────────────────────────────────────────────────────────────────────────

save_baseline() {
  print_header "Saving Current Results as Baseline"
  
  local baseline_file="${BASELINE_DIR}/benchmark-baseline.json"
  
  cat > "$baseline_file" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "crd_validation": {
    "file": "$RESULTS_DIR/crd-validation-${TIMESTAMP}.json"
  },
  "helm_rendering": {
    "file": "$RESULTS_DIR/helm-rendering-${TIMESTAMP}.json"
  },
  "api_throughput": {
    "file": "$RESULTS_DIR/api-throughput-${TIMESTAMP}.json"
  },
  "webhook": {
    "file": "$RESULTS_DIR/webhook-${TIMESTAMP}.json"
  }
}
EOF
  
  print_pass "Baseline saved to: $baseline_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# Generate Report
# ─────────────────────────────────────────────────────────────────────────────

generate_report() {
  print_header "Benchmark Summary Report"
  
  echo ""
  echo "Results Directory: $RESULTS_DIR"
  echo "Generated Files:"
  ls -1 "$RESULTS_DIR"/benchmark-* 2>/dev/null | while read -r file; do
    echo "  - $(basename "$file")"
  done
  echo ""
  
  echo "Recommendations:"
  echo "  1. Review results in: $RESULTS_DIR/"
  echo "  2. Save baseline:     $0 --save-baseline"
  echo "  3. Export results:    jq -r '.latency_ms' $RESULTS_DIR/*.json"
  echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

main() {
  local suite="${1:-all}"
  local save_baseline="${2:-}"
  
  print_header "Stellar-K8s Benchmark Suite"
  print_info "Timestamp: $(date)"
  echo ""
  
  case "$suite" in
    all)
      benchmark_crd_validation
      benchmark_helm_rendering
      benchmark_api_throughput
      benchmark_webhook
      ;;
    crd)
      benchmark_crd_validation
      ;;
    helm)
      benchmark_helm_rendering
      ;;
    api)
      benchmark_api_throughput
      ;;
    webhook)
      benchmark_webhook
      ;;
    *)
      echo "Usage: $0 [all|crd|helm|api|webhook] [--save-baseline]"
      exit 1
      ;;
  esac
  
  echo ""
  compare_with_baseline
  
  if [[ "$save_baseline" == "--save-baseline" ]]; then
    save_baseline
  fi
  
  generate_report
  
  print_pass "Benchmark suite completed"
}

main "$@"
