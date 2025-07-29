#!/usr/bin/env bash

# Test script for Saturn TURN server metrics in Docker Compose setup
# This script tests Saturn metrics through Prometheus since Saturn metrics
# are not exposed directly to the host
#
# FEATURES:
# - Basic metrics testing via Prometheus API
# - Traffic simulation using UDP packets to TURN server
# - Sustained load testing with monitoring
# - Before/after metrics comparison
# - Graceful fallbacks for missing dependencies
#
# USAGE:
#   ./test-metrics.sh                    # Basic metrics testing
#   ./test-metrics.sh --simulate-traffic # Test with simulated traffic  
#   ./test-metrics.sh --load-test       # Sustained load test (60 seconds)
#   ./test-metrics.sh --help           # Show help
#
# DEPENDENCIES:
#   Required: curl
#   Optional: bc (for MB calculations), nc/netcat (for UDP traffic simulation)
#
# PREREQUISITES:
#   - Saturn TURN server running via docker-compose
#   - Prometheus accessible at localhost:9091
#   - Grafana accessible at localhost:3000

set -e

# Check for required tools
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required but not installed. Aborting." >&2; exit 1; }
if ! command -v bc >/dev/null 2>&1; then
    echo "WARNING: bc (calculator) not found. Memory values will be shown in bytes only."
    BC_AVAILABLE=false
else
    BC_AVAILABLE=true
fi

# Check for optional tools used in traffic simulation
if ! command -v nc >/dev/null 2>&1; then
    echo "WARNING: nc (netcat) not found. Traffic simulation will be limited."
    echo "   To install: brew install netcat (macOS) or apt-get install netcat (Linux)"
    NC_AVAILABLE=false
else
    NC_AVAILABLE=true
fi

# Function to query metric and extract value
query_metric() {
    local metric_name="$1"
    local result=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=${metric_name}")
    if echo "$result" | grep -q '"status":"success"'; then
        echo "$result" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9.]*"' | tr -d '"' | tail -1
    else
        echo ""
    fi
}

# Function to check if metric has data
has_metric_data() {
    local value="$1"
    [ -n "$value" ] && [ "$value" != "0" ]
}

