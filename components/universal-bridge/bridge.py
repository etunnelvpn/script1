#!/usr/bin/env python3
"""
E-TUNNEL VPN — Universal Bridge
Listens on 127.0.0.1:8080
Routes: SSH, OpenVPN (CONNECT), OpenVPN (WebSocket)
"""
import asyncio, hashlib, base64, socket

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

def make_accept_key(key):
    return base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()

async def read_payload(reader, timeout=1.0, idle=0.3):
    data = b""
    deadline = asyncio.get_event_loop().time() + timeout
    while asyncio.get_event_loop().time() < deadline:
        try:
            chunk = await asyncio.wait_for(reader.read(4096), timeout=idle)
            if not chunk: break
            data += chunk
            deadline = asyncio.get_event_loop().time() + timeout
        except asyncio.TimeoutError:
            break
    return data

async def handle_client(cr, cw):
    peer = cw.get_extra_info('peername')
    print(f"[+] New: {peer}", flush=True)
    try:
        sock = cw.get_extra_info('socket')
        if sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except: pass

    payload = await read_payload(cr, 1.0, 0.3)
    if not payload:
        cw.close(); return

    first = payload.split(b'\r\n', 1)[0].decode('utf-8', errors='ignore')
    forward_first = b""; target = None; proto = ""

    if first.startswith('CONNECT '):
        cw.write(b'HTTP/1.1 200 Connection established\r\nProxy-Agent: E-TUNNEL\r\n\r\n')
        await cw.drain()
        target = ('127.0.0.1', 1194); proto = "OpenVPN-CONNECT"
        try: forward_first = await asyncio.wait_for(cr.read(64), timeout=3)
        except: pass
    else:
        ws_key = 'dGhlIHNhbXBsZSBub25jZQ=='
        try:
            for line in payload.decode('utf-8', errors='ignore').split('\r\n'):
                if ':' in line:
                    k, v = line.split(':', 1)
                    if k.strip().lower() == 'sec-websocket-key':
                        ws_key = v.strip(); break
        except: pass
        cw.write(('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n'
                  'Connection: Upgrade\r\nSec-WebSocket-Accept: ' +
                  make_accept_key(ws_key) + '\r\n\r\n').encode())
        await cw.drain()
        try: forward_first = await asyncio.wait_for(cr.read(64), timeout=5)
        except: pass
        if forward_first.startswith(b'SSH-'):
            target = ('127.0.0.1', 22); proto = "SSH"
        else:
            target = ('127.0.0.1', 1194); proto = "OpenVPN-WS"

    try:
        tr, tw = await asyncio.open_connection(*target)
        ts = tw.get_extra_info('socket')
        if ts:
            ts.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            ts.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except Exception as e:
        print(f"[!] {proto} fail: {e}", flush=True); cw.close(); return

    if forward_first:
        try: tw.write(forward_first); await tw.drain()
        except: pass

    print(f"[+] Active: {peer} <-> {proto}", flush=True)

    async def pump(src, dst):
        try:
            while True:
                try: data = await asyncio.wait_for(src.read(65536), timeout=600)
                except asyncio.TimeoutError: continue
                if not data: break
                try: dst.write(data); await dst.drain()
                except: break
        except: pass

    try:
        await asyncio.gather(pump(cr, tw), pump(tr, cw))
    finally:
        try: tw.close()
        except: pass
        try: cw.close()
        except: pass
        print(f"[-] Closed: {peer} ({proto})", flush=True)

async def main():
    server = await asyncio.start_server(handle_client, '127.0.0.1', 8080)
    print("E-TUNNEL Universal Bridge on 127.0.0.1:8080", flush=True)
    async with server:
        await server.serve_forever()

if __name__ == '__main__':
    try: asyncio.run(main())
    except KeyboardInterrupt: pass
