# Saturn TURN Server Configuration Guide

This document explains how to configure the Saturn TURN server using environment variables and the `.env` file.

## Environment Configuration

The server uses environment variables for configuration, which can be set in several ways:

1. **`.env` file** - Recommended for local development and production
2. **Environment variables** - For Docker/container deployments  
3. **Command line** - For testing and scripts

## Configuration Sections

### Core Server Configuration

```bash
# Network configuration
PUBLIC_IP=149.248.196.229        # External IP address for TURN server
PORT=3478                        # TURN/STUN server port
BIND_ADDRESS=fly-global-services  # Address to bind to (fly-global-services for Fly.io)

# Application settings  
REALM=production                 # Authentication realm
USERS=100                       # Maximum concurrent users
THREAD_NUM=10                   # Number of server threads
```

### Security Configuration

```bash
# JWT Authentication
ACCESS_SECRET=your-secret-key-here  # Secret for JWT token signing (min 32 chars)
```

### Metrics and Monitoring

```bash
# Metrics configuration
ENABLE_METRICS=true              # Enable Prometheus metrics
METRICS_PORT=9090               # Metrics server port
METRICS_USERNAME=admin          # Basic auth username for metrics
METRICS_PASSWORD=secret         # Basic auth password for metrics
```

### Testing Configuration

```bash
# Testing settings (used by test scripts)
APP_NAME=saturn-turn-server     # Fly.io app name
TURN_SERVER=149.248.196.229:3478 # Full server address for testing
METRICS_HOST=saturn-turn-server.fly.dev # Metrics endpoint host
```

### Logging Configuration

```bash
# Logging settings
LOG_LEVEL=debug                 # Log level: trace, debug, info, warn, error
```

## Platform-Specific Settings

### For Fly.io Deployment

```bash
# Use fly-global-services for proper UDP routing
BIND_ADDRESS=fly-global-services
PUBLIC_IP=149.248.196.229  # Your Fly.io dedicated IPv4
APP_NAME=your-app-name
```

### For Local Development

```bash
# Use localhost binding for local testing
BIND_ADDRESS=0.0.0.0
PUBLIC_IP=127.0.0.1
TURN_SERVER=localhost:3478
METRICS_HOST=localhost
```

### For Docker/Container Deployment

```bash
# Use container-friendly settings
BIND_ADDRESS=0.0.0.0
PUBLIC_IP=your-external-ip
PORT=3478
```

## Testing Scripts Configuration

The testing scripts automatically load configuration from `.env`:

```bash
# Run comprehensive tests
./scripts/test-turn-server.sh

# Generate JWT tokens using environment settings
make jwt-token
```

## Security Considerations

1. **ACCESS_SECRET**: Use a strong, randomly generated secret (minimum 32 characters)
2. **METRICS_PASSWORD**: Use a secure password for metrics endpoint
3. **Never commit real secrets to version control**

## Examples

### Development Environment (.env)

```bash
ACCESS_SECRET=dev-secret-key-for-testing-only
PUBLIC_IP=127.0.0.1
PORT=3478
BIND_ADDRESS=0.0.0.0
REALM=development
USERS=10
THREAD_NUM=2
LOG_LEVEL=debug
ENABLE_METRICS=true
METRICS_PORT=9090
METRICS_USERNAME=admin
METRICS_PASSWORD=dev-password
APP_NAME=saturn-turn-server-dev
TURN_SERVER=localhost:3478
METRICS_HOST=localhost
```

### Production Environment (.env)

```bash
ACCESS_SECRET=your-production-secret-32-chars-min
PUBLIC_IP=149.248.196.229
PORT=3478
BIND_ADDRESS=fly-global-services
REALM=production
USERS=1000
THREAD_NUM=10
LOG_LEVEL=info
ENABLE_METRICS=true
METRICS_PORT=9090
METRICS_USERNAME=admin
METRICS_PASSWORD=secure-metrics-password
APP_NAME=saturn-turn-server
TURN_SERVER=149.248.196.229:3478
METRICS_HOST=saturn-turn-server.fly.dev
```

## Environment Variable Priority

1. Command line environment variables (highest priority)
2. `.env` file in project root
3. Default values in code (lowest priority)

## Validation

To verify your configuration is loaded correctly:

```bash
# Test the configuration
./scripts/test-turn-server.sh

# Generate and test JWT tokens
make jwt-token

# Check server logs
flyctl logs --app your-app-name
```