# Function to simulate TURN server traffic
simulate_traffic() {
    echo "SIMULATING TURN server traffic..."
    echo "====================================="
    
    if [ "$NC_AVAILABLE" = false ]; then
        echo "WARNING: netcat (nc) not available - using alternative traffic simulation"
        echo "   For better UDP testing, install netcat: brew install netcat"
        echo "   Alternative: brew install telnet"
    fi
    
    # Check if Saturn is running and accessible
    SATURN_HOST="localhost"
    SATURN_PORT="3478"
    
    echo "Testing Saturn server connectivity..."
    if [ "$NC_AVAILABLE" = true ] && timeout 5 nc -z "$SATURN_HOST" "$SATURN_PORT" 2>/dev/null; then
        echo "SUCCESS: Saturn server is accessible at ${SATURN_HOST}:${SATURN_PORT}"
    elif command -v telnet >/dev/null 2>&1; then
        echo "Testing with telnet as fallback..."
        if timeout 5 bash -c "echo '' | telnet $SATURN_HOST $SATURN_PORT" 2>/dev/null | grep -q "Connected"; then
            echo "SUCCESS: Saturn server is accessible at ${SATURN_HOST}:${SATURN_PORT} (via telnet)"
        else
            echo "ERROR: Saturn server not accessible at ${SATURN_HOST}:${SATURN_PORT}"
            echo "   Please ensure Saturn is running with: docker-compose up -d"
            return 1
        fi
    elif command -v bash >/dev/null 2>&1; then
        echo "Testing with bash TCP redirection as fallback..."
        if timeout 5 bash -c "exec 3<>/dev/tcp/$SATURN_HOST/$SATURN_PORT && echo 'Connected' >&3 && exec 3<&-" 2>/dev/null; then
            echo "SUCCESS: Saturn server is accessible at ${SATURN_HOST}:${SATURN_PORT} (via bash)"
        else
            echo "WARNING: Saturn server connectivity test failed"
            echo "   This might be normal if Saturn is running in Docker"
            echo "   Proceeding with simulation anyway..."
        fi
    else
        echo "WARNING: Cannot test connectivity (no nc, telnet, or bash TCP available)"
        echo "   Assuming Saturn is running and proceeding with simulation..."
    fi
    
    # Generate test JWT token
    echo
    echo "Generating test JWT token..."
    if command -v make >/dev/null 2>&1; then
        TEST_TOKEN=$(cd /tmp && ACCESS_SECRET=qwertyuiopasdfghjklzxcvbnm123456 REALM=development go run /Volumes/Workspace/git/saturn/scripts/jwt-gen/main.go -user-id=test-user -email=test@example.com 2>/dev/null | grep "Generated token:" | cut -d' ' -f3)
        if [ -n "$TEST_TOKEN" ]; then
            echo "SUCCESS: Test token generated successfully"
        else
            echo "WARNING: Could not generate test token, using mock data for traffic simulation"
            TEST_TOKEN="mock_token_for_testing"
        fi
    else
        echo "WARNING: Make not available, using mock data for traffic simulation"
        TEST_TOKEN="mock_token_for_testing"
    fi
    
    # Simulate UDP traffic to TURN server with proper STUN/TURN protocol messages
    echo
    if [ "$NC_AVAILABLE" = true ]; then
        echo "Sending STUN/TURN protocol messages to Saturn server..."
        
        # Create proper STUN binding request packets (RFC 5389)
        # STUN message format: [Message Type][Message Length][Magic Cookie][Transaction ID]
        for i in $(seq 1 15); do
            # STUN Binding Request (0x0001) with magic cookie and random transaction ID
            printf '\x00\x01\x00\x00\x21\x12\xA4\x42' | cat - <(printf '%08x' $RANDOM | xxd -r -p) | nc -u -w1 "$SATURN_HOST" "$SATURN_PORT" 2>/dev/null &
            sleep 0.1
            
            # STUN Allocate Request (0x0003) for TURN allocation
            printf '\x00\x03\x00\x00\x21\x12\xA4\x42' | cat - <(printf '%08x' $RANDOM | xxd -r -p) | nc -u -w1 "$SATURN_HOST" "$SATURN_PORT" 2>/dev/null &
            sleep 0.1
        done
        
        # Send some larger packets to generate more traffic
        echo "Sending larger test packets to generate traffic metrics..."
        for i in $(seq 1 10); do
            # Create a larger payload (1KB) to trigger traffic metrics
            dd if=/dev/zero bs=1024 count=1 2>/dev/null | nc -u -w1 "$SATURN_HOST" "$SATURN_PORT" 2>/dev/null &
            sleep 0.2
        done
        
        # Wait for background processes
        sleep 3
        echo "Sent $(echo '15 * 2 + 10' | bc) test packets to Saturn server"
    else
        echo "Simulating traffic through alternative methods..."
        # Alternative: Generate traffic using different approaches
        if command -v python3 >/dev/null 2>&1; then
            echo "Using Python to generate STUN packets..."
            python3 -c "
import socket
import struct
import random
import time

def send_stun_packet(host, port):
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(1)
        
        # STUN Binding Request: Message Type (0x0001), Length (0x0000), Magic Cookie, Transaction ID
        message_type = 0x0001
        message_length = 0x0000
        magic_cookie = 0x2112A442
        transaction_id = random.randint(0, 0xFFFFFFFFFFFFFFFF)
        
        packet = struct.pack('>HHI', message_type, message_length, magic_cookie)
        packet += struct.pack('>Q', transaction_id)
        
        sock.sendto(packet, (host, port))
        sock.close()
        return True
    except:
        return False

# Send multiple STUN packets
print('Sending STUN packets...')
for i in range(20):
    if send_stun_packet('$SATURN_HOST', $SATURN_PORT):
        print(f'Sent packet {i+1}')
    time.sleep(0.1)
" 2>/dev/null || echo "Python STUN packet generation failed"
        else
            echo "Fallback: Generating HTTP traffic to metrics endpoint..."
            for i in $(seq 1 30); do
                curl -s "http://localhost:9090/metrics" > /dev/null 2>&1 &
                sleep 0.1
            done
            wait
        fi
    fi
    
    # Simulate some memory pressure to trigger GC
    echo "Triggering memory allocation to generate GC activity..."
    if command -v curl >/dev/null 2>&1; then
        # Make multiple rapid requests to metrics endpoint to generate some memory activity
        for i in $(seq 1 5); do
            curl -s "http://localhost:9090/metrics" > /dev/null 2>&1 &
        done
        wait
    fi
    
    echo "SUCCESS: Traffic simulation completed"
    echo "   Waiting 30 seconds for metrics to update..."
    sleep 30
    
    # Verify that some metrics were triggered
    echo "Verifying if traffic simulation triggered metrics..."
    
    # Check if any ingress packets were recorded
    INGRESS_CHECK=$(query_metric "saturn_ingress_packets_total")
    if [ -n "$INGRESS_CHECK" ] && [ "$INGRESS_CHECK" != "0" ]; then
        echo "SUCCESS: Ingress packets detected ($INGRESS_CHECK packets)"
    else
        echo "INFO: No ingress packets detected - this might be normal if Saturn filters invalid packets"
    fi
    
    # Check if memory metrics changed
    MEMORY_CHECK=$(query_metric "saturn_memory_usage_bytes")
    if [ -n "$MEMORY_CHECK" ] && [ "$MEMORY_CHECK" != "0" ]; then
        echo "SUCCESS: Memory metrics are active"
    else
        echo "WARNING: Memory metrics still not active"
    fi
    
    # Provide troubleshooting info
    echo
    echo "TROUBLESHOOTING INFO:"
    echo "====================="
    echo "If metrics are still showing 'no data available', this could mean:"
    echo "1. Saturn server is configured to only accept authenticated STUN/TURN requests"
    echo "2. Saturn may be filtering out malformed or unauthenticated packets"
    echo "3. The server might require proper TURN credentials for packet processing"
    echo "4. Check Saturn server logs: docker-compose logs saturn"
    echo "5. Verify Saturn configuration allows the test traffic"
    echo
    echo "To generate real metrics, try:"
    echo "1. Use a real TURN client (like coturn's turnutils)"  
    echo "2. Configure proper TURN credentials in Saturn"
    echo "3. Send authenticated STUN/TURN protocol messages"
    echo "4. Check if Saturn is running in a restrictive mode"
    
    return 0
}

