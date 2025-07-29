#!/usr/bin/env bash

# Test script for Saturn TURN server metrics
# This script demonstrates how to test the metrics endpoints

set -e

METRICS_HOST="localhost"
METRICS_PORT="9090"
BASE_URL="http://${METRICS_HOST}:${METRICS_PORT}"

# Check if running in Docker Compose environment
if docker ps | grep -q "saturn-saturn-1" && ! curl -s -f "${BASE_URL}/health" > /dev/null 2>&1; then
    echo "🐳 Docker Compose environment detected!"
    echo "======================================="
    echo
    echo "It looks like you're running Saturn in Docker Compose where"
    echo "the metrics port is not exposed externally for security."
    echo
    echo "Please use the Docker Compose-compatible test script instead:"
    echo "  ./scripts/test-metrics-docker.sh"
    echo
    echo "This script tests Saturn metrics through Prometheus at:"
    echo "  - Prometheus: http://localhost:9091"
    echo "  - Grafana: http://localhost:3000 (admin/admin)"
    echo
    exit 0
fi

echo "Testing Saturn TURN Server Metrics Endpoints"
echo "============================================="

# Test health endpoint
echo
echo "1. Testing Health Endpoint..."
echo "GET ${BASE_URL}/health"
if curl -s -f "${BASE_URL}/health" > /dev/null; then
    echo "Health endpoint is accessible"
else
    echo "❌ Health endpoint failed"
    exit 1
fi

# Test info endpoint
echo
echo "2. Testing Info Endpoint..."
echo "GET ${BASE_URL}/info"
curl -s "${BASE_URL}/info" | jq '.' 2>/dev/null || curl -s "${BASE_URL}/info"

# Test metrics endpoint
echo
echo
echo "3. Testing Metrics Endpoint..."
echo "GET ${BASE_URL}/metrics"
echo
echo "Sample metrics output:"
echo "======================"
curl -s "${BASE_URL}/metrics" | head -20

echo
echo "4. Checking for Saturn-specific metrics..."
SATURN_METRICS=$(curl -s "${BASE_URL}/metrics" | grep -c "saturn_" || echo "0")
echo "Found ${SATURN_METRICS} Saturn-specific metrics"

if [ "$SATURN_METRICS" -gt 0 ]; then
    echo "Saturn metrics are being exported"
    echo
    echo "Available Saturn metrics:"
    curl -s "${BASE_URL}/metrics" | grep "^# HELP saturn_" | sed 's/^# HELP /- /'
else
    echo "No Saturn metrics found (server may not have received any traffic yet)"
fi

echo
echo "Test completed!"
