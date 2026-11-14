"""
E-TUNNEL VPN — OpenVPN Web Panel
Runs on port 8090
Manage OpenVPN client configs via browser
"""
import os, subprocess, shutil, functools
from flask import Flask, request, render_template_string, send_from_directory, redirect, abort, Response

app = Flask(__name__)

CONFIG_DIR  = "/opt/vpn-panel/configs"
EASYRSA_DIR = "/etc/openvpn/easy-rsa"
os.makedirs(CONFIG_DIR, exist_ok=True)

# Resolve public IP / domain
PUB_IP = os.environ.get('PUB_IP', '')
if not PUB_IP:
    try:
        PUB_IP = subprocess.check_output(
            ['curl', '-s', '--max-time', '3', 'https://api.ipify.org']
        ).decode().strip()
    except Exception:
        PUB_IP = "127.0.0.1"

CUSTOM_DOMAIN = os.environ.get('CUSTOM_DOMAIN', '')
REMOTE        = CUSTOM_DOMAIN if CUSTOM_DOMAIN else PUB_IP
PANEL_USER    = os.environ.get('PANEL_USER', 'etunneladmin')
PANEL_PASS    = os.environ.get('PANEL_PASS', '')


def check_auth(auth):
    if not auth or not PANEL_PASS:
        return False
    return auth.username == PANEL_USER and auth.password == PANEL_PASS