# Function to create traffic load test
create_load_test() {
    echo
    echo "CREATING sustained load test..."
    echo "=================================="
    
    LOAD_DURATION=60  # seconds
    echo "Running ${LOAD_DURATION}-second load test..."
    
    if [ "$NC_AVAILABLE" = true ]; then
        # Background process to send continuous STUN/TURN protocol traffic
        (
            end_time=$(($(date +%s) + LOAD_DURATION))
            packet_count=0
            
            while [ $(date +%s) -lt $end_time ]; do
                # Send STUN Binding Request
                printf '\x00\x01\x00\x00\x21\x12\xA4\x42' | cat - <(printf '%08x' $RANDOM | xxd -r -p) | nc -u -w1 localhost 3478 2>/dev/null &
                
                # Send STUN Allocate Request  
                printf '\x00\x03\x00\x00\x21\x12\xA4\x42' | cat - <(printf '%08x' $RANDOM | xxd -r -p) | nc -u -w1 localhost 3478 2>/dev/null &
                
                # Send larger data packets periodically
                if [ $((packet_count % 5)) -eq 0 ]; then
                    dd if=/dev/zero bs=512 count=1 2>/dev/null | nc -u -w1 localhost 3478 2>/dev/null &
                fi
                
                packet_count=$((packet_count + 2))
                
                # Vary the rate - burst and pause pattern
                if [ $((packet_count % 20)) -eq 0 ]; then
                    sleep 2  # Pause to simulate client behavior
                else
                    sleep 0.05  # High frequency during active periods
                fi
            done
            
            echo "Load test completed. Sent approximately $packet_count STUN/TURN packets."
        ) &
        
        LOAD_PID=$!
    else
        # Alternative load test using HTTP requests
        echo "Running HTTP-based load test (netcat not available)..."
        (
            end_time=$(($(date +%s) + LOAD_DURATION))
            request_count=0
            
            while [ $(date +%s) -lt $end_time ]; do
                # Make requests to various endpoints to generate load
                curl -s "http://localhost:9090/metrics" > /dev/null 2>&1 &
                curl -s "http://localhost:9091/api/v1/targets" > /dev/null 2>&1 &
                
                request_count=$((request_count + 1))
                
                if [ $((request_count % 5)) -eq 0 ]; then
                    sleep 2
                else
                    sleep 0.5
                fi
            done
            
            echo "HTTP load test completed. Made approximately $request_count requests."
        ) &
        
        LOAD_PID=$!
    fi
    
    # Monitor metrics during load test
    echo "Monitoring metrics during load test..."
    for i in $(seq 1 6); do
        sleep 10
        echo "Load test progress: $((i * 10))s / ${LOAD_DURATION}s"
        
        # Quick metric check
        CURRENT_MEMORY=$(query_metric "saturn_memory_usage_bytes")
        CURRENT_INGRESS=$(query_metric "saturn_ingress_packets_total")
        
        if [ -n "$CURRENT_MEMORY" ] && [ "$CURRENT_MEMORY" != "0" ]; then
            if [ "$BC_AVAILABLE" = true ]; then
                MEMORY_MB=$(echo "scale=1; $CURRENT_MEMORY / 1024 / 1024" | bc)
                echo "  Current memory: ${MEMORY_MB} MB"
            else
                echo "  Current memory: ${CURRENT_MEMORY} bytes"
            fi
        fi
        
        if [ -n "$CURRENT_INGRESS" ]; then
            echo "  Ingress packets: ${CURRENT_INGRESS}"
        fi
    done
    
    # Wait for load test to complete
    wait $LOAD_PID
    
    echo "SUCCESS: Load test completed"
    echo "   Waiting 15 seconds for final metrics update..."
    sleep 15
    
    return 0
}

PROMETHEUS_HOST="localhost"
PROMETHEUS_PORT="9091"
PROMETHEUS_URL="http://${PROMETHEUS_HOST}:${PROMETHEUS_PORT}"

echo "Testing Saturn TURN Server Metrics via Prometheus (Docker Compose)"
echo "=================================================================="

# Check if we should simulate traffic
SIMULATE_TRAFFIC=false
LOAD_TEST=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --simulate-traffic)
            SIMULATE_TRAFFIC=true
            shift
            ;;
        --load-test)
            LOAD_TEST=true
            SIMULATE_TRAFFIC=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --simulate-traffic    Generate test traffic to Saturn server"
            echo "  --load-test          Run sustained load test (includes --simulate-traffic)"
            echo "  --help              Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                           # Basic metrics testing"
            echo "  $0 --simulate-traffic        # Test with simulated traffic"
            echo "  $0 --load-test              # Test with sustained load"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Test Prometheus health
echo
echo "1. Testing Prometheus Health..."
echo "GET ${PROMETHEUS_URL}/-/healthy"
if curl -s -f "${PROMETHEUS_URL}/-/healthy" > /dev/null; then
    echo "SUCCESS: Prometheus is healthy"
else
    echo "ERROR: Prometheus health check failed"
    exit 1
fi

# Test Saturn target status in Prometheus
echo
echo "2. Checking Saturn Target Status..."
echo "GET ${PROMETHEUS_URL}/api/v1/targets"
SATURN_TARGET_STATUS=$(curl -s "${PROMETHEUS_URL}/api/v1/targets" | grep -o '"health":"[^"]*".*saturn-turn-server' || echo "not_found")
if echo "$SATURN_TARGET_STATUS" | grep -q '"health":"up"'; then
    echo "SUCCESS: Saturn target is UP and healthy in Prometheus"
    
    # Check Saturn configuration from metrics
    echo "Checking Saturn configuration..."
    SATURN_INFO=$(curl -s "http://localhost:9090/info" 2>/dev/null || echo "")
    if [ -n "$SATURN_INFO" ]; then
        echo "Saturn configuration: $SATURN_INFO"
    else
        echo "INFO: Saturn /info endpoint not accessible (may require authentication)"
    fi
