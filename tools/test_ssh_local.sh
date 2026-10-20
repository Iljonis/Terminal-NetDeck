#!/bin/bash
# QA opcional con sshd efímero, claves de prueba y HTTP sólo en loopback. No usa el Llavero ni ~/.ssh.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PYQA'
import getpass, http.server, os, pathlib, shutil, socket, subprocess, tempfile, threading, time
root=pathlib.Path(tempfile.mkdtemp(prefix="netdeck-ssh-qa-")); os.chmod(root,0o700)
server=None; daemon=None
try:
    for name in ("client","host","old-host"):
        subprocess.run(["/usr/bin/ssh-keygen","-q","-t","ed25519","-N","","-f",str(root/name)],check=True)
    (root/"authorized_keys").write_bytes((root/"client.pub").read_bytes()); os.chmod(root/"authorized_keys",0o600)
    with socket.socket() as sock:
        sock.bind(("127.0.0.1",0)); port=sock.getsockname()[1]
    (root/"sshd_config").write_text(f"""ListenAddress 127.0.0.1
Port {port}
HostKey {root}/host
PidFile {root}/sshd.pid
AuthorizedKeysFile {root}/authorized_keys
StrictModes no
UsePAM no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AllowTcpForwarding yes
GatewayPorts no
PermitTunnel no
Subsystem sftp /usr/libexec/sftp-server
""")
    for file,key in (("known_hosts","host.pub"),("old_known_hosts","old-host.pub")):
        kind,data,*_=(root/key).read_text().split(); (root/file).write_text(f"[127.0.0.1]:{port} {kind} {data}\n")
    common=f"""  HostName 127.0.0.1
  Port {port}
  User {getpass.getuser()}
  IdentityFile {root}/client
  IdentityAgent none
  IdentitiesOnly yes
  GlobalKnownHostsFile /dev/null
  StrictHostKeyChecking yes
  ConnectTimeout 5
  LogLevel ERROR
"""
    (root/"ssh_config").write_text("Host qa-direct\n"+common+f"  UserKnownHostsFile {root}/known_hosts\n"+
        "Host qa-via\n"+common+f"  UserKnownHostsFile {root}/known_hosts\n  ProxyJump qa-direct\n"+
        "Host qa-mismatch\n"+common+f"  UserKnownHostsFile {root}/old_known_hosts\n")
    log=open(root/"sshd.log","w")
    daemon=subprocess.Popen(["/usr/sbin/sshd","-D","-e","-f",str(root/"sshd_config")],stdout=log,stderr=log)
    ready=False
    for _ in range(50):
        if daemon.poll() is not None: break
        try:
            with socket.create_connection(("127.0.0.1",port),timeout=.1): ready=True; break
        except OSError: time.sleep(.1)
    if not ready: raise RuntimeError("sshd no ha arrancado: "+(root/"sshd.log").read_text())
    check=subprocess.run(["/usr/bin/ssh","-F",str(root/"ssh_config"),"-o","BatchMode=yes","--","qa-direct","true"],capture_output=True,timeout=15)
    if check.returncode: raise RuntimeError("sshd no permite la autenticación de prueba: "+check.stderr.decode(errors="replace"))
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            body=b"netdeck-qa\n"; self.send_response(200); self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
        def log_message(self,*args): pass
    server=http.server.ThreadingHTTPServer(("127.0.0.1",0),Handler)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    env=os.environ.copy(); env["NETDECK_SSH_QA_DIR"]=str(root); env["NETDECK_SSH_QA_HTTP_PORT"]=str(server.server_port)
    result=subprocess.run(["./test.sh","--filter","IntegracionSSHTests"],env=env)
    raise SystemExit(result.returncode)
finally:
    if server: server.shutdown(); server.server_close()
    if daemon:
        daemon.terminate()
        try: daemon.wait(timeout=5)
        except subprocess.TimeoutExpired: daemon.kill(); daemon.wait()
    shutil.rmtree(root)
PYQA
