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
	UserID               string `json:"user_id"`     // Unique identifier for the user
	Email                string `json:"email"`       // User's email address
	Username             string `json:"username"`    // User's username
	IsVerified           string `json:"is_verified"` // Verification status ("true" or "false")
	Role                 string `json:"role"`        // User's assigned role for authorization
	Type                 string `json:"type"`        // Token type (e.g., "ACCESS_TOKEN")
	Realm                string `json:"realm"`       // Authentication realm, used for multi-tenant environments
	jwt.RegisteredClaims        // Standard JWT claims (iat, exp, etc.)
}

// Config holds the configuration needed for token generation
type Config struct {
	AccessSecret string `mapstructure:"ACCESS_SECRET"`
	Realm        string `mapstructure:"REALM"`
}

func main() {
	// Define command-line flags
	var (
		userID       = flag.String("user-id", "test-user-123", "User ID for the token")
		email        = flag.String("email", "test@example.com", "Email for the token")
		username     = flag.String("username", "testuser", "Username for the token")
		isVerified   = flag.String("is-verified", "true", "Verification status (true/false)")
		role         = flag.String("role", "user", "User's assigned role for authorization")
		tokenType    = flag.String("type", "ACCESS_TOKEN", "Token type")
		expiry       = flag.Duration("expiry", 24*time.Hour, "Token expiry duration (e.g., 1h, 24h, 7d)")
		accessSecret = flag.String("secret", "", "Access secret for signing tokens (overrides ACCESS_SECRET env var)")
		realm        = flag.String("realm", "", "Authentication realm (overrides REALM env var)")
	)

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "JWT Token Generator for Saturn TURN Server\n\n")
		fmt.Fprintf(os.Stderr, "Usage: go run scripts/jwt-gen/main.go [options]\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		flag.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nConfiguration Priority (highest to lowest):\n")
		fmt.Fprintf(os.Stderr, "  1. Command-line flags (-secret, -realm)\n")
		fmt.Fprintf(os.Stderr, "  2. Environment variables (ACCESS_SECRET, REALM)\n")
		fmt.Fprintf(os.Stderr, "  3. .env file\n")
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  # Using environment variables:\n")
		fmt.Fprintf(os.Stderr, "  ACCESS_SECRET=mysecret REALM=development go run scripts/jwt-gen/main.go -user-id=user123\n")
		fmt.Fprintf(os.Stderr, "\n  # Using command-line flags:\n")
		fmt.Fprintf(os.Stderr, "  go run scripts/jwt-gen/main.go -secret=mysecret -realm=development -user-id=user123 -email=user@test.com\n")
		fmt.Fprintf(os.Stderr, "\n  # Using .env file:\n")
		fmt.Fprintf(os.Stderr, "  echo 'ACCESS_SECRET=mysecret' > .env && echo 'REALM=development' >> .env\n")
		fmt.Fprintf(os.Stderr, "  go run scripts/jwt-gen/main.go -user-id=user123\n")
	}

	flag.Parse()

	// Load configuration
	config, err := loadConfig()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error loading configuration: %v\n", err)
		os.Exit(1)
	}

	// Validate required configuration with priority: CLI flag > env var > config file
	if *accessSecret != "" {
		// Command-line flag takes highest priority
		config.AccessSecret = *accessSecret
	} else if config.AccessSecret == "" {
		// Try direct environment variable access as fallback
		if envSecret := os.Getenv("ACCESS_SECRET"); envSecret != "" {
			config.AccessSecret = envSecret
		} else {
			fmt.Fprintf(os.Stderr, "ACCESS_SECRET is required. Provide it via:\n")
			fmt.Fprintf(os.Stderr, "  1. Command line: -secret=your_secret_key\n")
			fmt.Fprintf(os.Stderr, "  2. Environment variable: export ACCESS_SECRET=your_secret_key\n")
			fmt.Fprintf(os.Stderr, "  3. .env file: ACCESS_SECRET=your_secret_key\n")
			os.Exit(1)
		}
	}

	if *realm != "" {
		// Command-line flag takes highest priority
		config.Realm = *realm
	} else if config.Realm == "" {
		// Try direct environment variable access as fallback
		if envRealm := os.Getenv("REALM"); envRealm != "" {
			config.Realm = envRealm
		} else {
			fmt.Fprintf(os.Stderr, "REALM is required. Provide it via:\n")
			fmt.Fprintf(os.Stderr, "  1. Command line: -realm=your_realm\n")
			fmt.Fprintf(os.Stderr, "  2. Environment variable: export REALM=your_realm\n")
			fmt.Fprintf(os.Stderr, "  3. .env file: REALM=your_realm\n")
			os.Exit(1)
		}
	}

	// Create token claims
	now := time.Now()
	claims := Claims{
		UserID:     *userID,
		Email:      *email,
		Username:   *username,
		IsVerified: *isVerified,
		Role:       *role,
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
	fmt.Printf("  Role:        %s\n", claims.Role)
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
