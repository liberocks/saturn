ifneq (,$(wildcard ./.env.stage))
    include .env.stage
    export
endif

BINARY=engine
.PHONY: build format dev jwt-token deploy-fly test-fly fly-logs fly-status fly-ssh help

dev:
	air -c .air.toml

build:
	@echo "Building the binary..."
	@go build -o $(BINARY) ./src
	@if [ -f $(BINARY) ]; then \
		echo "Build successful: $(BINARY) created."; \
	else \
		echo "Build failed."; \
		exit 1; \
	fi

format:
	@echo "Formatting the code..."
	@go fmt ./...
	@go mod tidy
	@gofmt -s -w .
	@echo "Code formatted successfully!"

jwt-token:
	@echo "Generating JWT token for testing..."
	@if [ -f ".env" ]; then \
		export $$(grep -v '^#' .env | xargs) && \
		cd scripts/jwt-gen && \
		go run main.go -user-id=user123 -email=user@test.com; \
	else \
		echo "⚠️  .env file not found. Using default values..."; \
		ACCESS_SECRET=qwertyuiopasdfghjklzxcvbnm123456 REALM=development go run scripts/jwt-gen/main.go -user-id=user123 -email=user@test.com; \
	fi
 