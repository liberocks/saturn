#!/bin/bash

# Debug script for Error 701: STUN/TURN host lookup failures
# This script performs comprehensive connectivity tests for the TURN server
# deployed on Fly.io at saturn.fly.dev:3478

set -e

echo "=== Error 701 Debugging Script ==="
echo "Testing STUN/TURN connectivity for saturn.fly.dev:3478"
echo "Date: $(date)"
echo ""

# Configuration
TURN_HOST="saturn.fly.dev"
TURN_IP="66.51.120.77"
TURN_PORT="3478"
STUN_SERVER="${TURN_HOST}:${TURN_PORT}"

echo "=== 1. DNS Resolution Test ==="
echo "Testing DNS resolution for ${TURN_HOST}..."
nslookup ${TURN_HOST} || echo "DNS lookup failed"
echo ""

echo "=== 2. Basic Network Connectivity Test ==="
echo "Testing ping to ${TURN_IP}..."
ping -c 3 ${TURN_IP} || echo "Ping failed - this is expected for some cloud providers"
echo ""

echo "=== 3. Port Connectivity Test ==="
echo "Testing UDP port ${TURN_PORT} connectivity..."
nc -u -v -w 3 ${TURN_HOST} ${TURN_PORT} < /dev/null || echo "UDP connection test failed"
echo ""

echo "=== 4. TCP Port Test (if available) ==="
echo "Testing TCP port ${TURN_PORT} connectivity..."
nc -v -w 3 ${TURN_HOST} ${TURN_PORT} < /dev/null || echo "TCP connection test failed"
echo ""

echo "=== 5. STUN Binding Request Test ==="
echo "Creating Python STUN client test..."

cat > /tmp/stun_test.py << 'EOF'
#!/usr/bin/env python3
import socket
import struct
import random
import sys

def create_stun_binding_request():
    """Create a STUN Binding Request message"""
    # STUN Message Type: Binding Request (0x0001)
    msg_type = 0x0001
    # Message Length (20 bytes for header + 0 bytes attributes)
    msg_length = 0x0000
    # Magic Cookie (RFC 5389)
    magic_cookie = 0x2112A442
    # Transaction ID (96 bits / 12 bytes)
    transaction_id = struct.pack('>III', 
                                random.randint(0, 0xFFFFFFFF),
                                random.randint(0, 0xFFFFFFFF), 
                                random.randint(0, 0xFFFFFFFF))
    
    # Pack the STUN header
    header = struct.pack('>HHII', msg_type, msg_length, magic_cookie, 
                        *struct.unpack('>III', transaction_id))
    
    return header

def test_stun_server(host, port):
    """Test STUN server connectivity"""
    try:
        print(f"Creating STUN Binding Request for {host}:{port}")
        
        # Create UDP socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(5.0)  # 5 second timeout
        
        # Create STUN Binding Request
        stun_request = create_stun_binding_request()
        
        print(f"Sending STUN Binding Request ({len(stun_request)} bytes)...")
        print(f"Request hex: {stun_request.hex()}")
        
        # Send request
        sock.sendto(stun_request, (host, port))
        
        # Wait for response
        print("Waiting for STUN response...")
        response, addr = sock.recvfrom(1024)
        
        print(f"✅ SUCCESS: Received STUN response from {addr}")
        print(f"Response length: {len(response)} bytes")
        print(f"Response hex: {response.hex()}")
        
        # Parse response header
        if len(response) >= 20:
            msg_type, msg_length, magic_cookie = struct.unpack('>HHI', response[:8])
            print(f"Response Message Type: 0x{msg_type:04x}")
            print(f"Response Length: {msg_length}")
            print(f"Magic Cookie: 0x{magic_cookie:08x}")
            
            if msg_type == 0x0101:  # Binding Success Response
                print("✅ Received valid STUN Binding Success Response")
            else:
                print(f"⚠️  Unexpected message type: 0x{msg_type:04x}")
        
        sock.close()
        return True
        
    except socket.timeout:
        print("❌ ERROR: STUN request timed out (no response received)")
        return False
    except socket.gaierror as e:
        print(f"❌ ERROR: DNS resolution failed: {e}")
        return False
    except Exception as e:
        print(f"❌ ERROR: STUN test failed: {e}")
        return False
    finally:
        try:
            sock.close()
        except:
            pass

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 stun_test.py <host> <port>")
        sys.exit(1)
    
    host = sys.argv[1]
    port = int(sys.argv[2])
    
    success = test_stun_server(host, port)
    sys.exit(0 if success else 1)
EOF

echo "Running STUN connectivity test..."
python3 /tmp/stun_test.py ${TURN_HOST} ${TURN_PORT} || echo "STUN test failed"
echo ""

echo "=== 6. Alternative STUN Test with dig ==="
echo "Testing with different IP resolution..."
DIG_IP=$(dig +short ${TURN_HOST} | head -1)
if [ ! -z "$DIG_IP" ]; then
    echo "Dig resolved IP: $DIG_IP"
    if [ "$DIG_IP" != "$TURN_IP" ]; then
        echo "⚠️  WARNING: DNS resolves to different IP than expected!"
        echo "Running STUN test with dig-resolved IP..."
        python3 /tmp/stun_test.py ${DIG_IP} ${TURN_PORT} || echo "STUN test with dig IP failed"
    fi
else
    echo "Dig resolution failed"
fi
echo ""

echo "=== 7. Server Logs Check ==="
echo "Checking recent Fly.io logs for connection attempts..."
fly logs --no-tail -a saturn | tail -20 || echo "Failed to fetch logs"
echo ""

echo "=== 8. Troubleshooting Recommendations ==="
echo ""
echo "Based on the test results above, here are potential causes for Error 701:"
echo ""
echo "1. DNS Issues:"
echo "   - If DNS resolution fails, clients can't find the server"
echo "   - Check if your DNS provider blocks certain domains"
echo ""
echo "2. UDP Blocking:"
echo "   - Many corporate/public networks block UDP traffic"
echo "   - Try from a different network (mobile hotspot, etc.)"
echo ""
echo "3. Firewall/NAT Issues:"
echo "   - Your local firewall might block UDP responses"
echo "   - Router NAT might not handle STUN correctly"
echo ""
echo "4. Fly.io Network Configuration:"
echo "   - UDP service might not be properly exposed"
echo "   - Check fly.toml UDP service configuration"
echo ""
echo "5. Port Issues:"
echo "   - Port 3478 might be blocked by ISP or network"
echo "   - Try testing from different networks"
echo ""
echo "Immediate next steps:"
echo "- If STUN test succeeds, error 701 is likely client-side"
echo "- If STUN test fails, check Fly.io UDP service configuration"
echo "- Test from multiple networks to isolate network-specific issues"
echo "- Check browser console for more detailed error messages"
echo ""
echo "=== Debug script completed ==="
