#!/bin/bash

# Find pods with memory problems

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}=== Finding Memory Problems ===${NC}"
echo ""

# Check for OOMKilled
echo "1. OOMKilled pods:"
OOM=$(kubectl get pods | grep -i "oom" || echo "None found")
echo "$OOM"
echo ""

# Check for Evicted
echo "2. Evicted pods:"
EVICTED=$(kubectl get pods | grep -i "evicted" || echo "None found")
echo "$EVICTED"
echo ""

# Check CrashLoopBackOff (may be memory)
echo "3. CrashLoopBackOff pods:"
CRASH=$(kubectl get pods | grep "CrashLoopBackOff" || echo "None found")
echo "$CRASH"
echo ""

# Check ContainerCreating (may be waiting for resources)
echo "4. ContainerCreating pods:"
CREATING=$(kubectl get pods | grep "ContainerCreating" || echo "None found")
echo "$CREATING"
echo ""

# Check Pending (may be resource constraints)
echo "5. Pending pods:"
PENDING=$(kubectl get pods | grep "Pending" || echo "None found")
echo "$PENDING"
echo ""

# Node memory status
echo "6. Node memory capacity:"
kubectl describe nodes | grep -E "Allocatable:|Allocated resources:" -A 5 | grep -i memory || true
echo ""

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
TOTAL_ISSUES=0

if echo "$OOM" | grep -q "NAME\|OOMKilled"; then
    TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
fi
if echo "$EVICTED" | grep -q "NAME\|Evicted"; then
    TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
fi
if echo "$CRASH" | grep -q "CrashLoopBackOff"; then
    TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
fi
if echo "$CREATING" | grep -q "ContainerCreating"; then
    TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
fi
if echo "$PENDING" | grep -q "Pending"; then
    TOTAL_ISSUES=$((TOTAL_ISSUES + 1))
fi

if [ "$TOTAL_ISSUES" -eq 0 ]; then
    echo -e "${GREEN}✓ No obvious memory problems found!${NC}"
    echo "Run './scripts/audit-memory.sh' for detailed analysis."
else
    echo -e "${YELLOW}Found $TOTAL_ISSUES type(s) of issues.${NC}"
    echo "Run './scripts/audit-memory.sh' for detailed analysis."
fi