def requires_auth(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        auth = request.authorization
        if not check_auth(auth):
            return Response(
                'Authentication required', 401,
                {'WWW-Authenticate': 'Basic realm="E-TUNNEL VPN Panel"'}
            )
        return f(*args, **kwargs)
    return wrapper


def get_users():
    try:
        skip = ("-ws.ovpn", "-connect.ovpn", "-bhz.ovpn", "-etunnel.ovpn")
        return sorted(
            f.replace(".ovpn", "")
            for f in os.listdir(CONFIG_DIR)
            if f.endswith(".ovpn") and not any(f.endswith(s) for s in skip)
        )
    except Exception:
        return []


HTML = '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>E-TUNNEL VPN Panel</title>
<style>
  body{font-family:Tahoma,sans-serif;background:linear-gradient(135deg,#1a1a2e,#16213e,#0f3460);
       min-height:100vh;display:flex;justify-content:center;padding:20px;margin:0;color:#eee}
  .container{max-width:800px;width:100%;background:rgba(255,255,255,0.07);
             padding:35px;border-radius:20px;border:1px solid rgba(255,255,255,0.1)}
  h2{text-align:center;color:#e94560;margin-bottom:4px}
  .sub{text-align:center;color:#aaa;margin-bottom:24px;font-size:13px}
  .input-group{display:flex;gap:10px;margin:20px 0}
  .input-group input{flex:1;padding:12px;border:1px solid #444;border-radius:10px;
                     background:#1a1a2e;color:#eee}
  .input-group button{padding:12px 24px;background:#e94560;color:white;border:none;
                      border-radius:10px;font-weight:bold;cursor:pointer}
  .user-item{display:flex;justify-content:space-between;padding:12px;
             background:rgba(255,255,255,0.05);border-radius:10px;margin-bottom:8px;
             flex-wrap:wrap;gap:8px;align-items:center}
  .btn{padding:6px 12px;border-radius:8px;text-decoration:none;font-size:12px;color:white}
  .dl{background:#0984e3}.ws{background:#6c5ce7}.cn{background:#e17055}.dl2{background:#00b894}
  .del{background:#d63031}
  h3{color:#e94560}
</style>
</head>
<body>
<div class="container">
  <h2>E-TUNNEL VPN</h2>
  <p class="sub">OpenVPN Panel &mdash; Server: <b>{{ server_ip }}</b></p>
  <form method="POST" action="/create" class="input-group">
    <input type="text" name="username" placeholder="New username" required>
    <button>+ Create</button>
  </form>
  <div style="border-top:1px solid #333;padding-top:20px">
    <h3>Accounts</h3>
    {% if users %}
      {% for user in users %}
      <div class="user-item">
        <span>&#128100; {{ user }}</span>
        <div>
          <a class="btn dl"  href="/download/{{ user }}.ovpn">Direct</a>
          <a class="btn ws"  href="/download/{{ user }}-ws.ovpn">WS</a>
          <a class="btn cn"  href="/download/{{ user }}-connect.ovpn">Connect</a>
          <a class="btn del" href="/delete/{{ user }}"
             onclick="return confirm('Delete {{ user }}?')">Delete</a>
        </div>
      </div>
      {% endfor %}
    {% else %}
      <p style="text-align:center;color:#666">No users yet</p>
    {% endif %}
  </div>
</div>
</body>
</html>'''


def restart_openvpn():
    if os.path.exists("/run/systemd/system"):
        subprocess.run(["systemctl", "restart", "openvpn@server"],
                       capture_output=True, check=False)
    else:
        subprocess.run(["rc-service", "openvpn", "restart"],
                       capture_output=True, check=False)


@app.route('/')
@requires_auth
def index():
    return render_template_string(HTML, users=get_users(), server_ip=REMOTE)


@app.route('/create', methods=['POST'])
@requires_auth
def create_user():
    client = (request.form.get('username', '')
              .strip().replace(" ", "_").replace("..", "_"))
    if not client or '..' in client or '/' in client:
        return redirect('/')
    ovpn_file = os.path.join(CONFIG_DIR, f"{client}.ovpn")
    if os.path.exists(ovpn_file):
        return redirect('/')
    try:
        subprocess.run(
            ["./easyrsa", "--batch", "build-client-full", client, "nopass"],
            capture_output=True, check=False, cwd=EASYRSA_DIR
        )
        ca   = open(os.path.join(EASYRSA_DIR, "pki/ca.crt")).read()
        cert = open(os.path.join(EASYRSA_DIR, f"pki/issued/{client}.crt")).read()
        key  = open(os.path.join(EASYRSA_DIR, f"pki/private/{client}.key")).read()

        base = f"""<ca>\n{ca}</ca>\n<cert>\n{cert}</cert>\n<key>\n{key}</key>\n"""

        # Direct (TLS 443)
        with open(ovpn_file, "w") as f:
            f.write(f"""client\ndev tun\nproto tcp\nremote {REMOTE} 443\n"""
                    f"""connect-retry 1 2\nconnect-timeout 4\nresolv-retry 10\nnobind\n"""
                    f"""persist-key\npersist-tun\nremote-cert-tls server\n"""
                    f"""tls-version-min 1.2\ncipher AES-256-GCM\nauth SHA256\n"""
                    f"""verb 4\nauth-nocache\nreneg-sec 0\ntun-mtu 1500\nmssfix 1400\n"""
                    f"""dhcp-option DNS 1.1.1.1\ndhcp-option DNS 8.8.8.8\n{base}""")

        # WS (port 80)
        with open(os.path.join(CONFIG_DIR, f"{client}-ws.ovpn"), "w") as f:
            f.write(f"""client\ndev tun\nproto tcp\nremote {REMOTE} 80 tcp-client\n"""
                    f"""connect-timeout 4\nnobind\npersist-key\npersist-tun\n"""
                    f"""remote-cert-tls server\ncipher AES-256-GCM\nauth SHA256\n"""
                    f"""verb 4\nauth-nocache\nreneg-sec 0\ntun-mtu 1500\nmssfix 1400\n"""
                    f"""dhcp-option DNS 1.1.1.1\ndhcp-option DNS 8.8.8.8\n{base}""")

        # HTTP Connect
        with open(os.path.join(CONFIG_DIR, f"{client}-connect.ovpn"), "w") as f:
            f.write(f"""client\ndev tun\nproto tcp\nremote {REMOTE} 443 tcp-client\n"""
                    f"""http-proxy {REMOTE} 80\n"""
                    f"""http-proxy-option CUSTOM-HEADER Host domain.com\n"""
                    f"""auth-nocache\nresolv-retry infinite\nroute-method exe\n"""
                    f"""cipher AES-128-CBC\nnobind\npersist-key\npersist-tun\n"""
                    f"""remote-cert-tls server\nverb 3\n{base}""")

    except Exception as e:
        print(f"Error creating {client}: {e}")
    return redirect('/')


@app.route('/delete/<username>')
@requires_auth
def delete_user(username):
    if '..' in username or '/' in username:
        abort(400)
    if not username.replace('_', '').replace('-', '').isalnum():
        abort(400)
    for suffix in ['', '-ws', '-connect']:
        f = os.path.join(CONFIG_DIR, f"{username}{suffix}.ovpn")
        if os.path.exists(f):
            os.remove(f)
    try:
        subprocess.run(["./easyrsa", "--batch", "revoke", username],
                       capture_output=True, check=False, cwd=EASYRSA_DIR)
        subprocess.run(["./easyrsa", "gen-crl"],
                       capture_output=True, check=False, cwd=EASYRSA_DIR)
        crl_src = os.path.join(EASYRSA_DIR, "pki/crl.pem")
        if os.path.exists(crl_src):
            shutil.copy(crl_src, "/etc/openvpn/keys/crl.pem")
        restart_openvpn()
    except Exception:
        pass
    return redirect('/')


@app.route('/download/<filename>')
@requires_auth
def download_file(filename):
    if '..' in filename or not filename.endswith('.ovpn'):
        abort(400)
    return send_from_directory(CONFIG_DIR, filename, as_attachment=True)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8090, debug=False, threaded=True)
