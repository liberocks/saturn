package main

import (
	"net"
	"time"
)

// MetricsPacketConn wraps a net.PacketConn to track traffic metrics
type MetricsPacketConn struct {
	net.PacketConn
	realm string
}

// NewMetricsPacketConn creates a new MetricsPacketConn wrapper
func NewMetricsPacketConn(conn net.PacketConn, realm string) *MetricsPacketConn {
	return &MetricsPacketConn{
		PacketConn: conn,
		realm:      realm,
	}
}

// ReadFrom reads a packet from the connection and records ingress traffic
func (m *MetricsPacketConn) ReadFrom(p []byte) (n int, addr net.Addr, err error) {
	n, addr, err = m.PacketConn.ReadFrom(p)
	if err == nil && n > 0 {
		// Record ingress traffic (incoming data)
		RecordIngressTraffic(m.realm, int64(n))
	}
	return n, addr, err
}

// WriteTo writes a packet to the connection and records egress traffic
func (m *MetricsPacketConn) WriteTo(p []byte, addr net.Addr) (n int, err error) {
	n, err = m.PacketConn.WriteTo(p, addr)
	if err == nil && n > 0 {
		// Record egress traffic (outgoing data)
		RecordEgressTraffic(m.realm, int64(n))
	}
	return n, err
}

// Close closes the underlying connection
func (m *MetricsPacketConn) Close() error {
	return m.PacketConn.Close()
}

// LocalAddr returns the local network address
func (m *MetricsPacketConn) LocalAddr() net.Addr {
	return m.PacketConn.LocalAddr()
}

// SetDeadline sets the read and write deadlines
func (m *MetricsPacketConn) SetDeadline(t time.Time) error {
	return m.PacketConn.SetDeadline(t)
}

// SetReadDeadline sets the deadline for future ReadFrom calls
func (m *MetricsPacketConn) SetReadDeadline(t time.Time) error {
	return m.PacketConn.SetReadDeadline(t)
}

// SetWriteDeadline sets the deadline for future WriteTo calls
func (m *MetricsPacketConn) SetWriteDeadline(t time.Time) error {
	return m.PacketConn.SetWriteDeadline(t)
}
