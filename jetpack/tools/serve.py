#!/usr/bin/env python3
"""Serve the exported Jetpack Arena web build for local smoke tests.

Stdlib only (http.server). Serves <project>/build/web over HTTP and answers
GET /health with ``OK JETPACK`` so CI and humans can smoke-test the real
export. This is NOT a game server. Single-threaded export: sends no
COOP/COEP headers, so any plain static host works.

Usage: python3 tools/serve.py [--port PORT] [--dir DIR]   (run from the jetpack/ directory)
"""
import argparse
import errno
import functools
import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 8000
HEALTH_PATH = "/health"
HEALTH_BODY = b"OK JETPACK"
MAX_POST_BODY = 64 * 1024
WEB_ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build", "web")


class ServeHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
    }

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
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(HEALTH_BODY)))
        self.end_headers()
        if include_body:
            self.wfile.write(HEALTH_BODY)

    def _drain_post_body(self) -> None:
        length = self.headers.get("Content-Length")
        try:
            n = int(str(length).strip())
        except (ValueError, AttributeError):
            n = 0
        remaining = min(max(n, 0), MAX_POST_BODY)
        while remaining > 0:
            try:
                chunk = self.rfile.read(min(remaining, 65536))
            except OSError:
                break
            if not chunk:
                break
            remaining -= len(chunk)

    def _is_health(self) -> bool:
        return self.path.split("?", 1)[0] == HEALTH_PATH

    def do_GET(self) -> None:
        if self._is_health():
            self._serve_health(include_body=True)
        else:
            super().do_GET()

    def do_HEAD(self) -> None:
        if self._is_health():
            self._serve_health(include_body=False)
        else:
            super().do_HEAD()

    def do_POST(self) -> None:
        self._drain_post_body()
        if self._is_health():
            self._serve_health(include_body=True)
        else:
            super().do_GET()

    def log_message(self, format: str, *args: object) -> None:
        pass


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Serve the Jetpack web export for smoke tests.")
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", PORT)))
    parser.add_argument("--dir", default=WEB_ROOT, help="Directory to serve (default: build/web).")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    handler = functools.partial(ServeHandler, directory=args.dir)
    try:
        server = ThreadingHTTPServer((HOST, args.port), handler)
    except OSError as e:
        if e.errno == errno.EADDRINUSE:
            print(
                "jetpack serve: cannot bind %s:%d: address already in use"
                " (port held by another process?)" % (HOST, args.port),
                file=sys.stderr,
                flush=True,
            )
            return 1
        raise
    print("SERVING http://%s:%d/ from %s" % (HOST, args.port, args.dir), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
