package main

import (
	"context"
	"net"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/pion/turn/v4"
	"github.com/rs/zerolog/log"
	"golang.org/x/sys/unix"
)

func main() { //nolint:cyclop
	config := GetConfig()
	publicIP := config.PublicIP
	port := config.Port
	realm := config.Realm
	threadNum := config.ThreadNum

	InitLogger()
	SetLogLevel(config)

	// Initialize Prometheus metrics if enabled
	if config.EnableMetrics {
		InitMetrics(config)
		StartMetricsServer(config)
	}

	// Log server startup configuration
	log.Info().
		Str("public_ip", publicIP).
		Int("port", port).
		Str("realm", realm).
		Int("thread_num", threadNum).
		Bool("metrics_enabled", config.EnableMetrics).
		Int("metrics_port", config.MetricsPort).
		Msg("Starting TURN server with configuration")

	if len(publicIP) == 0 {
		log.Fatal().Msg("'public-ip' is required")
	}
	addr, err := net.ResolveUDPAddr("udp", "0.0.0.0:"+strconv.Itoa(port))
	if err != nil {
		log.Fatal().Msgf("Failed to parse server address: %s", err)
	}

	// Create `numThreads` UDP listeners to pass into pion/turn
	// pion/turn itself doesn't allocate any UDP sockets, but lets the user pass them in
	// this allows us to add logging, storage or modify inbound/outbound traffic
	// UDP listeners share the same local address:port with setting SO_REUSEPORT and the kernel
	// will load-balance received packets per the IP 5-tuple
	listenerConfig := &net.ListenConfig{
		Control: func(network, address string, conn syscall.RawConn) error { // nolint: revive
			var operr error
			if err = conn.Control(func(fd uintptr) {
				operr = syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, unix.SO_REUSEPORT, 1)
			}); err != nil {
				return err
			}

			return operr
		},
	}

	relayAddressGenerator := &turn.RelayAddressGeneratorStatic{
		RelayAddress: net.ParseIP(publicIP), // Claim that we are listening on IP passed by user
		Address:      "0.0.0.0",             // But actually be listening on every interface
	}

	packetConnConfigs := make([]turn.PacketConnConfig, threadNum)
	for i := range threadNum {
		conn, listErr := listenerConfig.ListenPacket(context.Background(), addr.Network(), addr.String())
		if listErr != nil {
			log.Fatal().Msgf("Failed to allocate UDP listener at %s:%s", addr.Network(), addr.String())
		}

		// Wrap the connection with metrics tracking if metrics are enabled
		var wrappedConn net.PacketConn = conn
		if config.EnableMetrics {
			wrappedConn = NewMetricsPacketConn(conn, realm)
		}

		packetConnConfigs[i] = turn.PacketConnConfig{
			PacketConn:            wrappedConn,
			RelayAddressGenerator: relayAddressGenerator,
		}

		log.Info().Msgf("Server %d listening on %s", i, conn.LocalAddr().String())
	}

	server, err := turn.NewServer(turn.ServerConfig{
		Realm: realm,
		// Set AuthHandler callback
		// This is called every time a user tries to authenticate with the TURN server
		// Return the key for that user, or false when no user is found
		AuthHandler: func(accessToken string, realm string, srcAddr net.Addr) ([]byte, bool) { //nolint:revive
			startTime := time.Now()

			// Log authentication attempt with source address and realm
			log.Info().
				Str("realm", realm).
				Str("source_addr", srcAddr.String()).
				Str("token_preview", safeTokenPreview(accessToken)).
				Msg("TURN authentication attempt")

			// Record authentication attempt
			RecordAuthAttempt(realm, "attempt")

			payload, err := ValidateToken(accessToken)

			if err != nil {
				// Record authentication failure with timing
				duration := time.Since(startTime)
				if ServerMetrics != nil {
					ServerMetrics.AuthDuration.WithLabelValues(realm, "failure").Observe(duration.Seconds())
				}
				RecordAuthAttempt(realm, "failure")
				RecordAuthFailure(realm, "token_validation_failed")

				log.Error().
					Err(err).
					Str("realm", realm).
					Str("source_addr", srcAddr.String()).
					Str("token_preview", safeTokenPreview(accessToken)).
					Msg("Token validation failed - authentication denied")
				return nil, false
			}

			// Record successful authentication with timing
			duration := time.Since(startTime)
			if ServerMetrics != nil {
				ServerMetrics.AuthDuration.WithLabelValues(realm, "success").Observe(duration.Seconds())
			}
			RecordAuthAttempt(realm, "success")
			RecordAuthSuccess(realm, payload.UserID)
			RecordConnection(realm)

			// Log successful authentication
			log.Info().
				Str("realm", realm).
				Str("source_addr", srcAddr.String()).
				Str("user_id", payload.UserID).
				Str("token_preview", safeTokenPreview(accessToken)).
				Msg("Token validation successful - authentication granted")

			return turn.GenerateAuthKey(accessToken, realm, payload.UserID), true
		},
		// PacketConnConfigs is a list of UDP Listeners and the configuration around them
		PacketConnConfigs: packetConnConfigs,
	})
	if err != nil {
		log.Panic().Msgf("Failed to create TURN server: %s", err)
	}

	log.Info().Msg("TURN server created successfully, waiting for connections")

	// Record server start time for uptime tracking
	if ServerMetrics != nil {
		// Set up a goroutine to update server uptime and memory metrics every 30 seconds
		go func() {
			startTime := time.Now()
			ticker := time.NewTicker(30 * time.Second)
			defer ticker.Stop()

			for range ticker.C {
				ServerMetrics.ServerUptime.Set(time.Since(startTime).Seconds())
				UpdateMemoryMetrics()
			}
		}()
	}

	// Block until user sends SIGINT or SIGTERM
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	sig := <-sigs

	log.Info().Str("signal", sig.String()).Msg("Received shutdown signal, closing TURN server")

	if err = server.Close(); err != nil {
		log.Panic().Msgf("Failed to close TURN server: %s", err)
	}

	log.Info().Msg("TURN server shutdown completed")
}
