package main

import (
	"fmt"
	"net"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/pion/turn/v4"
)

type TokenPayload struct {
	UserID     string   `json:"user_id"`
	Email      string   `json:"email"`
	Username   string   `json:"username"`
	IsVerified string   `json:"is_verified"`
	Roles      []string `json:"roles"`
	Type       string   `json:"type"`
	Realm      string   `json:"realm"`
	jwt.RegisteredClaims
}

func generateJWTToken(secret, userID, realm string) (string, error) {
	// Create claims with all required fields for TURN server validation
	claims := TokenPayload{
		UserID:     userID,
		Email:      userID + "@test.com", // Add email field
		Username:   userID,               // Add username field
		IsVerified: "true",               // Required: must be "true"
		Roles:      []string{"user"},     // Add roles array
		Type:       "ACCESS_TOKEN",       // Required: must be "ACCESS_TOKEN"
		Realm:      realm,                // Required: must match server realm
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			NotBefore: jwt.NewNumericDate(time.Now()),
			Issuer:    "saturn-turn-server",
			Subject:   userID,
			Audience:  []string{realm},
		},
	}

	// Create token object
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)

	// Sign and get the complete encoded token as a string
	tokenString, err := token.SignedString([]byte(secret))
	if err != nil {
		return "", err
	}

	return tokenString, nil
}

func main() {
	// Get configuration from environment variables
	publicIP := os.Getenv("PUBLIC_IP")
	port := os.Getenv("PORT")
	if port == "" {
		port = "3478"
	}
	accessSecret := os.Getenv("ACCESS_SECRET")

	if publicIP == "" {
		fmt.Printf("Error: PUBLIC_IP environment variable is required\n")
		fmt.Printf("Please set it in your .env file or environment\n")
		os.Exit(1)
	}

	if accessSecret == "" {
		fmt.Printf("Error: ACCESS_SECRET environment variable is required\n")
		fmt.Printf("Please set it in your .env file or environment\n")
		os.Exit(1)
	}

	// TURN server details
	serverAddr := publicIP + ":" + port

	// Generate JWT token using the ACCESS_SECRET

	fmt.Printf("Testing TURN Server Connection\n")
	fmt.Printf("================================\n")
	fmt.Printf("Server: %s\n", serverAddr)
	fmt.Printf("Realm: production\n\n")

	// Generate JWT token for test user
	token, err := generateJWTToken(accessSecret, "test-user-turn", "production")
	if err != nil {
		fmt.Printf("❌ Failed to generate JWT token: %v\n", err)
		return
	}

	fmt.Printf("Generated JWT token: %s...\n\n", token[:20])

	fmt.Printf("Connecting to TURN server...\n")

	// Create UDP connection for TURN client
	conn, err := net.ListenUDP("udp4", nil)
	if err != nil {
		fmt.Printf("❌ Failed to create UDP connection: %v\n", err)
		return
	}
	defer conn.Close()

	fmt.Printf("UDP connection created\n")

	// Create TURN client configuration with proper setup
	cfg := &turn.ClientConfig{
		STUNServerAddr: serverAddr,
		TURNServerAddr: serverAddr,
		Conn:           conn,
		Username:       token,            // JWT token as username
		Password:       "test-user-turn", // Password must match the UserID from JWT token
		Realm:          "production",
		LoggerFactory:  nil, // Disable logging for cleaner output
	}

	fmt.Printf("Attempting TURN authentication...\n")

	// Create TURN client
	client, err := turn.NewClient(cfg)
	if err != nil {
		fmt.Printf("❌ Failed to create TURN client: %v\n", err)
		return
	}
	defer client.Close()

	fmt.Printf("TURN client created successfully\n")

	// Wait for the client to connect
	fmt.Printf("Waiting for TURN connection to establish...\n")

	// Listen for connection state changes
	err = client.Listen()
	if err != nil {
		fmt.Printf("Failed to listen on TURN client: %v\n", err)
		return
	}

	fmt.Printf("TURN client is listening\n")

	// Try to allocate a relay address
	fmt.Printf("Requesting relay address allocation...\n")

	// Set a timeout for allocation
	relayConn, err := client.Allocate()
	if err != nil {
		fmt.Printf("Failed to allocate relay address: %v\n", err)
		return
	}
	defer relayConn.Close()

	fmt.Printf("Successfully allocated relay address!\n")
	fmt.Printf("Relay Address: %s\n", relayConn.LocalAddr())

	// Test the relay connection
	fmt.Printf("Testing relay connection...\n")

	testData := []byte("Hello from TURN relay!")

	// Test writing to a dummy address (we expect this to work even without a real peer)
	dummyAddr, _ := net.ResolveUDPAddr("udp", "8.8.8.8:53")
	n, err := relayConn.WriteTo(testData, dummyAddr)
	if err != nil {
		fmt.Printf("Note: Write test failed (expected without peer): %v\n", err)
	} else {
		fmt.Printf("Successfully wrote %d bytes through relay\n", n)
	}

	fmt.Printf("\nTURN connection test completed successfully!\n")
	fmt.Printf("Server is accepting TURN connections\n")
	fmt.Printf("JWT authentication is working\n")
	fmt.Printf("Relay allocation is successful\n")
}
