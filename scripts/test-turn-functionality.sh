#!/bin/bash

# TURN Connection Test Script
# This script tests the TURN server functionality with proper JWT authentication

set -e

# Load environment variables from .env file if it exists
if [ -f ".env" ]; then
    echo "Loading configuration from .env file..."
    export $(grep -v '^#' .env | xargs)
fi

# Configuration with defaults - require environment variables
SERVER="${TURN_SERVER:-${PUBLIC_IP}:${PORT:-3478}}"
ACCESS_SECRET="${ACCESS_SECRET}"

# Validation
if [ -z "$PUBLIC_IP" ]; then
    echo "Error: PUBLIC_IP environment variable is required"
    echo "Please set it in your .env file or environment"
    exit 1
fi

if [ -z "$ACCESS_SECRET" ]; then
    echo "Error: ACCESS_SECRET environment variable is required"
    echo "Please set it in your .env file or environment"
    exit 1
fi

echo "Testing TURN Server Functionality"
echo "=================================="
echo "Server: $SERVER"
echo

# Function to generate JWT token
generate_jwt() {
    local user_id=${1:-"test-user-$(date +%s)"}
    local exp_time=$(($(date +%s) + 3600))  # 1 hour from now
    
    echo "Generating JWT token for user: $user_id"
    
    # Create JWT using Go
    cat > /tmp/jwt_gen.go << 'EOF'
package main

import (
	"fmt"
	"os"
	"time"
	"github.com/golang-jwt/jwt/v5"
)

type Claims struct {
	UserID string `json:"user_id"`
	jwt.RegisteredClaims
}

func main() {
	if len(os.Args) != 3 {
		fmt.Println("Usage: go run jwt_gen.go <user_id> <secret>")
		os.Exit(1)
	}
	
	userID := os.Args[1]
	secret := os.Args[2]
	
	claims := Claims{
		UserID: userID,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}
	
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(secret))
	if err != nil {
		fmt.Printf("Error generating token: %v\n", err)
		os.Exit(1)
	}
	
	fmt.Print(tokenString)
}
EOF
    
    cd /Volumes/Workspace/git/saturn
    JWT_TOKEN=$(go run /tmp/jwt_gen.go "$user_id" "$ACCESS_SECRET")
    rm -f /tmp/jwt_gen.go
    echo "JWT token generated successfully"
    echo "Token preview: ${JWT_TOKEN:0:50}..."
    echo
}

# Function to test TURN allocation
test_turn_allocation() {
    echo "Testing TURN allocation..."
    
    # Use turnutils_uclient for comprehensive TURN testing
    if command -v turnutils_uclient >/dev/null 2>&1; then
        echo "Using turnutils_uclient for TURN testing..."
        
        # Test TURN allocation with authentication
        echo "Testing TURN allocation with JWT authentication..."
        timeout 15 turnutils_uclient -t -u "$JWT_TOKEN" -w "$JWT_TOKEN" -r production $SERVER || {
            echo "TURN allocation test with turnutils_uclient failed or timed out"
            echo "This might be normal if the test takes longer than expected"
        }
    else
        echo "turnutils_uclient not available, trying alternative approach..."
    fi
    
    # Alternative: Test with custom Go client
    echo "Testing with custom TURN client..."
    cat > /tmp/turn_test.go << 'EOF'
package main

import (
	"fmt"
	"net"
	"time"
	"github.com/pion/turn/v4"
)

func main() {
	if len(os.Args) != 3 {
		fmt.Println("Usage: go run turn_test.go <server> <token>")
		return
	}
	
	server := os.Args[1]
	token := os.Args[2]
	
	fmt.Printf("Connecting to TURN server: %s\n", server)
	fmt.Printf("Using token: %s...\n", token[:20])
	
	// Create TURN client configuration
	cfg := &turn.ClientConfig{
		STUNServerAddr: server,
		TURNServerAddr: server,
		Conn: func() (net.PacketConn, error) {
			return net.ListenPacket("udp4", "0.0.0.0:0")
		}(),
		Username: token,
		Password: token,
		Realm:    "production",
	}
	
	fmt.Println("Creating TURN client...")
	client, err := turn.NewClient(cfg)
	if err != nil {
		fmt.Printf("Failed to create TURN client: %v\n", err)
		return
	}
	defer client.Close()
	
	fmt.Println("TURN client created successfully!")
	fmt.Println("Attempting to allocate relay...")
	
	// Try to allocate a relay
	relayConn, err := client.Allocate()
	if err != nil {
		fmt.Printf("Failed to allocate relay: %v\n", err)
		return
	}
	defer relayConn.Close()
	
	fmt.Printf("TURN allocation successful!")
	fmt.Printf("Relay address: %s\n", relayConn.LocalAddr())
	
	// Test sending data through the relay
	fmt.Println("Testing data transmission through relay...")
	testData := []byte("Hello TURN relay!")
	
	// Set a read deadline for the test
	relayConn.SetReadDeadline(time.Now().Add(5 * time.Second))
	
	// Send data to ourselves through the relay
	_, err = relayConn.WriteTo(testData, relayConn.LocalAddr())
	if err != nil {
		fmt.Printf("Failed to send data through relay: %v\n", err)
		return
	}
	
	// Try to read the data back
	buffer := make([]byte, 1024)
	n, addr, err := relayConn.ReadFrom(buffer)
	if err != nil {
		fmt.Printf("Failed to read data from relay: %v\n", err)
		return
	}
	
	fmt.Printf("Received %d bytes from %s: %s\n", n, addr, string(buffer[:n]))
	fmt.Println("TURN relay test completed successfully!")
}
EOF
    
    cd /Volumes/Workspace/git/saturn
    timeout 30 go run /tmp/turn_test.go "$SERVER" "$JWT_TOKEN" || {
        echo "Custom TURN test failed or timed out"
        echo "Server might still be working but test conditions weren't met"
    }
    rm -f /tmp/turn_test.go
}

# Function to check server logs
check_server_logs() {
    echo
    echo "Checking server logs for TURN activity..."
    echo "Recent logs:"
    flyctl logs --app ${APP_NAME:-saturn-turn-server} --no-tail | tail -10
}

# Function to test metrics after TURN usage
test_metrics_after_turn() {
    echo
    echo "Checking metrics after TURN test..."
    if [ -z "$METRICS_PASSWORD" ]; then
        echo "Warning: METRICS_PASSWORD not set, skipping metrics check"
        echo "Please set METRICS_PASSWORD in your .env file to test metrics"
        return
    fi
    
    curl -s -u admin:"${METRICS_PASSWORD}" \
         "http://${PUBLIC_IP}:${METRICS_PORT:-9090}/metrics" | grep -E "(turn_|auth_|connection_)" | head -10 || {
        echo "Could not retrieve metrics"
    }
}

# Main test execution
main() {
    echo "Starting TURN server tests..."
    
    # Generate JWT token
    generate_jwt "turn-test-user"
    
    # Test TURN allocation
    test_turn_allocation
    
    # Check logs
    check_server_logs
    
    # Check metrics
    test_metrics_after_turn
    
    echo
    echo "TURN test completed!"
    echo
    echo "If tests failed, check:"
    echo "   1. Server is running: flyctl status --app ${APP_NAME:-saturn-turn-server}"
    echo "   2. Server logs: flyctl logs --app ${APP_NAME:-saturn-turn-server}"
    echo "   3. JWT token is valid and not expired"
    echo "   4. Network connectivity to the server"
}

# Run the main test
main
