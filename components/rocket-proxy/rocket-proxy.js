/**
 * E-TUNNEL VPN — Rocket Proxy
 * Listens on 127.0.0.1:8081
 * WebSocket upgrade → forwards to SSH on port 22
 */
const http = require('http');
const net  = require('net');

const server = http.createServer((req, res) => {
    res.writeHead(403);
    res.end('Forbidden');
});

server.on('upgrade', (req, socket, head) => {
    socket.setNoDelay(true);
    socket.write(
        'HTTP/1.1 101 Switching Protocols\r\n' +
        'Upgrade: websocket\r\n' +
        'Connection: Upgrade\r\n\r\n'
    );

    const sshSocket = net.connect(22, '127.0.0.1', () => {
        sshSocket.setNoDelay(true);
        if (head && head.length) sshSocket.write(head);
        socket.on('data',  (c) => { if (!sshSocket.destroyed) sshSocket.write(c); });
        sshSocket.on('data', (c) => { if (!socket.destroyed)  socket.write(c); });
        socket.on('end',   () => sshSocket.end());
        sshSocket.on('end', () => socket.end());
        socket.on('error', () => sshSocket.destroy());
        sshSocket.on('error', () => socket.destroy());
    });
});

server.keepAliveTimeout = 65000;
server.headersTimeout   = 66000;
server.listen(8081, '127.0.0.1', () => {
    console.log('E-TUNNEL Rocket Proxy on 127.0.0.1:8081');
});
