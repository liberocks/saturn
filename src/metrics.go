package main

import (
	"crypto/subtle"
	"net/http"
	"runtime"
	"strconv"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/rs/zerolog/log"
)

// Metrics holds all Prometheus metrics for the TURN server
type Metrics struct {
	// Authentication metrics
	AuthAttempts     *prometheus.CounterVec
	AuthSuccesses    *prometheus.CounterVec
	AuthFailures     *prometheus.CounterVec
	AuthDuration     *prometheus.HistogramVec
	TokenValidations *prometheus.CounterVec

	// Connection metrics
	ActiveConnections *prometheus.GaugeVec
	TotalConnections  *prometheus.CounterVec

	// Server metrics
	ServerUptime      prometheus.Gauge
	ConfiguredThreads prometheus.Gauge
	ConfiguredRealms  *prometheus.GaugeVec

	// Memory metrics
	MemoryUsage    prometheus.Gauge
	HeapInUse      prometheus.Gauge
	HeapIdle       prometheus.Gauge
	HeapSys        prometheus.Gauge
	StackInUse     prometheus.Gauge
	GoroutineCount prometheus.Gauge
	GCCount        prometheus.Counter

	// Network traffic metrics
	IngressTrafficMB *prometheus.CounterVec
	EgressTrafficMB  *prometheus.CounterVec
	IngressPackets   *prometheus.CounterVec
	EgressPackets    *prometheus.CounterVec
}

var (
	// Global metrics instance
	ServerMetrics *Metrics
)

// InitMetrics initializes all Prometheus metrics and registers them with the default registry
func InitMetrics(config *Config) {
	ServerMetrics = &Metrics{
		// Authentication attempt counter by realm and source
		AuthAttempts: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "saturn_auth_attempts_total",
				Help: "Total number of authentication attempts",
			},
			[]string{"realm", "result"},
		),

		// Successful authentication counter by realm
		AuthSuccesses: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "saturn_auth_success_total",
				Help: "Total number of successful authentications",
			},
			[]string{"realm", "user_id"},
		),

		// Failed authentication counter by realm and reason
		AuthFailures: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "saturn_auth_failures_total",
				Help: "Total number of failed authentications",
			},
			[]string{"realm", "reason"},
		),

		// Authentication duration histogram
		AuthDuration: prometheus.NewHistogramVec(
			prometheus.HistogramOpts{
				Name:    "saturn_auth_duration_seconds",
				Help:    "Duration of authentication requests",
				Buckets: prometheus.DefBuckets,
			},
			[]string{"realm", "result"},
		),

		// Token validation counter by result
		TokenValidations: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "saturn_token_validations_total",
				Help: "Total number of token validation attempts",
			},
			[]string{"result", "reason"},
		),

		// Active connections gauge by realm
		ActiveConnections: prometheus.NewGaugeVec(
			prometheus.GaugeOpts{
				Name: "saturn_active_connections",
				Help: "Number of currently active TURN connections",
			},
			[]string{"realm"},
		),

		// Total connections counter by realm
		TotalConnections: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "saturn_connections_total",
				Help: "Total number of TURN connections established",
			},
			[]string{"realm"},
		),

		// Server uptime gauge
		ServerUptime: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "saturn_server_uptime_seconds",
				Help: "Server uptime in seconds",
			},
		),

		// Configured threads gauge
		ConfiguredThreads: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "saturn_configured_threads",
				Help: "Number of configured server threads",
			},
		),

		// Configured realms gauge
		ConfiguredRealms: prometheus.NewGaugeVec(
			prometheus.GaugeOpts{
				Name: "saturn_configured_realms",
				Help: "Configured realms for the server",
			},
			[]string{"realm"},
		),

		// Memory usage metrics
		MemoryUsage: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "saturn_memory_usage_bytes",
				Help: "Current memory usage in bytes",
			},
		),

		HeapInUse: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "saturn_heap_inuse_bytes",
				Help: "Bytes in in-use spans",
			},
		),

		HeapIdle: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "saturn_heap_idle_bytes",
				Help: "Bytes in idle (unused) spans",
			},
		),

		HeapSys: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "saturn_heap_sys_bytes",
				Help: "Bytes obtained from system for heap",
			},
		),

		StackInUse: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "saturn_stack_inuse_bytes",
				Help: "Bytes in stack spans",
			},
		),

		GoroutineCount: prometheus.NewGauge(
			prometheus.GaugeOpts{
				Name: "saturn_goroutines_count",
				Help: "Number of goroutines that currently exist",
			},
		),

		GCCount: prometheus.NewCounter(
			prometheus.CounterOpts{
				Name: "saturn_gc_count_total",
				Help: "Total number of garbage collection cycles",
			},
		),

		// Network traffic metrics
		IngressTrafficMB: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "saturn_ingress_traffic_mb_total",
				Help: "Total ingress (incoming) traffic in megabytes",
			},
			[]string{"realm"},
		),

		EgressTrafficMB: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "saturn_egress_traffic_mb_total",
				Help: "Total egress (outgoing) traffic in megabytes",
			},
			[]string{"realm"},
		),

		IngressPackets: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "saturn_ingress_packets_total",
				Help: "Total number of ingress (incoming) packets",
			},
			[]string{"realm"},
		),

		EgressPackets: prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "saturn_egress_packets_total",
				Help: "Total number of egress (outgoing) packets",
			},
			[]string{"realm"},
		),
	}

	// Register all metrics with Prometheus
	prometheus.MustRegister(
		ServerMetrics.AuthAttempts,
		ServerMetrics.AuthSuccesses,
		ServerMetrics.AuthFailures,
		ServerMetrics.AuthDuration,
		ServerMetrics.TokenValidations,
		ServerMetrics.ActiveConnections,
		ServerMetrics.TotalConnections,
		ServerMetrics.ServerUptime,
		ServerMetrics.ConfiguredThreads,
		ServerMetrics.ConfiguredRealms,
		ServerMetrics.MemoryUsage,
		ServerMetrics.HeapInUse,
		ServerMetrics.HeapIdle,
		ServerMetrics.HeapSys,
		ServerMetrics.StackInUse,
		ServerMetrics.GoroutineCount,
		ServerMetrics.GCCount,
		ServerMetrics.IngressTrafficMB,
		ServerMetrics.EgressTrafficMB,
		ServerMetrics.IngressPackets,
		ServerMetrics.EgressPackets,
	)

	// Set initial static metrics
	ServerMetrics.ConfiguredThreads.Set(float64(config.ThreadNum))
	ServerMetrics.ConfiguredRealms.WithLabelValues(config.Realm).Set(1)

	log.Info().Msg("Prometheus metrics initialized and registered")
}

