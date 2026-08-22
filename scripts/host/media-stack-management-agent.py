#!/usr/bin/env python3
"""Restricted Tailscale-only management API for one portable media stack."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import hmac
import json
import os
import subprocess

STACK_DIR = Path(os.environ["STACK_DIR"])
TOKEN = os.environ["MANAGEMENT_AGENT_TOKEN"]
BIND = os.environ["MANAGEMENT_AGENT_BIND"]
PORT = int(os.environ.get("MANAGEMENT_AGENT_PORT", "9876"))


def run_stack(*args):
    completed = subprocess.run(
        [str(STACK_DIR / "squid-media"), *args], cwd=STACK_DIR, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120,
    )
    return completed.returncode, completed.stdout[-12000:]


def stack_status():
    code, output = run_stack("status")
    return {"ok": code == 0, "command": "status", "exit_code": code, "output": output}


class Handler(BaseHTTPRequestHandler):
    server_version = "SquidMediaManagement/1"

    def authorized(self):
        header = self.headers.get("Authorization", "")
        return header.startswith("Bearer ") and hmac.compare_digest(header[7:], TOKEN)

    def reply(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path != "/v1/status":
            self.reply(404, {"error": "not found"}); return
        if not self.authorized():
            self.reply(401, {"error": "unauthorized"}); return
        self.reply(200, {"agent": "portable-media-stack", "stack_dir": str(STACK_DIR), "status": stack_status()})

    def do_POST(self):
        routes = {"/v1/stack/start": "start", "/v1/stack/stop": "stop", "/v1/stack/restart": "restart"}
        action = routes.get(self.path)
        if action is None:
            self.reply(404, {"error": "not found"}); return
        if not self.authorized():
            self.reply(401, {"error": "unauthorized"}); return
        code, output = run_stack(action)
        verified = stack_status()
        self.reply(200 if code == 0 else 500, {"action": action, "ok": code == 0, "exit_code": code, "output": output, "verified_status": verified})

    def log_message(self, format, *args):
        print(f"{self.client_address[0]} {format % args}")


if __name__ == "__main__":
    print(f"Management agent listening on http://{BIND}:{PORT}")
    ThreadingHTTPServer((BIND, PORT), Handler).serve_forever()