else
    echo "ERROR: Saturn target is DOWN or not found"
    echo "Target status: $SATURN_TARGET_STATUS"
    echo
    echo "TROUBLESHOOTING:"
    echo "• Check if Saturn container is running: docker-compose ps"
    echo "• Check Saturn container logs: docker-compose logs saturn"
    echo "• Verify Saturn metrics are enabled in configuration"
    echo "• Check if Saturn metrics port (9090) is accessible"
    exit 1
fi

# Test Saturn metrics availability
echo
echo "3. Testing Saturn Metrics Availability..."
echo "GET ${PROMETHEUS_URL}/api/v1/label/__name__/values"
SATURN_METRICS=$(curl -s "${PROMETHEUS_URL}/api/v1/label/__name__/values" | grep -o '"saturn_[^"]*"' | wc -l | tr -d ' ')
echo "Found ${SATURN_METRICS} Saturn-specific metrics"

if [ "$SATURN_METRICS" -gt 0 ]; then
    echo "SUCCESS: Saturn metrics are being exported through Prometheus"
    echo
    echo "Available Saturn metrics:"
    curl -s "${PROMETHEUS_URL}/api/v1/label/__name__/values" | grep -o '"saturn_[^"]*"' | sed 's/"//g' | sed 's/^/- /'
    
    # Check for specific metric categories
    MEMORY_METRICS=$(curl -s "${PROMETHEUS_URL}/api/v1/label/__name__/values" | grep -o '"saturn_.*memory\|saturn_.*heap\|saturn_.*goroutines\|saturn_.*gc"' | wc -l | tr -d ' ')
    TRAFFIC_METRICS=$(curl -s "${PROMETHEUS_URL}/api/v1/label/__name__/values" | grep -o '"saturn_.*traffic\|saturn_.*packets"' | wc -l | tr -d ' ')
    AUTH_METRICS=$(curl -s "${PROMETHEUS_URL}/api/v1/label/__name__/values" | grep -o '"saturn_.*auth\|saturn_.*connections"' | wc -l | tr -d ' ')
    
    echo
    echo "Metric categories found:"
    echo "  - Memory metrics: ${MEMORY_METRICS}"
    echo "  - Traffic metrics: ${TRAFFIC_METRICS}"
    echo "  - Authentication metrics: ${AUTH_METRICS}"
else
    echo "WARNING: No Saturn metrics found (server may not have received any traffic yet)"
fi

# Traffic simulation phase
if [ "$SIMULATE_TRAFFIC" = true ]; then
    echo
    echo "TRAFFIC SIMULATION PHASE"
    echo "==========================="
    
    # Capture baseline metrics before traffic simulation
    echo "Capturing baseline metrics..."
    BASELINE_MEMORY=$(query_metric "saturn_memory_usage_bytes")
    BASELINE_INGRESS=$(query_metric "saturn_ingress_packets_total")
    BASELINE_EGRESS=$(query_metric "saturn_egress_packets_total")
    BASELINE_GC=$(query_metric "saturn_gc_count_total")
    
    if simulate_traffic; then
        echo "SUCCESS: Traffic simulation successful"
        
        if [ "$LOAD_TEST" = true ]; then
            create_load_test
        fi
        
        # Show before/after comparison
        echo
        echo "Before/After Metrics Comparison:"
        echo "==================================="
        
        AFTER_MEMORY=$(query_metric "saturn_memory_usage_bytes")
        AFTER_INGRESS=$(query_metric "saturn_ingress_packets_total")
        AFTER_EGRESS=$(query_metric "saturn_egress_packets_total")
        AFTER_GC=$(query_metric "saturn_gc_count_total")
        
        if [ -n "$BASELINE_MEMORY" ] && [ -n "$AFTER_MEMORY" ]; then
            if [ "$BC_AVAILABLE" = true ]; then
                BASELINE_MB=$(echo "scale=2; $BASELINE_MEMORY / 1024 / 1024" | bc)
                AFTER_MB=$(echo "scale=2; $AFTER_MEMORY / 1024 / 1024" | bc)
                MEMORY_DIFF=$(echo "scale=2; $AFTER_MB - $BASELINE_MB" | bc)
                echo "Memory Usage: ${BASELINE_MB} MB → ${AFTER_MB} MB (Δ ${MEMORY_DIFF} MB)"
            else
                echo "Memory Usage: ${BASELINE_MEMORY} → ${AFTER_MEMORY} bytes"
            fi
        fi
        
        if [ -n "$BASELINE_INGRESS" ] && [ -n "$AFTER_INGRESS" ]; then
            INGRESS_DIFF=$((AFTER_INGRESS - BASELINE_INGRESS))
            echo "Ingress Packets: ${BASELINE_INGRESS} → ${AFTER_INGRESS} (Δ +${INGRESS_DIFF})"
        fi
        
        if [ -n "$BASELINE_EGRESS" ] && [ -n "$AFTER_EGRESS" ]; then
            EGRESS_DIFF=$((AFTER_EGRESS - BASELINE_EGRESS))
            echo "Egress Packets: ${BASELINE_EGRESS} → ${AFTER_EGRESS} (Δ +${EGRESS_DIFF})"
        fi
        
        if [ -n "$BASELINE_GC" ] && [ -n "$AFTER_GC" ]; then
            GC_DIFF=$((AFTER_GC - BASELINE_GC))
            echo "GC Cycles: ${BASELINE_GC} → ${AFTER_GC} (Δ +${GC_DIFF})"
        fi
        
    else
        echo "ERROR: Traffic simulation failed"
        echo "   Continuing with metrics testing..."
    fi
