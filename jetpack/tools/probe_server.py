#!/usr/bin/env python3
"""Factory health probe for the Jetpack Arena walking skeleton.

Stdlib only (http.server). Answers GET, HEAD, and POST on /health with
``OK JETPACK`` (HEAD sends headers only, no body) so factory verification
can health-check the lap environment via any of those methods. This is NOT
a game server.
"""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import errno
import select
import sys

HOST = "127.0.0.1"
PORT = 8911
HEALTH_PATH = "/health"
HEALTH_BODY = b"OK JETPACK"
MAX_POST_BODY = 64 * 1024


class ProbeHandler(BaseHTTPRequestHandler):
    def _force_status_line(self) -> None:
        # BaseHTTPRequestHandler defaults to HTTP/0.9 until the request
        # line is parsed, and then omits the status line entirely. A raw
        # socket probe (e.g. bad-encoding path, missing/unsupported
        # version) would get a body with no status, parsed as "". Force
        # HTTP/1.0 so every response carries a status line.
        if getattr(self, "request_version", "HTTP/1.0") == "HTTP/0.9":
            self.request_version = "HTTP/1.0"

    def send_error(self, code: int, message: str | None = None, explain: str | None = None) -> None:
        self._force_status_line()
        # The probe must never see a 5xx: unknown methods (501) and
        # unsupported versions (505) are rejected as 404 like any
        # unknown path.
        if 500 <= code <= 599:
            code = 404
            message = "Not found"
            explain = None
        super().send_error(code, message, explain)

    def _serve_health(self, include_body: bool) -> None:
        self._force_status_line()
        path = self.path.split("?", 1)[0]
        if path == HEALTH_PATH:
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(HEALTH_BODY)))
            self.end_headers()
            if include_body:
                self.wfile.write(HEALTH_BODY)
        else:
            self.send_error(404, "Not found")

    def do_GET(self) -> None:
        self._serve_health(include_body=True)

    def do_HEAD(self) -> None:
        self._serve_health(include_body=False)

    def do_POST(self) -> None:
        length = self.headers.get("Content-Length")
        try:
            n = int(str(length).strip())
        except (ValueError, AttributeError):
            n = 0
        remaining = min(max(n, 0), MAX_POST_BODY)
        while remaining > 0:
            try:
                ready, _, _ = select.select([self.connection], [], [], 0)
            except OSError:
                break
            if not ready:
                break
            try:
                chunk = self.rfile.read(min(remaining, 65536))
            except OSError:
                break
            if not chunk:
                break
            remaining -= len(chunk)
        self._serve_health(include_body=True)

    def log_message(self, format: str, *args: object) -> None:
        pass


def main() -> int:
    try:
        server = ThreadingHTTPServer((HOST, PORT), ProbeHandler)
    except OSError as e:
        if e.errno == errno.EADDRINUSE:
            print(
                "jetpack probe: cannot bind %s:%d: address already in use"
                " (port held by another process?)" % (HOST, PORT),
                file=sys.stderr,
                flush=True,
            )
            return 1
        raise
    print("JETPACK PROBE on http://%s:%d/health" % (HOST, PORT), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
