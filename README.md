# Saturn

Saturn is a TURN server written in Golang that leverages the [Pion](https://github.com/pion) library for WebRTC. Saturn is designed to be secure with a focus providing authentication interoper### Production Security Recommendations

1. **Always use authentication** in production (`METRICS_AUTH=basic`)
2. **Use strong passwords** (minimum 16 characters)
3. **Bind to specific IP** instead of `0.0.0.0` when possible
4. **Monitor access logs** for suspicious activity
5. **Rotate credentials regularly**
6. **Consider network-level security** (VPN, firewall rules)ing JWT token. The goals of Saturn is that the TURN server can be secured with an access token that commonly also being used in other services susch the Backend API, Siganalling Server, or other services.

## Features
- TURN server
- Multithreaded handler
- JWT authentication
- Prometheus metrics and monitoring
- Health check endpoints

## How to run
1. Setup the environment
```bash
cp env.sample .env
```
2. Adjust the configuration in `.env` file according to your setup. The important part is the PUBLIC_IP. If you are running this on a cloud server, you can use the public IP of the server. If you are running this on your local machine, you should first find your local IP address using `ip addr` or `ifconfig` command. It must be something like `192.168.x.x`.

3. Run the server
```bash
go run ./src
```

4. Prior to testing the server, you need to generate a JWT token. You can use the built-in JWT generator:

### Using the JWT Generator

**Option 1: Using Makefile (Recommended)**
```bash
# Generate a token with default settings
make jwt-token

# Generate a token with custom parameters
make jwt-token ARGS="-user-id=myuser -email=user@example.com -expiry=1h"

# See all available options
make jwt-help
```

**Option 2: Direct execution**
```bash
# Generate a token with default settings
go run scripts/jwt-gen.go

# Generate a token with custom parameters
go run scripts/jwt-gen.go -user-id=myuser -email=user@example.com -expiry=1h -roles=admin,user

# See all available options
go run scripts/jwt-gen.go --help
```

**Available Options:**
- `-user-id`: User ID for the token (default: "test-user-123")
- `-email`: Email for the token (default: "test@example.com")
- `-username`: Username for the token (default: "testuser")
- `-is-verified`: Verification status (default: "true")
- `-roles`: Comma-separated list of roles (default: "user,admin")
- `-type`: Token type (default: "ACCESS_TOKEN")
- `-expiry`: Token expiry duration (default: 24h, examples: 1h, 30m, 7d)

5. To test the server, you can use [https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice](https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice). Use access token as the `username` and use `user_id` as the password. The server URL should be `turn:<PUBLIC_IP>:3478`. Make sure to replace `<PUBLIC_IP>` with the public IP address of your server.

## Prometheus Metrics

Saturn provides comprehensive Prometheus metrics for monitoring and observability. When metrics are enabled, the server exposes several endpoints for monitoring:

### Endpoints

- **`/metrics`** - Prometheus metrics endpoint (default port: 9090)
- **`/health`** - Health check endpoint
- **`/info`** - Server information endpoint (JSON)

### Configuration

Enable metrics in your `.env` file:

```bash
ENABLE_METRICS=true    # Enable/disable metrics collection
METRICS_PORT=9090      # Port for metrics HTTP server
```

### Available Metrics

#### Authentication Metrics
- **`saturn_auth_attempts_total`** - Total authentication attempts by realm and result
- **`saturn_auth_success_total`** - Successful authentications by realm and user ID
- **`saturn_auth_failures_total`** - Failed authentications by realm and reason
- **`saturn_auth_duration_seconds`** - Authentication request duration histogram

#### Token Validation Metrics
- **`saturn_token_validations_total`** - Token validation attempts by result and reason

#### Connection Metrics
- **`saturn_active_connections`** - Currently active TURN connections by realm
- **`saturn_connections_total`** - Total TURN connections established by realm

#### Server Metrics
- **`saturn_server_uptime_seconds`** - Server uptime in seconds
- **`saturn_configured_threads`** - Number of configured server threads
- **`saturn_configured_realms`** - Configured realms gauge

#### Memory Metrics
- **`saturn_memory_usage_bytes`** - Current memory usage in bytes (allocated and in use)
- **`saturn_heap_inuse_bytes`** - Bytes in in-use heap spans
- **`saturn_heap_idle_bytes`** - Bytes in idle (unused) heap spans
- **`saturn_heap_sys_bytes`** - Bytes obtained from system for heap
- **`saturn_stack_inuse_bytes`** - Bytes in stack spans
- **`saturn_goroutines_count`** - Number of goroutines that currently exist
- **`saturn_gc_count_total`** - Total number of garbage collection cycles

#### Network Traffic Metrics
- **`saturn_ingress_traffic_mb_total`** - Total ingress (incoming) traffic in megabytes by realm
- **`saturn_egress_traffic_mb_total`** - Total egress (outgoing) traffic in megabytes by realm
- **`saturn_ingress_packets_total`** - Total number of ingress (incoming) packets by realm
- **`saturn_egress_packets_total`** - Total number of egress (outgoing) packets by realm

### Example Prometheus Configuration

Add this job to your `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'saturn-turn-server'
    static_configs:
      - targets: ['your-server:9090']
    scrape_interval: 15s
    metrics_path: /metrics
```

### Example Grafana Dashboard Queries

**Authentication Success Rate:**
```promql
rate(saturn_auth_success_total[5m]) / rate(saturn_auth_attempts_total[5m]) * 100
```

**Active Connections by Realm:**
```promql
sum(saturn_active_connections) by (realm)
```

**Token Validation Failure Rate:**
```promql
rate(saturn_token_validations_total{result="failure"}[5m])
```

**Authentication Duration (95th percentile):**
```promql
histogram_quantile(0.95, rate(saturn_auth_duration_seconds_bucket[5m]))
```

**Memory Usage (in MB):**
```promql
saturn_memory_usage_bytes / 1024 / 1024
```

**Heap Memory Usage:**
```promql
saturn_heap_inuse_bytes / 1024 / 1024
```

**Goroutine Count:**
```promql
saturn_goroutines_count
```

**Garbage Collection Rate:**
```promql
rate(saturn_gc_count_total[5m])
```

**Ingress Traffic Rate (MB/s):**
```promql
rate(saturn_ingress_traffic_mb_total[5m])
```

**Egress Traffic Rate (MB/s):**
```promql
rate(saturn_egress_traffic_mb_total[5m])
```

**Total Traffic by Realm (MB):**
```promql
sum(saturn_ingress_traffic_mb_total + saturn_egress_traffic_mb_total) by (realm)
```

**Packet Rate (packets/s):**
```promql
rate(saturn_ingress_packets_total[5m]) + rate(saturn_egress_packets_total[5m])
```

## Metrics Security

Saturn provides multiple security options to protect your metrics endpoints in production environments.

### Security Features

1. **Authentication Methods**
   - No authentication (development only)
   - HTTP Basic Authentication

2. **Network Security**
   - Configurable bind IP address

3. **Access Control**
   - Separate authentication for metrics vs health endpoints
   - Detailed access logging

### Configuration Options

Add these to your `.env` file for security:

```bash
# Authentication method: "none" or "basic"
METRICS_AUTH=basic

# Basic Authentication
METRICS_USERNAME=prometheus
METRICS_PASSWORD=your_secure_password

# Network binding (default: 127.0.0.1 for security)
METRICS_BIND_IP=127.0.0.1
```