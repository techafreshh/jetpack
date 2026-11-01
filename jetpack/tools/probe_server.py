#!/usr/bin/env python3
"""Factory health probe for the Jetpack Arena walking skeleton.

Stdlib only (http.server). Answers GET /health with exactly ``OK JETPACK``
so factory verification can health-check the lap environment. This is NOT a
game server.
"""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
PORT = 8911
HEALTH_PATH = "/health"
HEALTH_BODY = b"OK JETPACK"


class ProbeHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        if path == HEALTH_PATH:
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(HEALTH_BODY)))
            self.end_headers()
            self.wfile.write(HEALTH_BODY)
        else:
            self.send_error(404, "Not found")

    def log_message(self, format: str, *args: object) -> None:
        pass


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), ProbeHandler)
    print("JETPACK PROBE on http://%s:%d/health" % (HOST, PORT), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