// SecurityMiddleware provides authentication for metrics endpoints
func SecurityMiddleware(config *Config) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Authentication check
			switch config.MetricsAuth {
			case "basic":
				if !basicAuth(w, r, config.MetricsUsername, config.MetricsPassword) {
					return
				}
			case "none":
				// No authentication required
			default:
				log.Warn().Str("auth_type", config.MetricsAuth).Msg("Unknown metrics auth type, defaulting to none")
			}

			// Log successful access
			log.Debug().
				Str("remote_addr", r.RemoteAddr).
				Str("method", r.Method).
				Str("path", r.URL.Path).
				Str("user_agent", r.UserAgent()).
				Msg("Metrics endpoint accessed")

			next.ServeHTTP(w, r)
		})
	}
}

// basicAuth implements HTTP Basic Authentication
func basicAuth(w http.ResponseWriter, r *http.Request, expectedUsername, expectedPassword string) bool {
	if expectedUsername == "" || expectedPassword == "" {
		log.Error().Msg("Basic auth configured but username/password not set")
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return false
	}

	username, password, ok := r.BasicAuth()
	if !ok {
		w.Header().Set("WWW-Authenticate", `Basic realm="Saturn Metrics"`)
		http.Error(w, "Authentication required", http.StatusUnauthorized)
		return false
	}

	// Use constant-time comparison to prevent timing attacks
	if subtle.ConstantTimeCompare([]byte(username), []byte(expectedUsername)) != 1 ||
		subtle.ConstantTimeCompare([]byte(password), []byte(expectedPassword)) != 1 {
		log.Warn().
			Str("username", username).
			Str("remote_addr", r.RemoteAddr).
			Msg("Metrics basic auth failed")
		w.Header().Set("WWW-Authenticate", `Basic realm="Saturn Metrics"`)
		http.Error(w, "Authentication failed", http.StatusUnauthorized)
		return false
	}

	return true
}

