package main

import (
	"os"
	"runtime"
	"strings"
	"sync"

	"github.com/rs/zerolog/log"
	"github.com/spf13/viper"
)

type Config struct {
	PublicIP      string `mapstructure:"PUBLIC_IP"`
	Port          int    `mapstructure:"PORT"`
	AccessSecret  string `mapstructure:"ACCESS_SECRET"`
	LogLevel      string `mapstructure:"LOG_LEVEL"`
	Version       string `mapstructure:"VERSION"`
	Branch        string `mapstructure:"BRANCH"`
	BuiltAt       string `mapstructure:"BUILT_AT"`
	ThreadNum     int    `mapstructure:"THREAD_NUM"`
	Realm         string `mapstructure:"REALM"`
	BindAddress   string `mapstructure:"BIND_ADDRESS"` // Address to bind UDP server
	EnableMetrics bool   `mapstructure:"ENABLE_METRICS"`
	MetricsPort   int    `mapstructure:"METRICS_PORT"`

	// Metrics security configuration
	MetricsAuth     string `mapstructure:"METRICS_AUTH"`     // "none", "basic"
	MetricsUsername string `mapstructure:"METRICS_USERNAME"` // For basic auth
	MetricsPassword string `mapstructure:"METRICS_PASSWORD"` // For basic auth
	MetricsBindIP   string `mapstructure:"METRICS_BIND_IP"`  // IP to bind metrics server
}

var (
	Conf Config
	once sync.Once
)

// Get are responsible to load env and get data an return the struct
func GetConfig() *Config {
	// Set default values
	viper.SetDefault("ENABLE_METRICS", false)
	viper.SetDefault("METRICS_PORT", 9090)
	viper.SetDefault("LOG_LEVEL", "info")
	viper.SetDefault("BIND_ADDRESS", "0.0.0.0")

	// Set THREAD_NUM default based on CPU count if not specified in environment
	if os.Getenv("THREAD_NUM") == "" {
		cpuCount := runtime.NumCPU()
		viper.SetDefault("THREAD_NUM", 2*cpuCount)
		log.Info().Int("cpu_count", cpuCount).Msg("THREAD_NUM not specified, using CPU count as default")
	} else {
		viper.SetDefault("THREAD_NUM", 2) // Keep existing default as fallback
	}

	// Security defaults
	viper.SetDefault("METRICS_AUTH", "none")
	viper.SetDefault("METRICS_BIND_IP", "127.0.0.1") // Bind to localhost by default for security

	// Load environment variables from .env file
	viper.AutomaticEnv()
	viper.SetConfigFile(".env")
	_ = viper.ReadInConfig()

	// Read all environment variables and set them in Viper
	for _, env := range os.Environ() {
		parts := strings.SplitN(env, "=", 2)
		if len(parts) != 2 {
			continue
		}
		key := parts[0]
		val := parts[1]

		viper.Set(key, val)
	}

	// Print out all keys Viper knows about
	for _, key := range viper.AllKeys() {
		val := strings.Trim(viper.GetString(key), "\"")
		newKey := strings.ReplaceAll(key, "_", ".")
		viper.Set(newKey, val)
	}

	once.Do(func() {
		log.Info().Msg("Service configuration initialized.")
		err := viper.Unmarshal(&Conf)
		if err != nil {
			log.Fatal().Err(err).Msg("Failed unmarshall config")
		}
	})

	return &Conf
}
