package main

import (
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/rs/zerolog/log"
)

// Claims defines the custom JWT claims structure for our application tokens.
// It extends the standard JWT RegisteredClaims with additional application-specific fields.
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

// ValidateToken validates a JWT token string and returns the claims if valid.
// It performs multiple checks:
// 1. Token signature validation
// 2. Token expiration check
// 3. Verification status check
// 4. Realm validation
// 5. Token type verification
//
// Returns the parsed Claims if valid, or an error if validation fails.
func ValidateToken(tokenString string) (*Claims, error) {
	// Record token validation attempt
	defer func() {
		// This will be overridden below based on actual result
		RecordTokenValidation("attempt", "unknown")
	}()

	// Parse and validate the JWT token
	// Conf.AccessSecret is the secret key used to sign tokens
	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		return []byte(Conf.AccessSecret), nil
	}, jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}))

	// Handle token parsing errors
	if err != nil {
		if errors.Is(err, jwt.ErrTokenExpired) {
			log.Error().Msgf("Invalid token [Reason: token expired]")
			RecordTokenValidation("failure", "token_expired")
			// Token is expired
			return nil, fmt.Errorf("token expired")
		}

		log.Error().Err(err).Msg("failed to parse token")
		RecordTokenValidation("failure", "parse_error")
		return nil, err
	}

	// Extract claims from the token and check validity
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok || !token.Valid {
		log.Error().Msgf("Invalid token [Reason: claims not valid]")
		RecordTokenValidation("failure", "invalid_claims")
		return nil, fmt.Errorf("invalid token")
	}

	// Check if user is verified
	// This ensures only verified users can use the token
	if _, ok := claims["is_verified"]; !ok {
		log.Error().Msgf("Invalid token [Reason: is_verified not found]")
		RecordTokenValidation("failure", "is_verified_missing")
		return nil, fmt.Errorf("invalid token")
	}
	if claims["is_verified"].(string) != "true" {
		log.Error().Msgf("Invalid token [Reason: is_verified not true]")
		RecordTokenValidation("failure", "is_verified_false")
		return nil, fmt.Errorf("invalid token")
	}

	// Validate token realm matches server realm
	// This prevents tokens from one environment being used in another
	if _, ok := claims["realm"]; !ok {
		log.Error().Msgf("Invalid token [Reason: realm not found]")
		RecordTokenValidation("failure", "realm_missing")
		return nil, fmt.Errorf("invalid token")
	}
	if claims["realm"].(string) != Conf.Realm {
		log.Error().Msgf("Invalid token [Reason: realm mismatch]")
		RecordTokenValidation("failure", "realm_mismatch")
		return nil, fmt.Errorf("invalid token")
	}

	// Ensure token type is ACCESS_TOKEN
	// This prevents refresh tokens or other token types from being used for access
	if _, ok := claims["type"]; !ok {
		log.Error().Msgf("Invalid token [Reason: type not found]")
		RecordTokenValidation("failure", "type_missing")
		return nil, fmt.Errorf("invalid token")
	}
	if claims["type"].(string) != "ACCESS_TOKEN" {
		log.Error().Msgf("Invalid token [Reason: type not access]")
		RecordTokenValidation("failure", "type_not_access")
		return nil, fmt.Errorf("invalid token")
	}

	// Ensure user role is present
	if _, ok := claims["role"]; !ok {
		log.Error().Msgf("Invalid token [Reason: role not found]")
		RecordTokenValidation("failure", "role_missing")
		return nil, fmt.Errorf("invalid token")
	}

	// Construct a proper Claims struct from the parsed map claims
	payload := Claims{
		UserID:     claims["user_id"].(string),
		Email:      claims["email"].(string),
		Username:   claims["username"].(string),
		IsVerified: claims["is_verified"].(string),
		Type:       claims["type"].(string),
		Realm:      claims["realm"].(string),
		Role:       claims["role"].(string),
		RegisteredClaims: jwt.RegisteredClaims{
			// Convert numeric dates from the token to proper time.Time objects
			ExpiresAt: jwt.NewNumericDate(time.Unix(int64(claims["exp"].(float64)), 0)),
			IssuedAt:  jwt.NewNumericDate(time.Unix(int64(claims["iat"].(float64)), 0)),
		},
	}

	// Double-check expiration time
	// This is a safeguard in case the JWT library didn't properly validate expiration
	if payload.ExpiresAt.Before(time.Now()) {
		RecordTokenValidation("failure", "token_expired_double_check")
		return nil, fmt.Errorf("token expired")
	}

	// Record successful token validation
	RecordTokenValidation("success", "valid")

	return &payload, nil
}