// StartMetricsServer starts the HTTP server for Prometheus metrics endpoint
func StartMetricsServer(config *Config) {
	if !config.EnableMetrics {
		log.Info().Msg("Metrics disabled in configuration")
		return
	}

	// Create HTTP server for metrics with security middleware
	mux := http.NewServeMux()
	securityMiddleware := SecurityMiddleware(config)

	// Protected metrics endpoint
	mux.Handle("/metrics", securityMiddleware(promhttp.Handler()))

	// Health check endpoint (no authentication required)
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("OK"))
	})

	// Protected info endpoint
	mux.HandleFunc("/info", securityMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		info := `{
			"service": "saturn-turn-server",
			"version": "` + config.Version + `",
			"realm": "` + config.Realm + `",
			"threads": ` + strconv.Itoa(config.ThreadNum) + `,
			"metrics_enabled": ` + strconv.FormatBool(config.EnableMetrics) + `,
			"metrics_auth": "` + config.MetricsAuth + `",
			"metrics_bind_ip": "` + config.MetricsBindIP + `"
		}`
		_, _ = w.Write([]byte(info))
	})).ServeHTTP)

	// Determine bind address
	bindAddr := config.MetricsBindIP + ":" + strconv.Itoa(config.MetricsPort)

	server := &http.Server{
		Addr:    bindAddr,
		Handler: mux,
	}

	// Start HTTP metrics server in a goroutine
	go func() {
		log.Info().
			Str("bind_addr", bindAddr).
			Str("auth", config.MetricsAuth).
			Str("endpoint", "/metrics").
			Msg("Starting Prometheus metrics server")

		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Error().Err(err).Msg("Failed to start metrics server")
		}
	}()

	// Log security configuration
	if config.MetricsAuth != "none" {
		log.Info().Str("auth_type", config.MetricsAuth).Msg("Metrics endpoint authentication enabled")
	}
	if config.MetricsBindIP != "0.0.0.0" {
		log.Info().Str("bind_ip", config.MetricsBindIP).Msg("Metrics endpoint bound to specific IP")
	}
} // RecordAuthAttempt records an authentication attempt
func RecordAuthAttempt(realm, result string) {
	if ServerMetrics != nil {
		ServerMetrics.AuthAttempts.WithLabelValues(realm, result).Inc()
	}
}

// RecordAuthSuccess records a successful authentication
func RecordAuthSuccess(realm, userID string) {
	if ServerMetrics != nil {
		ServerMetrics.AuthSuccesses.WithLabelValues(realm, userID).Inc()
	}
}

// RecordAuthFailure records a failed authentication
func RecordAuthFailure(realm, reason string) {
	if ServerMetrics != nil {
		ServerMetrics.AuthFailures.WithLabelValues(realm, reason).Inc()
	}
}

// RecordTokenValidation records a token validation attempt
func RecordTokenValidation(result, reason string) {
	if ServerMetrics != nil {
		ServerMetrics.TokenValidations.WithLabelValues(result, reason).Inc()
	}
}

// RecordConnection records a new connection
func RecordConnection(realm string) {
	if ServerMetrics != nil {
		ServerMetrics.TotalConnections.WithLabelValues(realm).Inc()
		ServerMetrics.ActiveConnections.WithLabelValues(realm).Inc()
	}
}

// RecordDisconnection records a connection ending
func RecordDisconnection(realm string) {
	if ServerMetrics != nil {
		ServerMetrics.ActiveConnections.WithLabelValues(realm).Dec()
	}
}

// UpdateMemoryMetrics updates memory-related metrics
func UpdateMemoryMetrics() {
	if ServerMetrics == nil {
		return
	}

	var m runtime.MemStats
	runtime.ReadMemStats(&m)

	// Update memory metrics
	ServerMetrics.MemoryUsage.Set(float64(m.Alloc))
	ServerMetrics.HeapInUse.Set(float64(m.HeapInuse))
	ServerMetrics.HeapIdle.Set(float64(m.HeapIdle))
	ServerMetrics.HeapSys.Set(float64(m.HeapSys))
	ServerMetrics.StackInUse.Set(float64(m.StackInuse))
	ServerMetrics.GoroutineCount.Set(float64(runtime.NumGoroutine()))

	// Update GC count (this is a counter, so we need to track the delta)
	static := getGCCountTracker()
	currentGC := m.NumGC
	if currentGC > static.lastGCCount {
		ServerMetrics.GCCount.Add(float64(currentGC - static.lastGCCount))
		static.lastGCCount = currentGC
	}
}

// gcCountTracker helps track GC count changes for the counter metric
type gcCountTracker struct {
	lastGCCount uint32
}

var gcTracker *gcCountTracker

func getGCCountTracker() *gcCountTracker {
	if gcTracker == nil {
		gcTracker = &gcCountTracker{lastGCCount: 0}
	}
	return gcTracker
}

// RecordIngressTraffic records incoming traffic in bytes
func RecordIngressTraffic(realm string, bytes int64) {
	if ServerMetrics != nil {
		// Convert bytes to megabytes (1 MB = 1,048,576 bytes)
		megabytes := float64(bytes) / 1048576.0
		ServerMetrics.IngressTrafficMB.WithLabelValues(realm).Add(megabytes)
		ServerMetrics.IngressPackets.WithLabelValues(realm).Inc()
	}
}

// RecordEgressTraffic records outgoing traffic in bytes
func RecordEgressTraffic(realm string, bytes int64) {
	if ServerMetrics != nil {
		// Convert bytes to megabytes (1 MB = 1,048,576 bytes)
		megabytes := float64(bytes) / 1048576.0
		ServerMetrics.EgressTrafficMB.WithLabelValues(realm).Add(megabytes)
		ServerMetrics.EgressPackets.WithLabelValues(realm).Inc()
	}
}
