package main

import (
	"os"

	"github.com/pkg/errors"     // For enhanced error handling with stack traces
	"github.com/rs/zerolog"     // Zero-allocation JSON logger
	"github.com/rs/zerolog/log" // Global logger instance
)

// InitLogger configures and initializes the zerolog logging system with the following settings:
// - Sets the time format to Unix timestamp for standardized time representation
// - Initializes the global log level to the most verbose (Trace) initially
// - Configures JSON output for structured, parseable logs
// - Sets up the global logger instance
//
// This function should be called early in the application startup process
// before any logging is needed.
func InitLogger() {
	// Configure zerolog to use Unix timestamp format for consistent time representation
	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix

	// Set the most verbose logging level initially
	// This ensures all logs are captured until a more specific level is set
	zerolog.SetGlobalLevel(zerolog.TraceLevel)

	// Configure the global logger to output structured JSON logs directly to stdout
	// This ensures logs are parseable by log aggregation tools like ELK, Fluentd, etc.
	log.Logger = zerolog.New(os.Stdout).With().Timestamp().Logger()

	// Log confirmation that the logger has been initialized
	log.Trace().Msg("Zerolog initialized with JSON output")
}

// ErrorWithStack logs an error along with its complete stack trace.
// This provides much more context about where errors occur than standard error logging.
//
// Parameters:
//   - err: The error to be logged with its stack trace
//
// The function uses the errors.WithStack wrapper to capture the stack trace
// at the point where this function is called, then formats it with the %+v verb
// to include the full stack in the output.
func ErrorWithStack(err error) {
	log.Error().Msgf("%+v", errors.WithStack(err))
}

// SetLogLevel sets the desired log level specified in env var.
//
// Parameters:
//   - config: A pointer to the Config struct containing the desired log level
//
// The function parses the log level from the configuration and sets it globally.
// If the log level is invalid or not set, it defaults to Trace level and logs a message.
func SetLogLevel(config *Config) {
	level, err := zerolog.ParseLevel(config.LogLevel)
	if err != nil {
		level = zerolog.TraceLevel
		log.Trace().Str("loglevel", level.String()).Msg("Environment has no log level set up, using default.")
	} else {
		log.Trace().Str("loglevel", level.String()).Msg("Desired log level detected.")
	}
	zerolog.SetGlobalLevel(level)
}