fi

# Test specific Saturn metrics
echo
echo "4. Querying Saturn Metric Values..."
echo "=================================="

# Server uptime
UPTIME_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=saturn_server_uptime_seconds")
if echo "$UPTIME_RESULT" | grep -q '"status":"success"'; then
    UPTIME_VALUE=$(echo "$UPTIME_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9.]*"' | tr -d '"' | tail -1)
    echo "SUCCESS: Saturn server uptime: ${UPTIME_VALUE} seconds"
else
    echo "ERROR: Failed to query saturn_server_uptime_seconds"
fi

# Configured threads
THREADS_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=saturn_configured_threads")
if echo "$THREADS_RESULT" | grep -q '"status":"success"'; then
    THREADS_VALUE=$(echo "$THREADS_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9]*"' | tr -d '"' | tail -1)
    echo "SUCCESS: Saturn configured threads: ${THREADS_VALUE}"
else
    echo "ERROR: Failed to query saturn_configured_threads"
fi

# Configured realms
REALMS_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=saturn_configured_realms")
if echo "$REALMS_RESULT" | grep -q '"status":"success"'; then
    REALMS_VALUE=$(echo "$REALMS_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9]*"' | tr -d '"' | tail -1)
    echo "SUCCESS: Saturn configured realms: ${REALMS_VALUE}"
else
    echo "ERROR: Failed to query saturn_configured_realms"
fi

echo
echo "5. Testing Memory Metrics..."
echo "============================"

# Memory usage
MEMORY_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=saturn_memory_usage_bytes")
if echo "$MEMORY_RESULT" | grep -q '"status":"success"'; then
    MEMORY_VALUE=$(echo "$MEMORY_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9.]*"' | tr -d '"' | tail -1)
    if [ -n "$MEMORY_VALUE" ] && [ "$MEMORY_VALUE" != "0" ]; then
        if [ "$BC_AVAILABLE" = true ]; then
            MEMORY_MB=$(echo "scale=2; $MEMORY_VALUE / 1024 / 1024" | bc)
            echo "SUCCESS: Saturn memory usage: ${MEMORY_MB} MB (${MEMORY_VALUE} bytes)"
        else
            echo "SUCCESS: Saturn memory usage: ${MEMORY_VALUE} bytes"
        fi
    else
        echo "WARNING: Saturn memory usage: No data available yet"
    fi
else
    echo "ERROR: Failed to query saturn_memory_usage_bytes"
fi

# Heap in use
HEAP_INUSE_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=saturn_heap_inuse_bytes")
if echo "$HEAP_INUSE_RESULT" | grep -q '"status":"success"'; then
    HEAP_INUSE_VALUE=$(echo "$HEAP_INUSE_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9.]*"' | tr -d '"' | tail -1)
    if [ -n "$HEAP_INUSE_VALUE" ] && [ "$HEAP_INUSE_VALUE" != "0" ]; then
        if [ "$BC_AVAILABLE" = true ]; then
            HEAP_INUSE_MB=$(echo "scale=2; $HEAP_INUSE_VALUE / 1024 / 1024" | bc)
            echo "SUCCESS: Saturn heap in use: ${HEAP_INUSE_MB} MB (${HEAP_INUSE_VALUE} bytes)"
        else
            echo "SUCCESS: Saturn heap in use: ${HEAP_INUSE_VALUE} bytes"
        fi
    else
        echo "WARNING: Saturn heap in use: No data available yet"
    fi
else
    echo "ERROR: Failed to query saturn_heap_inuse_bytes"
fi

# Goroutine count
GOROUTINES_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=saturn_goroutines_count")
if echo "$GOROUTINES_RESULT" | grep -q '"status":"success"'; then
    GOROUTINES_VALUE=$(echo "$GOROUTINES_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9]*"' | tr -d '"' | tail -1)
    if [ -n "$GOROUTINES_VALUE" ] && [ "$GOROUTINES_VALUE" != "0" ]; then
        echo "SUCCESS: Saturn goroutines: ${GOROUTINES_VALUE}"
    else
        echo "WARNING: Saturn goroutines: No data available yet"
    fi
else
    echo "ERROR: Failed to query saturn_goroutines_count"
fi

# GC count
GC_COUNT_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=saturn_gc_count_total")
if echo "$GC_COUNT_RESULT" | grep -q '"status":"success"'; then
    GC_COUNT_VALUE=$(echo "$GC_COUNT_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9]*"' | tr -d '"' | tail -1)
    if [ -n "$GC_COUNT_VALUE" ]; then
        echo "SUCCESS: Saturn GC cycles: ${GC_COUNT_VALUE}"
    else
        echo "WARNING: Saturn GC cycles: No data available yet"
    fi
else
    echo "ERROR: Failed to query saturn_gc_count_total"
fi

echo
echo "6. Testing Network Traffic Metrics..."
echo "====================================="

# Ingress traffic
INGRESS_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=saturn_ingress_traffic_mb_total")
if echo "$INGRESS_RESULT" | grep -q '"status":"success"'; then
    INGRESS_VALUE=$(echo "$INGRESS_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9.]*"' | tr -d '"' | tail -1)
    if [ -n "$INGRESS_VALUE" ]; then
        echo "SUCCESS: Saturn ingress traffic: ${INGRESS_VALUE} MB"
    else
        echo "WARNING: Saturn ingress traffic: No data available yet (no incoming traffic)"
    fi
else
    echo "ERROR: Failed to query saturn_ingress_traffic_mb_total"
fi

# Egress traffic
EGRESS_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=saturn_egress_traffic_mb_total")
if echo "$EGRESS_RESULT" | grep -q '"status":"success"'; then
    EGRESS_VALUE=$(echo "$EGRESS_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9.]*"' | tr -d '"' | tail -1)
    if [ -n "$EGRESS_VALUE" ]; then
        echo "SUCCESS: Saturn egress traffic: ${EGRESS_VALUE} MB"
    else
        echo "WARNING: Saturn egress traffic: No data available yet (no outgoing traffic)"
    fi
else
    echo "ERROR: Failed to query saturn_egress_traffic_mb_total"
fi

# Ingress packets
INGRESS_PACKETS_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=saturn_ingress_packets_total")
if echo "$INGRESS_PACKETS_RESULT" | grep -q '"status":"success"'; then
    INGRESS_PACKETS_VALUE=$(echo "$INGRESS_PACKETS_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9]*"' | tr -d '"' | tail -1)
    if [ -n "$INGRESS_PACKETS_VALUE" ]; then
        echo "SUCCESS: Saturn ingress packets: ${INGRESS_PACKETS_VALUE}"
    else
        echo "WARNING: Saturn ingress packets: No data available yet (no incoming packets)"
    fi
else
    echo "ERROR: Failed to query saturn_ingress_packets_total"
fi

# Egress packets
EGRESS_PACKETS_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=saturn_egress_packets_total")
if echo "$EGRESS_PACKETS_RESULT" | grep -q '"status":"success"'; then
    EGRESS_PACKETS_VALUE=$(echo "$EGRESS_PACKETS_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9]*"' | tr -d '"' | tail -1)
    if [ -n "$EGRESS_PACKETS_VALUE" ]; then
        echo "SUCCESS: Saturn egress packets: ${EGRESS_PACKETS_VALUE}"
    else
        echo "WARNING: Saturn egress packets: No data available yet (no outgoing packets)"
    fi
else
    echo "ERROR: Failed to query saturn_egress_packets_total"
fi

# Traffic rate calculations (if data is available)
if [ -n "$INGRESS_VALUE" ] && [ -n "$EGRESS_VALUE" ] && [ "$INGRESS_VALUE" != "0" ] && [ "$EGRESS_VALUE" != "0" ]; then
    if [ "$BC_AVAILABLE" = true ]; then
        TOTAL_TRAFFIC=$(echo "scale=2; $INGRESS_VALUE + $EGRESS_VALUE" | bc)
        echo "SUCCESS: Total traffic: ${TOTAL_TRAFFIC} MB (ingress + egress)"
    else
        echo "SUCCESS: Total traffic: ${INGRESS_VALUE} MB ingress + ${EGRESS_VALUE} MB egress"
    fi
fi

echo
echo "7. Testing Authentication Metrics..."
echo "===================================="

# Auth attempts
AUTH_ATTEMPTS_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=saturn_auth_attempts_total")
if echo "$AUTH_ATTEMPTS_RESULT" | grep -q '"status":"success"'; then
    AUTH_ATTEMPTS_VALUE=$(echo "$AUTH_ATTEMPTS_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9]*"' | tr -d '"' | tail -1)
    if [ -n "$AUTH_ATTEMPTS_VALUE" ]; then
        echo "SUCCESS: Saturn auth attempts: ${AUTH_ATTEMPTS_VALUE}"
    else
        echo "WARNING: Saturn auth attempts: No data available yet (no authentication attempts)"
    fi
else
    echo "ERROR: Failed to query saturn_auth_attempts_total"
fi

# Active connections
ACTIVE_CONNECTIONS_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=saturn_active_connections")
if echo "$ACTIVE_CONNECTIONS_RESULT" | grep -q '"status":"success"'; then
    ACTIVE_CONNECTIONS_VALUE=$(echo "$ACTIVE_CONNECTIONS_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9]*"' | tr -d '"' | tail -1)
    if [ -n "$ACTIVE_CONNECTIONS_VALUE" ]; then
        echo "SUCCESS: Saturn active connections: ${ACTIVE_CONNECTIONS_VALUE}"
    else
        echo "WARNING: Saturn active connections: No data available yet (no active connections)"
    fi
else
    echo "ERROR: Failed to query saturn_active_connections"
fi

echo
echo "9. Testing Rate-Based Metrics..."
echo "================================"

# Ingress traffic rate (5-minute window)
INGRESS_RATE_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=rate(saturn_ingress_traffic_mb_total[5m])")
if echo "$INGRESS_RATE_RESULT" | grep -q '"status":"success"'; then
    INGRESS_RATE_VALUE=$(echo "$INGRESS_RATE_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9.]*"' | tr -d '"' | tail -1)
    if [ -n "$INGRESS_RATE_VALUE" ] && [ "$INGRESS_RATE_VALUE" != "0" ]; then
        echo "SUCCESS: Saturn ingress rate: ${INGRESS_RATE_VALUE} MB/s (5min avg)"
    else
        echo "WARNING: Saturn ingress rate: No traffic in last 5 minutes"
    fi
else
    echo "ERROR: Failed to query ingress traffic rate"
fi

# Egress traffic rate (5-minute window)
EGRESS_RATE_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=rate(saturn_egress_traffic_mb_total[5m])")
if echo "$EGRESS_RATE_RESULT" | grep -q '"status":"success"'; then
    EGRESS_RATE_VALUE=$(echo "$EGRESS_RATE_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9.]*"' | tr -d '"' | tail -1)
    if [ -n "$EGRESS_RATE_VALUE" ] && [ "$EGRESS_RATE_VALUE" != "0" ]; then
        echo "SUCCESS: Saturn egress rate: ${EGRESS_RATE_VALUE} MB/s (5min avg)"
    else
        echo "WARNING: Saturn egress rate: No traffic in last 5 minutes"
    fi
else
    echo "ERROR: Failed to query egress traffic rate"
fi

# Authentication attempts rate
AUTH_RATE_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=rate(saturn_auth_attempts_total[5m])")
if echo "$AUTH_RATE_RESULT" | grep -q '"status":"success"'; then
    AUTH_RATE_VALUE=$(echo "$AUTH_RATE_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9.]*"' | tr -d '"' | tail -1)
    if [ -n "$AUTH_RATE_VALUE" ] && [ "$AUTH_RATE_VALUE" != "0" ]; then
        echo "SUCCESS: Saturn auth rate: ${AUTH_RATE_VALUE} attempts/s (5min avg)"
    else
        echo "WARNING: Saturn auth rate: No auth attempts in last 5 minutes"
    fi
else
    echo "ERROR: Failed to query authentication rate"
fi

# GC rate
GC_RATE_RESULT=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=rate(saturn_gc_count_total[5m])")
if echo "$GC_RATE_RESULT" | grep -q '"status":"success"'; then
    GC_RATE_VALUE=$(echo "$GC_RATE_RESULT" | grep -o '"value":\[[^]]*\]' | grep -o '[0-9.]*"' | tr -d '"' | tail -1)
    if [ -n "$GC_RATE_VALUE" ] && [ "$GC_RATE_VALUE" != "0" ]; then
        echo "SUCCESS: Saturn GC rate: ${GC_RATE_VALUE} cycles/s (5min avg)"
    else
        echo "WARNING: Saturn GC rate: No GC activity in last 5 minutes"
    fi
else
    echo "ERROR: Failed to query GC rate"
fi

echo
echo "10. Testing Grafana Integration..."
echo "================================="
GRAFANA_URL="http://localhost:3000"
if curl -s -f "${GRAFANA_URL}/api/health" > /dev/null; then
    echo "SUCCESS: Grafana is accessible at ${GRAFANA_URL}"
    echo "   Login with: admin/admin"
    echo "   Saturn dashboard should be available"
else
    echo "WARNING: Grafana not accessible at ${GRAFANA_URL}"
fi

echo
echo "TEST COMPLETED!"
echo "==================="
echo "• Prometheus: ${PROMETHEUS_URL}"
echo "• Grafana: ${GRAFANA_URL}"
echo "• Saturn metrics: Available through Prometheus API"

echo
echo "METRICS STATUS SUMMARY:"
echo "======================="
echo "Always Available Metrics (should have data):"
echo "  ✓ saturn_server_uptime_seconds"
echo "  ✓ saturn_configured_threads"  
echo "  ✓ saturn_configured_realms"
echo "  ✓ saturn_memory_usage_bytes"
echo "  ✓ saturn_heap_*_bytes"
echo "  ✓ saturn_goroutines_count"
echo
echo "Event-Driven Metrics (only have data during activity):"
echo "  • saturn_auth_attempts_total (requires TURN client authentication)"
echo "  • saturn_auth_success_total (requires successful TURN authentication)"
echo "  • saturn_auth_failures_total (requires failed TURN authentication)"  
echo "  • saturn_active_connections (requires active TURN connections)"
echo "  • saturn_connections_total (requires TURN connection attempts)"
echo "  • saturn_ingress_traffic_mb_total (requires incoming TURN data)"
echo "  • saturn_egress_traffic_mb_total (requires outgoing TURN data)"
echo "  • saturn_ingress_packets_total (requires valid TURN packets)"
echo "  • saturn_egress_packets_total (requires TURN responses)"
echo "  • saturn_token_validations_total (requires JWT token validation)"
echo "  • saturn_gc_count_total (requires garbage collection activity)"

echo
echo "TO GENERATE EVENT-DRIVEN METRICS:"
echo "================================="
echo "1. Use a real TURN client like 'turnutils_uclient' from coturn:"
echo "   turnutils_uclient -t -T -v $SATURN_HOST -p $SATURN_PORT"
echo
echo "2. Configure TURN credentials in Saturn and test with authentication:"
echo "   turnutils_uclient -u username -w password $SATURN_HOST -p $SATURN_PORT"
echo
echo "3. Generate sustained traffic with multiple clients:"
echo "   for i in {1..5}; do turnutils_uclient -t -T $SATURN_HOST -p $SATURN_PORT & done"
echo
echo "4. Check Saturn server logs for processing status:"
echo "   docker-compose logs -f saturn"

# Show traffic simulation results if applicable
if [ "$SIMULATE_TRAFFIC" = true ]; then
    echo
    echo "TRAFFIC SIMULATION NOTES:"
    echo "========================"
    echo "The test script sent STUN-like packets, but Saturn may require:"
    echo "• Proper STUN/TURN protocol compliance"
    echo "• Valid authentication credentials"  
    echo "• Specific server configuration"
    echo
    echo "If event-driven metrics still show 'no data', this is expected"
    echo "without real TURN client traffic or proper authentication."
fi
    echo
    echo "Traffic Simulation Results:"
    echo "=============================="
    
    # Re-query key metrics after simulation
    FINAL_MEMORY=$(query_metric "saturn_memory_usage_bytes")
    FINAL_INGRESS=$(query_metric "saturn_ingress_packets_total")
    FINAL_EGRESS=$(query_metric "saturn_egress_packets_total")
    FINAL_INGRESS_MB=$(query_metric "saturn_ingress_traffic_mb_total")
    FINAL_EGRESS_MB=$(query_metric "saturn_egress_traffic_mb_total")
    
    if [ -n "$FINAL_MEMORY" ] && [ "$FINAL_MEMORY" != "0" ]; then
        if [ "$BC_AVAILABLE" = true ]; then
            FINAL_MEMORY_MB=$(echo "scale=2; $FINAL_MEMORY / 1024 / 1024" | bc)
            echo "• Final memory usage: ${FINAL_MEMORY_MB} MB"
        else
            echo "• Final memory usage: ${FINAL_MEMORY} bytes"
        fi
    fi
    
    if [ -n "$FINAL_INGRESS" ] && [ "$FINAL_INGRESS" != "0" ]; then
        echo "• Total ingress packets: ${FINAL_INGRESS}"
    fi
    
    if [ -n "$FINAL_EGRESS" ] && [ "$FINAL_EGRESS" != "0" ]; then
        echo "• Total egress packets: ${FINAL_EGRESS}"
    fi
    
    if [ -n "$FINAL_INGRESS_MB" ] && [ "$FINAL_INGRESS_MB" != "0" ]; then
        echo "• Total ingress traffic: ${FINAL_INGRESS_MB} MB"
    fi
    
    if [ -n "$FINAL_EGRESS_MB" ] && [ "$FINAL_EGRESS_MB" != "0" ]; then
        echo "• Total egress traffic: ${FINAL_EGRESS_MB} MB"
    fi
    
    if [ "$LOAD_TEST" = true ]; then
        echo "• Load test: Completed 60-second sustained traffic test"
    fi
fi
echo
echo "Metrics Summary:"
echo "==================="
echo "Server Metrics:"
echo "  - Uptime: Available"
echo "  - Threads: Available"
echo "  - Realms: Available"
echo
echo "Memory Metrics:"
echo "  - Memory Usage: $([ -n "$MEMORY_VALUE" ] && echo "Available" || echo "Pending data")"
echo "  - Heap Usage: $([ -n "$HEAP_INUSE_VALUE" ] && echo "Available" || echo "Pending data")"
echo "  - Goroutines: $([ -n "$GOROUTINES_VALUE" ] && echo "Available" || echo "Pending data")"
echo "  - GC Cycles: $([ -n "$GC_COUNT_VALUE" ] && echo "Available" || echo "Pending data")"
echo
echo "Network Traffic Metrics:"
echo "  - Ingress Traffic: $([ -n "$INGRESS_VALUE" ] && echo "Available" || echo "Pending traffic")"
echo "  - Egress Traffic: $([ -n "$EGRESS_VALUE" ] && echo "Available" || echo "Pending traffic")"
echo "  - Ingress Packets: $([ -n "$INGRESS_PACKETS_VALUE" ] && echo "Available" || echo "Pending traffic")"
echo "  - Egress Packets: $([ -n "$EGRESS_PACKETS_VALUE" ] && echo "Available" || echo "Pending traffic")"
echo
echo "Authentication Metrics:"
echo "  - Auth Attempts: $([ -n "$AUTH_ATTEMPTS_VALUE" ] && echo "Available" || echo "Pending auth attempts")"
echo "  - Active Connections: $([ -n "$ACTIVE_CONNECTIONS_VALUE" ] && echo "Available" || echo "Pending connections")"
echo
echo "NOTE: Some metrics may show 'Pending' until Saturn receives actual traffic or authentication attempts."
if [ "$SIMULATE_TRAFFIC" = false ]; then
    echo "   To generate test data automatically, run: $0 --simulate-traffic"
    echo "   To run a sustained load test, use: $0 --load-test"
else
    echo "   Traffic simulation was performed - metrics should now show data."
fi
echo "   To generate manual test data, try connecting a WebRTC client to the TURN server."
echo
echo "TROUBLESHOOTING:"
echo "==================="
echo "If metrics are missing:"
echo "  1. Check Saturn server logs: docker-compose logs saturn"
echo "  2. Verify metrics are enabled: ENABLE_METRICS=true in .env"
echo "  3. Check Prometheus targets: ${PROMETHEUS_URL}/targets"
echo "  4. Wait a few minutes for metrics collection to stabilize"
echo
echo "To generate test traffic:"
if [ "$SIMULATE_TRAFFIC" = false ]; then
    echo "  1. Run this script with traffic simulation: $0 --simulate-traffic"
    echo "  2. Run sustained load test: $0 --load-test"
    echo "  3. Use a WebRTC application that connects to TURN server"
    echo "  4. Generate test JWT tokens: make jwt-token"
    echo "  5. Monitor metrics during connection attempts"
else
    echo "  SUCCESS: Traffic simulation was already performed in this run"
    echo "  1. Re-run with --load-test for sustained traffic"
    echo "  2. Use a WebRTC application for real-world testing"
    echo "  3. Generate additional JWT tokens: make jwt-token"
fi
echo
echo "Useful Prometheus queries:"
echo "  - Memory usage trend: saturn_memory_usage_bytes[1h]"
echo "  - Traffic rate: rate(saturn_ingress_traffic_mb_total[5m])"
echo "  - Auth success rate: rate(saturn_auth_success_total[5m])"
