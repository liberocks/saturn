FROM golang:alpine AS builder

ARG VERSION=main

RUN apk add --no-cache git

WORKDIR /build/saturn

# Download all the dependencies
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Build static binary from src directory
RUN GOFLAGS="-buildvcs=false" CGO_ENABLED=0 go build -o main ./src

##### main
FROM alpine

ARG BUILD_DATE
ARG VCS_REF
ARG VERSION=main

LABEL org.label-schema.build-date="${BUILD_DATE}" \
      org.label-schema.name="saturn" \
      org.label-schema.description="An TURN server than use JWT token to authenticate" \
      org.label-schema.usage="https://github.com/liberocks/saturn" \
      org.label-schema.vcs-ref="${VCS_REF}" \
      org.label-schema.vcs-url="https://github.com/liberocks/saturn" \
      org.label-schema.vendor="Tirtadwipa Manunggal" \
      org.label-schema.version="${VERSION}" \
      maintainer="https://github.com/liberocks"

EXPOSE 3478 9090

USER nobody

# Copy the executable
COPY --from=builder /build/saturn/main /usr/bin/

# Run the executable
CMD ["/usr/bin/main"]