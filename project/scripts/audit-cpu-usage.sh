#!/bin/bash

# Audit CPU usage to find inefficiencies

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_section() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo ""
print_section "CPU Usage Audit"

echo ""
print_section "1. Total CPU Requested by Pod Type"
kubectl get pods -o json | jq -r '.items[] | "\(.metadata.name)\t\(.spec.containers[0].resources.requests.cpu // "0")\t\(.status.phase)"' | \
  awk -F'\t' '
  {
    name = $1
    cpu = $2
    phase = $3
    gsub(/[^0-9]/, "", cpu)
    cpu_num = cpu + 0
    if (cpu_num > 0) {
      if (name ~ /service/) type = "Services"
      else if (name ~ /mongodb/) type = "MongoDB"
      else if (name ~ /redis/) type = "Redis"
      else if (name ~ /memcached/) type = "Memcached"
      else if (name ~ /nginx/) type = "Nginx"
      else if (name ~ /jaeger/) type = "Jaeger"
      else type = "Other"
      
      type_cpu[type] += cpu_num
      if (phase == "Pending") pending_cpu[type] += cpu_num
      if (phase == "Running") running_cpu[type] += cpu_num
    }
  }
  END {
    printf "%-20s %12s %12s %12s\n", "Type", "Total CPU", "Running", "Pending"
    printf "%s\n", "----------------------------------------------------------------"
    for (type in type_cpu) {
      printf "%-20s %8dm %12s %12s\n", type, type_cpu[type], 
        running_cpu[type] ? running_cpu[type] "m" : "0m",
        pending_cpu[type] ? pending_cpu[type] "m" : "0m"
    }
  }' 2>/dev/null || echo "jq not installed, showing raw data..."

echo ""
print_section "2. Pods Consuming Most CPU"
echo "Checking actual CPU usage (if metrics available):"
kubectl top pods --sort-by=cpu 2>/dev/null | head -20 || print_warn "kubectl top not available (metrics-server may not be running)"

echo ""
print_section "3. Duplicate Pods (Same Deployment)"
echo "Looking for pods from same deployment that could be duplicates:"
kubectl get pods -o json | jq -r '.items[] | "\(.metadata.ownerReferences[0].name // "none")\t\(.metadata.name)\t\(.status.phase)"' | \
  awk -F'\t' '{deploy[$1]++} END {for (d in deploy) if (deploy[d] > 1) print d ": " deploy[d] " pods"}' 2>/dev/null || \
  kubectl get pods | awk '{print $1}' | cut -d'-' -f1-4 | sort | uniq -d

echo ""
print_section "4. Resource Request Summary"
print_info "Current resource requests in deployments:"
echo ""
echo "Services (11 × 100m):     1100m"
echo "Databases (estimated):    ~2000m"
echo "Other (nginx, jaeger):    ~500m"
echo "--------------------------------"
echo "Total estimated:          ~3600m"
echo ""
print_warn "But you're requesting 5685m - let's find where the extra ~2000m is coming from!"

echo ""
print_section "5. Recommendations"
print_info "Before scaling to 3 nodes, consider:"
echo "  1. Reducing database resource requests (they may be too high)"
echo "  2. Deleting duplicate pods"
echo "  3. Reducing service replicas if you have multiple per service"
echo "  4. Checking if some pods have much higher requests than needed"

