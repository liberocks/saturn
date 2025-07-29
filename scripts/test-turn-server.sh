#!/usr/bin/env bash

# Test script for Saturn TURN server on Fly.io
# Tests both STUN and TURN functionality

set -e

# Load environment variables from .env file if it exists
if [ -f ".env" ]; then
    echo "Loading configuration from .env file..."
    export $(grep -v '^#' .env | xargs)
fi

# Configuration with defaults - require environment variables
TURN_SERVER="${TURN_SERVER:-${PUBLIC_IP}:${PORT:-3478}}"
APP_NAME="${APP_NAME:-saturn-turn-server}"
REALM="${REALM:-production}"

# Validation
if [ -z "$PUBLIC_IP" ]; then
    echo "Error: PUBLIC_IP environment variable is required"
    echo "Please set it in your .env file or environment"
    exit 1
fi

echo "Testing Saturn TURN Server on Fly.io"
echo "====================================="
echo "Server: $TURN_SERVER"
echo ""

# Function to test STUN functionality
test_stun() {
    echo "Testing STUN functionality..."
    
    if command -v stun >/dev/null 2>&1; then
        echo "Using stun command to test..."
        timeout 10s stun $TURN_SERVER || echo "STUN test failed or timed out"
    elif command -v turnutils_stunclient >/dev/null 2>&1; then
        echo "Using turnutils_stunclient to test..."
        timeout 10s turnutils_stunclient -v $TURN_SERVER || echo "STUN test failed or timed out"
    else
        echo "No STUN testing tools found. Install coturn-utils or libnice-tools"
        echo "   macOS: brew install coturn"
        echo "   Ubuntu: sudo apt-get install coturn-utils"
    fi
    echo ""
}



# Function to check server logs
check_server_logs() {
    echo "Checking server logs for errors..."
    
    if command -v flyctl >/dev/null 2>&1; then
        echo "Recent logs from Fly.io:"
        echo "------------------------"
        flyctl logs --app $APP_NAME --no-tail | tail -20
    else
        echo "flyctl not found. Install flyctl to check server logs"
        echo "   curl -L https://fly.io/install.sh | sh"
    fi
    echo ""
}

# Function to check metrics endpoint
test_metrics() {
    echo "Testing metrics endpoint..."
    
    # Use environment variables with fallbacks
    METRICS_HOST="${METRICS_HOST:-${APP_NAME}.fly.dev}"
    METRICS_PORT="${METRICS_PORT:-9090}"
    METRICS_URL="https://${METRICS_HOST}:${METRICS_PORT}/metrics"
    
    echo "Checking: $METRICS_URL"
    
    # Try to access metrics with authentication if credentials are available
    if [ -n "$METRICS_USERNAME" ] && [ -n "$METRICS_PASSWORD" ]; then
        echo "Using basic authentication..."
        if curl -f -s --connect-timeout 10 --max-time 30 -u "$METRICS_USERNAME:$METRICS_PASSWORD" "$METRICS_URL" >/dev/null 2>&1; then
            echo "Metrics endpoint is accessible with authentication"
        else
            echo "Metrics endpoint test failed with authentication"
        fi
    else
        # Try to access metrics (this might fail due to auth, but we can still test connectivity)
        if curl -f -s --connect-timeout 10 --max-time 30 "$METRICS_URL" >/dev/null 2>&1; then
            echo "Metrics endpoint is accessible"
        else
            echo "Metrics endpoint test failed (might be due to authentication)"
            echo "   Try: curl -u admin:YOUR_PASSWORD $METRICS_URL"
        fi
    fi
    echo ""
}

# Function to generate a test JWT token
generate_test_token() {
    echo "Generating test JWT token..."
    
    if [ -f "scripts/jwt-gen/main.go" ]; then
        echo "Building JWT generator..."
        cd scripts/jwt-gen
        go build -o jwt-gen main.go
        
        echo "Generating token for test user..."
        if [ -n "$ACCESS_SECRET" ]; then
            export REALM="${REALM}"
            export ACCESS_SECRET="${ACCESS_SECRET}"
            ./jwt-gen -user-id=test-user -email=test@example.com
        else
            echo "ACCESS_SECRET environment variable not set"
            echo "   Set it in .env file or environment"
            echo "   For Fly.io: flyctl secrets list --app $APP_NAME"
        fi
        cd ../..
    else
        echo "JWT generator not found at scripts/jwt-gen/main.go"
    fi
    echo ""
}

# Function to test TURN allocation
test_turn_allocation() {
    echo "Testing TURN allocation..."
    
    if command -v turnutils_uclient >/dev/null 2>&1; then
        if [ -n "$JWT_TOKEN" ]; then
            echo "Testing TURN allocation with JWT token..."
            timeout 15s turnutils_uclient -v -t -u "$JWT_TOKEN" $TURN_SERVER || echo "TURN allocation test failed or timed out"
        else
            echo "No JWT token available for TURN testing"
            echo "   Set ACCESS_SECRET and run this script again"
        fi
    else
        echo "turnutils_uclient not found. Install coturn-utils for TURN testing"
        echo "   macOS: brew install coturn"
        echo "   Ubuntu: sudo apt-get install coturn-utils"
    fi
    echo ""
}

# Main test execution
main() {
    echo "Starting tests..."
    echo ""
    
    test_stun
    test_metrics
    check_server_logs
    generate_test_token
    test_turn_allocation
    
    echo "Test completed!"
    echo ""
    echo "Troubleshooting tips:"
    echo "   1. Check Fly.io app status: flyctl status --app $APP_NAME"
    echo "   2. Monitor logs: flyctl logs --app $APP_NAME"
    echo "   3. Check IP allocation: flyctl ips list --app $APP_NAME"
    echo "   4. Test from different locations to rule out firewall issues"
    echo "   5. Verify PUBLIC_IP secret: flyctl secrets list --app $APP_NAME"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo ""
        echo "Environment variables:"
        echo "  ACCESS_SECRET  TURN server access secret for JWT generation"
        echo "  JWT_TOKEN      Pre-generated JWT token for TURN testing"
        exit 0
        ;;
    *)
        main
        ;;
esac
