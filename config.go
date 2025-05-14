package main

import (
	"os"
	"strings"
	"sync"

	"github.com/rs/zerolog/log"
	"github.com/spf13/viper"
)

type Config struct {
	PublicIP     string `mapstructure:"PUBLIC_IP"`
	Port         int    `mapstructure:"PORT"`
	AccessSecret string `mapstructure:"ACCESS_SECRET"`
	LogLevel     string `mapstructure:"LOG_LEVEL"`
	Version      string `mapstructure:"VERSION"`
	Branch       string `mapstructure:"BRANCH"`
	BuiltAt      string `mapstructure:"BUILT_AT"`
	ThreadNum    int    `mapstructure:"THREAD_NUM"`
	Realm        string `mapstructure:"REALM"`
}

var (
	Conf Config
	once sync.Once
)

// Get are responsible to load env and get data an return the struct
func GetConfig() *Config {
	// Load environment variables from .env file
	viper.AutomaticEnv()
	viper.SetConfigFile(".env")
	_ = viper.ReadInConfig()

	// Read all environment variables and set them in Viper
	for _, env := range os.Environ() {
		parts := strings.SplitN(env, "=", 2)
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
