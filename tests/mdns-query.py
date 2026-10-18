#!/usr/bin/env python3
# minimal mDNS query: python3 mdnsq.py <name.local>  -> prints the A record or nothing
import socket, struct, sys, time
name = sys.argv[1]
q = struct.pack('>HHHHHH', 0, 0, 1, 0, 0, 0) + b''.join(bytes([len(p)]) + p.encode() for p in name.split('.')) + b'\0' + struct.pack('>HH', 1, 0x8001)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
s.settimeout(0.5)
s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
s.bind(('', 0))
end = time.time() + 4
while time.time() < end:
    s.sendto(q, ('224.0.0.251', 5353))
    try:
        d, a = s.recvfrom(2048)
    except socket.timeout:
        continue
    # take the last 4 bytes of the first A answer
    if len(d) > 12 and struct.unpack('>H', d[6:8])[0] > 0:
        print(socket.inet_ntoa(d[-4:]))
        break
