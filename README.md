# Saturn

⚠️ This project is still in development and not yet ready for production use.

Saturn is a TURN server written in Golang that leverages the [Pion](https://github.com/pion) library for WebRTC. Saturn is designed to be secure with a focus providing authentication interoperability using JWT token. The goals of Saturn is that the TURN server can be secured with an access token that commonly also being used in other services susch the Backend API, Siganalling Server, or other services.

## Features
- TURN server
- Multithreaded handler
- JWT authentication

## How to run
1. Setup the environment
```bash
cp env.sample .env
```
2. Adjust the configuration in `.env` file according to your setup. The important part is the PUBLIC_IP. If you are running this on a cloud server, you can use the public IP of the server. If you are running this on your local machine, you should first find your local IP address using `ip addr` or `ifconfig` command. It must be something like `192.168.x.x`.

3. Run the server
```bash
go run main.go
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