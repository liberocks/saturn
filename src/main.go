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
	bindAddress := config.BindAddress
	ipv4Only := config.IPv4Only

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
		Str("bind_address", bindAddress).
		Bool("ipv4_only", ipv4Only).
		Bool("metrics_enabled", config.EnableMetrics).
		Int("metrics_port", config.MetricsPort).
		Msg("Starting TURN server with configuration")

	if len(publicIP) == 0 {
		log.Fatal().Msg("'public-ip' is required")
	}

	// For Fly.io UDP, we must bind to the special fly-global-services address
	// This is required for UDP traffic to be properly routed by Fly.io
	// Can be configured via BIND_ADDRESS environment variable
	// Use IPv4 only to avoid IPv6 DNS resolution issues
	network := "udp"
	if ipv4Only {
		network = "udp4"
	}
	addr, err := net.ResolveUDPAddr(network, bindAddress+":"+strconv.Itoa(port))
	if err != nil {
		log.Fatal().Msgf("Failed to parse server address: %s", err)
	}

	log.Info().
		Str("resolved_network", addr.Network()).
		Str("resolved_address", addr.String()).
		Str("bind_address", bindAddress).
		Bool("ipv4_only", ipv4Only).
		Msg("Resolved UDP address for binding")

	// Create `numThreads` UDP listeners to pass into pion/turn
	// pion/turn itself doesn't allocate any UDP sockets, but lets the user pass them in
	// this allows us to add logging, storage or modify inbound/outbound traffic
	// UDP listeners share the same local address:port with setting SO_REUSEPORT and the kernel
	// will load-balance received packets per the IP 5-tuple
	listenerConfig := &net.ListenConfig{
		Control: func(network, address string, conn syscall.RawConn) error { // nolint: revive
			var operr error
			if err = conn.Control(func(fd uintptr) {
				// Set SO_REUSEPORT for load balancing
				operr = syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, unix.SO_REUSEPORT, 1)
				if operr != nil {
					return
				}
				// Set SO_REUSEADDR for better address reuse
				operr = syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_REUSEADDR, 1)
			}); err != nil {
				return err
			}

			return operr
		},
	}

	// For Fly.io deployment, we need to use the same address resolution as the main server
	// The RelayAddress should be the public IP that clients connect to,
	// but the Address should be what we can actually bind to inside the container
	relayNetwork := "udp"
	if ipv4Only {
		relayNetwork = "udp4"
	}
	relayAddr, err := net.ResolveUDPAddr(relayNetwork, bindAddress+":0")
	if err != nil {
		log.Fatal().Err(err).Str("bind_address", bindAddress).Msg("Failed to resolve relay address")
	}

	relayAddressGenerator := &turn.RelayAddressGeneratorStatic{
		RelayAddress: net.ParseIP(publicIP), // Clients connect to the public IP
		Address:      relayAddr.IP.String(), // Use the resolved fly-global-services IP for binding
	}

	packetConnConfigs := make([]turn.PacketConnConfig, threadNum)
	for i := range threadNum {
		conn, listErr := listenerConfig.ListenPacket(context.Background(), addr.Network(), addr.String())
		if listErr != nil {
			log.Fatal().Msgf("Failed to allocate UDP listener at %s:%s", addr.Network(), addr.String())
		}

		// Log the actual local address to debug binding issues
		localAddr := conn.LocalAddr()
		log.Info().
			Int("server_id", i).
			Str("network", addr.Network()).
			Str("bind_addr", addr.String()).
			Str("actual_local_addr", localAddr.String()).
			Msgf("Server %d listening on %s", i, localAddr.String())

		// Use the connection directly, with metrics tracking if enabled
		wrappedConn := conn
		if config.EnableMetrics {
			wrappedConn = NewMetricsPacketConn(wrappedConn, realm)
		}

		packetConnConfigs[i] = turn.PacketConnConfig{
			PacketConn:            wrappedConn,
			RelayAddressGenerator: relayAddressGenerator,
		}
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
