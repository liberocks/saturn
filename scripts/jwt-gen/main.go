package main

import (
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/spf13/viper"
)

// Claims defines the custom JWT claims structure for our application tokens.
// This mirrors the structure used in the main application.
type Claims struct {
	UserID               string   `json:"user_id"`     // Unique identifier for the user
	Email                string   `json:"email"`       // User's email address
	Username             string   `json:"username"`    // User's username
	IsVerified           string   `json:"is_verified"` // Verification status ("true" or "false")
	Roles                []string `json:"roles"`       // User's assigned roles for authorization
	Type                 string   `json:"type"`        // Token type (e.g., "ACCESS_TOKEN")
	Realm                string   `json:"realm"`       // Authentication realm, used for multi-tenant environments
	jwt.RegisteredClaims          // Standard JWT claims (iat, exp, etc.)
}

// Config holds the configuration needed for token generation
type Config struct {
	AccessSecret string `mapstructure:"ACCESS_SECRET"`
	Realm        string `mapstructure:"REALM"`
}

func main() {
	// Define command-line flags
	var (
		userID     = flag.String("user-id", "test-user-123", "User ID for the token")
		email      = flag.String("email", "test@example.com", "Email for the token")
		username   = flag.String("username", "testuser", "Username for the token")
		isVerified = flag.String("is-verified", "true", "Verification status (true/false)")
		roles      = flag.String("roles", "user,admin", "Comma-separated list of roles")
		tokenType  = flag.String("type", "ACCESS_TOKEN", "Token type")
		expiry     = flag.Duration("expiry", 24*time.Hour, "Token expiry duration (e.g., 1h, 24h, 7d)")
	)

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "JWT Token Generator for Saturn TURN Server\n\n")
		fmt.Fprintf(os.Stderr, "Usage: make jwt-token [options]\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		flag.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nEnvironment Variables:\n")
		fmt.Fprintf(os.Stderr, "  ACCESS_SECRET    Secret key for signing tokens (required)\n")
		fmt.Fprintf(os.Stderr, "  REALM           Authentication realm (required)\n")
		fmt.Fprintf(os.Stderr, "\nExample:\n")
		fmt.Fprintf(os.Stderr, "  ACCESS_SECRET=mysecret REALM=development make jwt-token -user-id=user123 -email=user@test.com\n")
	}

	flag.Parse()

	// Load configuration
	config, err := loadConfig()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading configuration: %v\n", err)
		os.Exit(1)
	}

	// Validate required configuration
	if config.AccessSecret == "" {
		fmt.Fprintf(os.Stderr, "ACCESS_SECRET environment variable is required\n")
		os.Exit(1)
	}

	if config.Realm == "" {
		fmt.Fprintf(os.Stderr, "REALM environment variable is required\n")
		os.Exit(1)
	}

	// Parse roles from comma-separated string
	rolesList := strings.Split(*roles, ",")
	for i, role := range rolesList {
		rolesList[i] = strings.TrimSpace(role)
	}

	// Create token claims
	now := time.Now()
	claims := Claims{
		UserID:     *userID,
		Email:      *email,
		Username:   *username,
		IsVerified: *isVerified,
		Roles:      rolesList,
		Type:       *tokenType,
		Realm:      config.Realm,
		RegisteredClaims: jwt.RegisteredClaims{
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(*expiry)),
		},
	}

	// Generate the token
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(config.AccessSecret))
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error generating token: %v\n", err)
		os.Exit(1)
	}

	// Output the token
	fmt.Println("Generated JWT Token:")
	fmt.Println(tokenString)
	fmt.Println()

	// Output token details for verification
	fmt.Println("Token Details:")
	fmt.Printf("  User ID:      %s\n", claims.UserID)
	fmt.Printf("  Email:        %s\n", claims.Email)
	fmt.Printf("  Username:     %s\n", claims.Username)
	fmt.Printf("  Is Verified:  %s\n", claims.IsVerified)
	fmt.Printf("  Roles:        %s\n", strings.Join(claims.Roles, ", "))
	fmt.Printf("  Type:         %s\n", claims.Type)
	fmt.Printf("  Realm:        %s\n", claims.Realm)
	fmt.Printf("  Issued At:    %s\n", claims.IssuedAt.Time.Format(time.RFC3339))
	fmt.Printf("  Expires At:   %s\n", claims.ExpiresAt.Time.Format(time.RFC3339))
	fmt.Println()

	// Output usage example
	fmt.Println("Usage Example:")
	fmt.Printf("  Use this token as the username in TURN authentication.\n")
	fmt.Printf("  The password can be any string (it's not validated).\n")
}

// loadConfig loads configuration from environment variables
func loadConfig() (*Config, error) {
	viper.AutomaticEnv()

	// Try to load from .env file if it exists
	viper.SetConfigFile(".env")
	_ = viper.ReadInConfig() // Ignore error if file doesn't exist

	// Read all environment variables
	for _, env := range os.Environ() {
		parts := strings.SplitN(env, "=", 2)
		if len(parts) == 2 {
			key := parts[0]
			val := parts[1]
			viper.Set(key, val)
		}
	}

	var config Config
	err := viper.Unmarshal(&config)
	if err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	return &config, nil
}
