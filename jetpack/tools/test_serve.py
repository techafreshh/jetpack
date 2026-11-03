"""Black-box tests for serve.py using the real HTTP server (stdlib only)."""

import errno
import functools
import http.client
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path

try:
    from jetpack.tools.serve import HEALTH_BODY, HEALTH_PATH, ServeHandler, HOST, PORT
except ImportError:
    try:
        from tools.serve import HEALTH_BODY, HEALTH_PATH, ServeHandler, HOST, PORT
    except ImportError:
        from serve import HEALTH_BODY, HEALTH_PATH, ServeHandler, HOST, PORT

SERVE_SCRIPT = Path(__file__).with_name("serve.py")


class ServeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = tempfile.TemporaryDirectory()
        root = Path(cls.tmp.name)
        (root / "index.html").write_bytes(b"<html><body>jetpack</body></html>")
        (root / "game.wasm").write_bytes(b"\x00asm-wasm-fixture")
        (root / "game.pck").write_bytes(b"PCK-fixture")
        handler = functools.partial(ServeHandler, directory=str(root))
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        cls.port = cls.server.server_address[1]
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()
        cls.tmp.cleanup()

    def request(self, method: str, path: str, body: bytes | None = None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            conn.request(method, path, body=body)
            resp = conn.getresponse()
            # Lowercase keys: the stdlib static handler sends
            # "Content-type" while the health endpoint sends "Content-Type".
            return resp.status, {k.lower(): v for k, v in resp.getheaders()}, resp.read()
        finally:
            conn.close()

    def test_get_health(self) -> None:
        status, headers, body = self.request("GET", HEALTH_PATH)
        self.assertEqual(status, 200)
        self.assertEqual(body, HEALTH_BODY)
        self.assertEqual(headers.get("content-type"), "text/plain")
        self.assertEqual(headers.get("content-length"), str(len(HEALTH_BODY)))

    def test_get_health_query(self) -> None:
        status, _, body = self.request("GET", HEALTH_PATH + "?x=1")
        self.assertEqual(status, 200)
        self.assertEqual(body, HEALTH_BODY)

    def test_head_health(self) -> None:
        status, headers, body = self.request("HEAD", HEALTH_PATH)
        self.assertEqual(status, 200)
        self.assertEqual(body, b"")
        self.assertEqual(headers.get("content-type"), "text/plain")
        self.assertEqual(headers.get("content-length"), str(len(HEALTH_BODY)))

    def test_post_health_empty(self) -> None:
        status, _, body = self.request("POST", HEALTH_PATH)
        self.assertEqual(status, 200)
        self.assertEqual(body, HEALTH_BODY)

    def test_post_health_with_body(self) -> None:
        status, _, body = self.request("POST", HEALTH_PATH, body=b"x=1")
        self.assertEqual(status, 200)
        self.assertEqual(body, HEALTH_BODY)

    def test_get_index(self) -> None:
        status, headers, body = self.request("GET", "/")
        self.assertEqual(status, 200)
        self.assertIn(b"jetpack", body)
        self.assertEqual(headers.get("content-type"), "text/html")

    def test_get_wasm_mime(self) -> None:
        status, headers, body = self.request("GET", "/game.wasm")
        self.assertEqual(status, 200)
        self.assertEqual(body, b"\x00asm-wasm-fixture")
        self.assertEqual(headers.get("content-type"), "application/wasm")

    def test_get_pck_mime(self) -> None:
        status, headers, body = self.request("GET", "/game.pck")
        self.assertEqual(status, 200)
        self.assertEqual(body, b"PCK-fixture")
        self.assertEqual(headers.get("content-type"), "application/octet-stream")

    def test_missing_path_404(self) -> None:
        status, _, _ = self.request("GET", "/does-not-exist.png")
        self.assertEqual(status, 404)

    def test_no_501(self) -> None:
        for method, path in (
            ("GET", HEALTH_PATH),
            ("HEAD", HEALTH_PATH),
            ("POST", HEALTH_PATH),
            ("GET", "/"),
        ):
            status, _, _ = self.request(method, path)
            self.assertNotEqual(status, 501, f"{method} {path}")

    def test_no_coop_coep_headers(self) -> None:
        for path in (HEALTH_PATH, "/", "/game.wasm"):
            _, headers, _ = self.request("GET", path)
            lowered = {k.lower() for k in headers}
            self.assertNotIn("cross-origin-opener-policy", lowered, path)
            self.assertNotIn("cross-origin-embedder-policy", lowered, path)


def _free_port() -> int:
    """Return a currently-free loopback port (TOCTOU-safe enough for tests)."""
    s = socket.socket()
    try:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]
    finally:
        s.close()


class OccupiedPortTest(unittest.TestCase):
    """A second serve on an occupied port must fail cleanly, not traceback."""

    def test_occupied_port_exits_1_with_clean_diagnostic(self) -> None:
        holder = socket.socket()
        try:
            holder.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            holder.bind((HOST, PORT))
        except OSError as e:
            if e.errno == errno.EADDRINUSE:
                self.skipTest("port %d already taken in this environment" % PORT)
            raise
        holder.listen(1)
        try:
            proc = subprocess.run(
                [sys.executable, str(SERVE_SCRIPT)],
                capture_output=True,
                text=True,
                timeout=15,
            )
        finally:
            holder.close()
        self.assertEqual(proc.returncode, 1, "stderr was: %r" % proc.stderr)
        self.assertIn(str(PORT), proc.stderr)
        self.assertIn("already in use", proc.stderr)
        self.assertNotIn("Traceback", proc.stdout)
        self.assertNotIn("Traceback", proc.stderr)


class FreePortSmokeTest(unittest.TestCase):
    """With a free port the server must serve /health end to end."""

    def test_free_port_serves_health(self) -> None:
        port = _free_port()
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "index.html").write_bytes(b"<html>smoke</html>")
            proc = subprocess.Popen(
                [sys.executable, str(SERVE_SCRIPT), "--port", str(port), "--dir", tmp],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            try:
                banner = proc.stdout.readline() if proc.stdout else ""
                self.assertIn("SERVING", banner)
                deadline = time.time() + 10
                body: bytes | None = None
                status: int | None = None
                while time.time() < deadline:
                    try:
                        conn = http.client.HTTPConnection(HOST, port, timeout=2)
                        try:
                            conn.request("GET", HEALTH_PATH)
                            resp = conn.getresponse()
                            status = resp.status
                            body = resp.read()
                        finally:
                            conn.close()
                        break
                    except OSError:
                        time.sleep(0.1)
                self.assertEqual(status, 200)
                self.assertEqual(body, HEALTH_BODY)
            finally:
                proc.terminate()
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=10)
                finally:
                    if proc.stdout:
                        proc.stdout.close()
                    if proc.stderr:
                        proc.stderr.close()


if __name__ == "__main__":
    unittest.main()
