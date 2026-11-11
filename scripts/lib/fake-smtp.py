#!/usr/bin/env python3
"""A tiny fake SMTP server for the tests: no TLS, AUTH PLAIN and LOGIN accepted, every message captured to a file.

  python3 -I scripts/lib/fake-smtp.py PORT CAPTURE_FILE [--reject-auth]

Writes one JSON object per received message (auth user and password, MAIL FROM, RCPT TO, the data) to CAPTURE_FILE.
--reject-auth answers 535 to any login. Tests only: it listens on 127.0.0.1.
"""
import base64
import json
import socketserver
import sys

port, capture = int(sys.argv[1]), sys.argv[2]
reject = "--reject-auth" in sys.argv


class H(socketserver.StreamRequestHandler):
    def send(self, s):
        self.wfile.write((s + "\r\n").encode())
        self.wfile.flush()

    def line(self):
        return self.rfile.readline().decode(errors="replace").rstrip("\r\n")

    def handle(self):
        st = {"user": None, "pass": None, "from": None, "to": []}
        self.send("220 fake ESMTP")
        while True:
            l = self.line()
            if not l:
                return
            u = l.upper()
            if u.startswith("EHLO") or u.startswith("HELO"):
                self.wfile.write(b"250-fake\r\n250-AUTH PLAIN LOGIN\r\n250 OK\r\n"); self.wfile.flush()
            elif u.startswith("AUTH LOGIN"):
                self.send("334 VXNlcm5hbWU6"); st["user"] = base64.b64decode(self.line()).decode()
                self.send("334 UGFzc3dvcmQ6"); st["pass"] = base64.b64decode(self.line()).decode()
                self.send("535 authentication failed" if reject else "235 ok")
            elif u.startswith("AUTH PLAIN"):
                parts = base64.b64decode(l.split(None, 2)[2]).decode().split("\0")
                st["user"], st["pass"] = parts[1], parts[2]
                self.send("535 authentication failed" if reject else "235 ok")
            elif u.startswith("MAIL FROM"):
                st["from"] = l.split(":", 1)[1].strip(); self.send("250 ok")
            elif u.startswith("RCPT TO"):
                st["to"].append(l.split(":", 1)[1].strip()); self.send("250 ok")
            elif u == "DATA":
                self.send("354 go")
                data = []
                while True:
                    d = self.rfile.readline().decode(errors="replace")
                    if d.rstrip("\r\n") == "." or not d:
                        break
                    data.append(d)
                st["data"] = "".join(data)
                with open(capture, "a") as f:
                    f.write(json.dumps(st) + "\n")
                self.send("250 queued")
            elif u == "QUIT":
                self.send("221 bye"); return
            elif u == "RSET" or u == "NOOP":
                self.send("250 ok")
            else:
                self.send("250 ok")


class S(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


S(("127.0.0.1", port), H).serve_forever()
