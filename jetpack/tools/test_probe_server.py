"""Black-box tests for probe_server using the real HTTP server (stdlib only)."""

import errno
import http.client
import socket
import subprocess
import sys
import threading
import time
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path

try:
    from jetpack.tools.probe_server import HEALTH_BODY, HEALTH_PATH, ProbeHandler, HOST, PORT
except ImportError:
    from probe_server import HEALTH_BODY, HEALTH_PATH, ProbeHandler, HOST, PORT

PROBE_SCRIPT = Path(__file__).with_name("probe_server.py")


class ProbeServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), ProbeHandler)
        cls.port = cls.server.server_address[1]
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def request(self, method: str, path: str, body: bytes | None = None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            conn.request(method, path, body=body)
            resp = conn.getresponse()
            return resp.status, dict(resp.getheaders()), resp.read()
        finally:
            conn.close()

    def raw_post(self, content_length: str):
        req = (
            "POST %s HTTP/1.1\r\n"
            "Host: 127.0.0.1\r\n"
            "Content-Length: %s\r\n"
            "Connection: close\r\n"
            "\r\n"
        ) % (HEALTH_PATH, content_length)
        start = time.monotonic()
        s = socket.create_connection(("127.0.0.1", self.port), timeout=5)
        try:
            s.settimeout(5)
            s.sendall(req.encode("ascii"))
            chunks = []
            while True:
                try:
                    data = s.recv(65536)
                except socket.timeout:
                    break
                if not data:
                    break
                chunks.append(data)
        finally:
            s.close()
        return time.monotonic() - start, b"".join(chunks)

    def test_post_negative_content_length_responds_quickly(self) -> None:
        elapsed, raw = self.raw_post("-1")
        self.assertLess(elapsed, 3, "negative Content-Length blocked handler")
        self.assertIn(b"200", raw.split(b"\r\n", 1)[0])
        self.assertTrue(raw.endswith(HEALTH_BODY), raw)
        self.assertNotIn(b"Traceback", raw)

    def test_post_huge_content_length_responds_quickly(self) -> None:
        elapsed, raw = self.raw_post("99999999999")
        self.assertLess(elapsed, 3, "huge Content-Length blocked handler")
        self.assertIn(b"200", raw.split(b"\r\n", 1)[0])
        self.assertTrue(raw.endswith(HEALTH_BODY), raw)
        self.assertNotIn(b"Traceback", raw)

    def test_post_small_lie_content_length_responds_quickly(self) -> None:
        elapsed, raw = self.raw_post("16")
        self.assertLess(elapsed, 3, "small-lie Content-Length blocked handler")
        self.assertIn(b"200", raw.split(b"\r\n", 1)[0])
        self.assertTrue(raw.endswith(HEALTH_BODY), raw)
        self.assertNotIn(b"Traceback", raw)

    def test_handler_alive_after_bogus_lengths(self) -> None:
        for bogus in ("-1", "99999999999", "16"):
            self.raw_post(bogus)
        status, _, body = self.request("GET", HEALTH_PATH)
        self.assertEqual(status, 200)
        self.assertEqual(body, HEALTH_BODY)

    def test_get_health(self) -> None:
        status, headers, body = self.request("GET", HEALTH_PATH)
        self.assertEqual(status, 200)
        self.assertEqual(body, HEALTH_BODY)
        self.assertEqual(headers.get("Content-Type"), "text/plain")
        self.assertEqual(headers.get("Content-Length"), str(len(HEALTH_BODY)))

    def test_get_health_query(self) -> None:
        status, _, body = self.request("GET", HEALTH_PATH + "?x=1")
        self.assertEqual(status, 200)
        self.assertEqual(body, HEALTH_BODY)

    def test_head_health(self) -> None:
        status, headers, body = self.request("HEAD", HEALTH_PATH)
        self.assertEqual(status, 200)
        self.assertEqual(body, b"")
        self.assertEqual(headers.get("Content-Type"), "text/plain")
        self.assertEqual(headers.get("Content-Length"), str(len(HEALTH_BODY)))

    def test_post_health_empty(self) -> None:
        status, _, body = self.request("POST", HEALTH_PATH)
        self.assertEqual(status, 200)
        self.assertEqual(body, HEALTH_BODY)

    def test_post_health_with_body(self) -> None:
        status, _, body = self.request("POST", HEALTH_PATH, body=b"x=1")
        self.assertEqual(status, 200)
        self.assertEqual(body, HEALTH_BODY)

    def test_unknown_paths_404(self) -> None:
        for method in ("GET", "HEAD", "POST"):
            status, _, _ = self.request(method, "/other")
            self.assertEqual(status, 404, method)

    def test_no_501(self) -> None:
        for method, path in (
            ("GET", HEALTH_PATH),
            ("HEAD", HEALTH_PATH),
            ("POST", HEALTH_PATH),
        ):
            status, _, _ = self.request(method, path)
            self.assertNotEqual(status, 501, f"{method} {path}")


def _port_is_free() -> bool:
    """True if PORT can be bound right now; False if already taken."""
    s = socket.socket()
    try:
        # SO_REUSEADDR mirrors ThreadingHTTPServer: stale TIME_WAIT alone
        # must not count as "taken", only a live listener does.
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((HOST, PORT))
        return True
    except OSError as e:
        if e.errno == errno.EADDRINUSE:
            return False
        raise
    finally:
        s.close()


class OccupiedPortTest(unittest.TestCase):
    """Second probe on an occupied port must fail cleanly, not traceback."""

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
                [sys.executable, str(PROBE_SCRIPT)],
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
    """With the port free the probe must serve /health end to end."""

    def test_free_port_serves_health(self) -> None:
        if not _port_is_free():
            self.skipTest("port %d already taken in this environment" % PORT)
        proc = subprocess.Popen(
            [sys.executable, str(PROBE_SCRIPT)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            banner = proc.stdout.readline() if proc.stdout else ""
            self.assertIn("JETPACK PROBE", banner)
            deadline = time.time() + 10
            body: bytes | None = None
            status: int | None = None
            while time.time() < deadline:
                try:
                    conn = http.client.HTTPConnection(HOST, PORT, timeout=2)
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
